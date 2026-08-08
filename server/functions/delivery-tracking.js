/* eslint-disable max-len, require-jsdoc */
"use strict";

const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue, GeoPoint} = require("firebase-admin/firestore");
const tracking = require("./sender-tracking-state-core");
const {evaluateRoadCharges} = require("./road-charges-core");
const {highestTrustAward} = require("./trust-award");

function text(value) {
  return `${value || ""}`.trim();
}

function normalized(value) {
  return tracking.normalizeStatus(value);
}

function firstDefined(...values) {
  for (const value of values) {
    if (value !== undefined && value !== null) return value;
  }
  return undefined;
}

function liveLocationPatch(location) {
  if (!location || typeof location !== "object") return {};
  const lat = Number(firstDefined(location.latitude, location.lat));
  const lng = Number(firstDefined(location.longitude, location.lng));
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return {};
  const heading = Number(firstDefined(location.heading, location.bearing));
  const speed = Number(location.speed);
  return {
    riderLiveLocation: {
      geopoint: new GeoPoint(lat, lng),
      latitude: lat,
      longitude: lng,
      ...(Number.isFinite(heading) ? {heading} : {}),
      ...(Number.isFinite(speed) ? {speed} : {}),
      updatedAt: FieldValue.serverTimestamp(),
    },
  };
}

function signalQuality(accuracy) {
  const value = Number(accuracy);
  if (!Number.isFinite(value) || value <= 0) return "unknown";
  if (value <= 25) return "high";
  if (value <= 80) return "medium";
  return "reduced";
}

function validatedLiveLocation(input) {
  const location = input && typeof input === "object" ? input : {};
  const lat = Number(firstDefined(location.latitude, location.lat));
  const lng = Number(firstDefined(location.longitude, location.lng));
  if (!Number.isFinite(lat) || !Number.isFinite(lng) ||
      lat < -90 || lat > 90 || lng < -180 || lng > 180) {
    throw new functions.https.HttpsError("invalid-argument", "A valid rider location is required.");
  }
  const accuracy = Number(firstDefined(location.accuracyMeters, location.accuracy, 0));
  if (!Number.isFinite(accuracy) || accuracy <= 0 || accuracy > 250) {
    throw new functions.https.HttpsError("failed-precondition", "GPS accuracy is not reliable enough for live tracking.");
  }
  const heading = Number(firstDefined(location.heading, location.bearing));
  const speed = Number(location.speed);
  const clientRecordedAt = Number(firstDefined(location.clientRecordedAt, location.updatedAt, Date.now()));
  return {
    latitude: lat,
    longitude: lng,
    accuracy,
    heading: Number.isFinite(heading) ? heading : 0,
    speed: Number.isFinite(speed) ? speed : 0,
    clientRecordedAt,
    gpsStatus: text(location.gpsStatus || (accuracy <= 80 ? "active" : "poorAccuracy")),
    gpsSignalQuality: text(location.gpsSignalQuality || signalQuality(accuracy)),
    mocked: location.mocked === true || location.isMocked === true,
    backgroundCapable: location.backgroundCapable === true,
    queueDepth: Math.max(0, Number(location.queueDepth || 0)),
  };
}

function timestampMs(value) {
  if (!value) return 0;
  if (typeof value.toMillis === "function") return value.toMillis();
  if (value instanceof Date) return value.getTime();
  if (typeof value === "number") return value;
  return 0;
}

function distanceMeters(a, b) {
  if (!a || !b) return Number.POSITIVE_INFINITY;
  const lat1 = Number(firstDefined(a.latitude, a.lat));
  const lon1 = Number(firstDefined(a.longitude, a.lng));
  const lat2 = Number(firstDefined(b.latitude, b.lat));
  const lon2 = Number(firstDefined(b.longitude, b.lng));
  if (![lat1, lon1, lat2, lon2].every(Number.isFinite)) return Number.POSITIVE_INFINITY;
  const radians = (deg) => deg * Math.PI / 180;
  const dLat = radians(lat2 - lat1);
  const dLon = radians(lon2 - lon1);
  const rLat1 = radians(lat1);
  const rLat2 = radians(lat2);
  const h = Math.sin(dLat / 2) ** 2 +
    Math.cos(rLat1) * Math.cos(rLat2) * Math.sin(dLon / 2) ** 2;
  return 6371000 * 2 * Math.atan2(Math.sqrt(h), Math.sqrt(1 - h));
}

function headingDelta(a, b) {
  const h1 = Number(a);
  const h2 = Number(b);
  if (!Number.isFinite(h1) || !Number.isFinite(h2)) return 0;
  const delta = Math.abs(((h2 - h1 + 540) % 360) - 180);
  return delta;
}

function shouldWriteLiveLocation(previous, next, nowMs = Date.now()) {
  if (!next || !next.riderLiveLocation) return false;
  const previousLocation = previous && previous.riderLiveLocation;
  if (!previousLocation) return true;
  const ageMs = nowMs - timestampMs(previousLocation.updatedAt);
  if (ageMs < 10000) return false;
  const moved = distanceMeters(previousLocation, next.riderLiveLocation);
  const turned = headingDelta(previousLocation.heading, next.riderLiveLocation.heading);
  if (moved >= 25 || turned >= 15) return true;
  return ageMs >= 30000;
}

async function findDelivery(db, transaction, deliveryId) {
  const directRef = db.collection("deliveryRequests").doc(deliveryId);
  const direct = await transaction.get(directRef);
  if (direct.exists) return {ref: directRef, id: direct.id, data: direct.data()};

  const query = await transaction.get(
      db.collection("deliveryRequests")
          .where("requestId", "==", deliveryId)
          .limit(1),
  );
  if (query.empty) return null;
  const doc = query.docs[0];
  return {ref: doc.ref, id: doc.id, data: doc.data()};
}

function assertRiderOwnsDelivery(delivery, riderId) {
  const assigned = text(
      delivery.riderId ||
      delivery.driverId ||
      delivery.assignedRiderId ||
      delivery.assignedDriverId,
  );
  if (!assigned || assigned !== riderId) {
    throw new functions.https.HttpsError("permission-denied", "Only the assigned rider can update this delivery.");
  }
}

function assertRiderOperational(rider = {}) {
  const state = normalized(
      rider.accountState || rider.accountStatus || rider.status || rider.approvalStatus,
  );
  if (["suspended", "frozen", "closed", "rejected"].includes(state)) {
    throw new functions.https.HttpsError(
        "failed-precondition",
        "This rider account cannot perform delivery actions.",
    );
  }
}

function expectedPin(privateDelivery, action) {
  const protection = privateDelivery.vanguardProtection || {};
  if (action === "verify_collection_pin") {
    return text(privateDelivery.collectionPin || privateDelivery.pickupPin || protection.collectionPin);
  }
  if (action === "verify_receiver_pin") {
    return text(privateDelivery.deliveryPin || privateDelivery.receiverPin || privateDelivery.dropoffPin || protection.deliveryPin);
  }
  return "";
}

function pinAuthorityRequired(delivery, action) {
  if (action !== "verify_collection_pin" && action !== "verify_receiver_pin") return false;
  const protection = delivery.vanguardProtection || {};
  return delivery.vanguardProtocolEnabled === true ||
    delivery.vanguardEnabled === true ||
    delivery.requiresVanguard === true ||
    protection.enabled === true;
}

function pinAttemptField(action) {
  return action === "verify_receiver_pin" ?
    "deliveryPinAttemptCount" : "collectionPinAttemptCount";
}

function evidenceRequirements(delivery, action, evidence = {}) {
  const pickup = action === "verify_collection_pin";
  const handover = action === "verify_receiver_pin";
  if (!pickup && !handover) return {valid: true};
  const required = pickup ?
    delivery.verificationRequired === true ||
      delivery.requiresVerification === true ||
      delivery.requiresVanguard === true :
    delivery.deliveryPhotoRequired === true ||
      delivery.requiresVanguard === true ||
      delivery.secureHandoverRequired === true;
  if (!required) return {valid: true};
  if (!text(evidence.photoUrl)) return {valid: false, reason: "A delivery evidence photo is required."};
  if (pickup && evidence.conditionConfirmed !== true) {
    return {valid: false, reason: "Parcel condition must be confirmed."};
  }
  if (pickup && evidence.riderDeclarationAccepted !== true) {
    return {valid: false, reason: "Rider declaration is required."};
  }
  if (pickup && delivery.weightVerificationRequired === true &&
      !(Number(evidence.actualWeightKg) > 0)) {
    return {valid: false, reason: "Actual parcel weight is required."};
  }
  if (handover && !text(evidence.recipientName) && evidence.recipientConfirmed !== true) {
    return {valid: false, reason: "Recipient confirmation is required."};
  }
  return {valid: true};
}

function settlementValues(delivery = {}, roadReimbursementOverride = null) {
  const base = Number(
      delivery.riderEarning ||
      delivery.estimatedEarnings ||
      delivery.riderShare ||
      delivery.riderPayout ||
      0,
  );
  const breakdown = delivery.riderEarningBreakdown || {};
  const tip = Number(breakdown.tip || delivery.riderTip || delivery.tipAmount || 0);
  const waiting = Number(breakdown.waiting || delivery.riderWaitingEarning || delivery.noShowEarning || 0);
  const adjustment = Number(breakdown.adjustment || delivery.riderAdjustment || 0);
  const storedRoadReimbursement = Number(
      delivery.roadChargeReimbursement ||
      delivery.roadChargeBreakdown && delivery.roadChargeBreakdown.riderReimbursement ||
      0,
  );
  const roadReimbursement = roadReimbursementOverride == null ?
    storedRoadReimbursement : Number(roadReimbursementOverride);
  const amount = (Number.isFinite(base) ? base : 0) +
    (Number.isFinite(roadReimbursement) ? roadReimbursement : 0);
  return {
    amount: Number.isFinite(amount) && amount > 0 ? Math.round(amount * 100) / 100 : 0,
    deliveryAmount: Math.max(0, Math.round((amount - tip - waiting - adjustment - roadReimbursement) * 100) / 100),
    roadReimbursement: Number.isFinite(roadReimbursement) ? Math.round(roadReimbursement * 100) / 100 : 0,
    tip: Number.isFinite(tip) ? Math.round(tip * 100) / 100 : 0,
    waiting: Number.isFinite(waiting) ? Math.round(waiting * 100) / 100 : 0,
    adjustment: Number.isFinite(adjustment) ? Math.round(adjustment * 100) / 100 : 0,
    trustPoints: highestTrustAward(delivery),
  };
}

function canonicalRiderRankForTrust(trustPoints) {
  const trust = Number(trustPoints);
  if (!Number.isFinite(trust) || trust < 100) return "agent";
  if (trust < 300) return "sentinel";
  if (trust < 700) return "warden";
  if (trust < 1500) return "knight";
  return "veteran";
}

function hasManualRankOverride(profile = {}) {
  return profile.rankOverride === true ||
    `${profile.rankSource || ""}`.toLowerCase() === "manual" ||
    text(profile.rankUpdatedBy) ||
    text(profile.rankReason);
}

function riderTrustRankPatch(profile = {}, awardedTrustPoints = 0) {
  const currentTrust = Number(profile.trustPoints || profile.riderTrustPoints || 0);
  const awarded = Number(awardedTrustPoints);
  const trustPoints = Math.max(0, (Number.isFinite(currentTrust) ? currentTrust : 0) +
    (Number.isFinite(awarded) ? awarded : 0));
  const patch = {
    trustPoints: FieldValue.increment(awardedTrustPoints),
    updatedAt: FieldValue.serverTimestamp(),
  };
  if (!hasManualRankOverride(profile)) {
    patch.riderRank = canonicalRiderRankForTrust(trustPoints);
    patch.rank = patch.riderRank;
    patch.rankSource = "trust_points";
    patch.rankUpdatedAt = FieldValue.serverTimestamp();
  }
  return patch;
}

function patchForTransition({action, nextStatus, riderId}) {
  const now = FieldValue.serverTimestamp();
  const patch = {
    status: nextStatus,
    deliveryStatus: nextStatus,
    deliveryStage: nextStatus,
    updatedAt: now,
    lastRiderAction: action,
    lastRiderActionAt: now,
  };

  if (nextStatus === "navigating_to_pickup") patch.headingToPickupAt = now;
  if (nextStatus === "arrived_at_pickup") patch.arrivedAtPickupAt = now;
  if (nextStatus === "pickup_verified") {
    patch.collectionPinVerified = true;
    patch.collectionPinVerifiedAt = now;
    patch.collectionPinVerifiedBy = riderId;
  }
  if (nextStatus === "collected") patch.collectedAt = now;
  if (nextStatus === "navigating_to_dropoff") {
    patch.collectedAt = now;
    patch.inTransitAt = now;
  }
  if (nextStatus === "arrived_at_dropoff") patch.arrivedAtDropoffAt = now;
  if (nextStatus === "delivered") {
    patch.deliveryPinVerified = true;
    patch.deliveryPinVerifiedAt = now;
    patch.deliveryPinVerifiedBy = riderId;
    patch.deliveredAt = now;
    patch.completedAt = now;
  }
  if (nextStatus === "issue_reported") {
    patch.issueReportedAt = now;
    patch.issueReportedBy = riderId;
  }
  if (nextStatus === "cancelled") {
    patch.cancelledAt = now;
    patch.cancelledBy = riderId;
  }
  return patch;
}

exports.updateDeliveryTrackingStatus = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Rider must be signed in.");
  }
  const deliveryId = text(data && (data.deliveryId || data.requestId));
  const action = normalized(data && data.action);
  const nextStatus = tracking.statusForRiderAction(action);
  if (!deliveryId) {
    throw new functions.https.HttpsError("invalid-argument", "deliveryId is required.");
  }
  if (!nextStatus) {
    throw new functions.https.HttpsError("invalid-argument", "Unsupported rider tracking action.");
  }

  const db = getFirestore();
  const riderId = context.auth.uid;
  const result = await db.runTransaction(async (transaction) => {
    const found = await findDelivery(db, transaction, deliveryId);
    if (!found) {
      throw new functions.https.HttpsError("not-found", "Delivery not found.");
    }
    const delivery = found.data || {};
    assertRiderOwnsDelivery(delivery, riderId);

    const riderRef = db.collection("riders").doc(riderId);
    const riderSnapshot = await transaction.get(riderRef);
    if (!(context.auth.token && context.auth.token.founderRider === true)) assertRiderOperational(riderSnapshot.data());

    const currentStatus = normalized(delivery.status || delivery.deliveryStatus || "requested");
    if (currentStatus === nextStatus ||
        (nextStatus === "delivered" && currentStatus === "completed")) {
      return {
        deliveryId: found.id,
        requestId: delivery.requestId || found.id,
        status: currentStatus,
        senderTrackingState: tracking.senderTrackingStateForBackendStatus(currentStatus),
        idempotent: true,
      };
    }
    if (!tracking.canTransitionDeliveryStatus(currentStatus, nextStatus)) {
      throw new functions.https.HttpsError("failed-precondition", `Cannot move delivery from ${currentStatus} to ${nextStatus}.`);
    }

    const evidence = data && data.evidence && typeof data.evidence === "object" ? data.evidence : {};
    const evidenceDecision = evidenceRequirements(delivery, action, evidence);
    if (!evidenceDecision.valid) {
      throw new functions.https.HttpsError("failed-precondition", evidenceDecision.reason);
    }


    const privateRef = db.collection("deliveryRequestsPrivate").doc(found.id);
    const privateSnapshot = await transaction.get(privateRef);
    const privateDelivery = privateSnapshot.exists ? privateSnapshot.data() || {} : {};
    const requiredPin = expectedPin(privateDelivery, action);
    if (!requiredPin && pinAuthorityRequired(delivery, action)) {
      throw new functions.https.HttpsError(
          "failed-precondition",
          "Secure PIN authority is not available for this delivery.",
      );
    }
    if (requiredPin) {
      const suppliedPin = text(data && data.pin);
      const attemptField = pinAttemptField(action);
      const attempts = Number(privateDelivery[attemptField] || 0);
      if (attempts >= 5) {
        throw new functions.https.HttpsError(
            "resource-exhausted",
            "Too many incorrect PIN attempts. Contact Circum Support.",
        );
      }
      if (!/^\d{6}$/.test(suppliedPin) || suppliedPin !== requiredPin) {
        transaction.set(privateRef, {
          [attemptField]: attempts + 1,
          lastPinAttemptAt: FieldValue.serverTimestamp(),
          vanguardReviewRequired: attempts + 1 >= 5,
          vanguardLastFailedStage: action === "verify_receiver_pin" ? "delivery" : "collection",
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
        return {verificationFailed: true, attemptsRemaining: 4 - attempts};
      }
    }

    const patch = patchForTransition({
      action,
      nextStatus,
      riderId,
    });
    if (Object.keys(evidence).length > 0) {
      patch[action === "verify_receiver_pin" ? "handoverEvidence" : "pickupEvidence"] = {
        ...evidence,
        recordedAt: FieldValue.serverTimestamp(),
        recordedBy: riderId,
      };
    }
    if (action === "report_issue") {
      const issue = data && data.issue && typeof data.issue === "object" ? data.issue : {};
      patch.deliveryIssue = {
        category: text(issue.category || "other"),
        notes: text(issue.notes),
        evidenceUrls: Array.isArray(issue.evidenceUrls) ? issue.evidenceUrls : [],
        reportedBy: riderId,
        reportedAt: FieldValue.serverTimestamp(),
      };
      patch.requiresAdminReview = true;
    }
    const liveLocation = liveLocationPatch(data && data.location);
    let activeRef = null;
    let shouldWriteLocation = false;
    if (Object.keys(liveLocation).length > 0) {
      activeRef = db.collection("activeDeliveries").doc(found.id);
      const activeSnapshot = await transaction.get(activeRef);
      shouldWriteLocation = shouldWriteLiveLocation(activeSnapshot.data(), liveLocation);
    }
    const earningRef = nextStatus === "delivered" ?
      db.collection("riderEarningTransactions").doc(found.id) : null;
    const existingEarning = earningRef ? await transaction.get(earningRef) : null;
    let actualRoadCharges = null;
    const liabilitySnapshots = new Map();
    if (nextStatus === "delivered" && existingEarning && !existingEarning.exists &&
        delivery.roadChargeRouteFacts && delivery.roadChargeRouteFacts.authority === "authoritative_route") {
      const assignedVehicle = delivery.assignedVehicleSnapshot || {
        type: delivery.assignedVehicleClass || delivery.driverVehicle,
      };
      const assignedVehicleId = text(
          delivery.assignedVehicleId || assignedVehicle.id || assignedVehicle.registration,
      );
      const preliminaryRoadCharges = evaluateRoadCharges({
        routeFacts: delivery.roadChargeRouteFacts,
        selectedVehicle: delivery.assignedVehicleClass || assignedVehicle.type,
        vehicleProfile: assignedVehicle,
        vehicleId: assignedVehicleId,
        requireVehicleIdentity: true,
      });
      if (!preliminaryRoadCharges.authoritativePricingComplete) {
        throw new functions.https.HttpsError(
            "failed-precondition",
            "Assigned vehicle road-charge classification requires review before settlement.",
        );
      }
      for (const key of preliminaryRoadCharges.liabilityKeys) {
        const liabilityRef = db.collection("roadChargeLiabilities").doc(key);
        liabilitySnapshots.set(key, {
          ref: liabilityRef,
          snapshot: await transaction.get(liabilityRef),
        });
      }
      const liabilityState = {liabilities: {}};
      for (const [key, value] of liabilitySnapshots.entries()) {
        if (value.snapshot.exists) liabilityState.liabilities[key] = value.snapshot.data();
      }
      actualRoadCharges = evaluateRoadCharges({
        routeFacts: delivery.roadChargeRouteFacts,
        selectedVehicle: delivery.assignedVehicleClass || assignedVehicle.type,
        vehicleProfile: assignedVehicle,
        vehicleId: assignedVehicleId,
        liabilityState,
        requireVehicleIdentity: true,
      });
    }
    const riderProfileRef = settlementValues(delivery).trustPoints > 0 ?
      db.collection("riderProfiles").doc(riderId) : null;
    const riderProfileSnapshot = riderProfileRef ? await transaction.get(riderProfileRef) : null;
    const existingAward = Number(delivery.trustPointsAwarded);
    const existingLedgerAward = existingEarning && existingEarning.exists ?
      Number(existingEarning.data()?.trustPoints) : NaN;
    const canonicalAward = Number.isFinite(existingAward) && existingAward >= 0 ?
      existingAward : Number.isFinite(existingLedgerAward) && existingLedgerAward >= 0 ?
        existingLedgerAward : settlementValues(delivery).trustPoints;
    if (nextStatus === "delivered") patch.trustPointsAwarded = canonicalAward;
    if (actualRoadCharges) {
      const quotedRoadPence = Number(
          delivery.roadChargeBreakdown && delivery.roadChargeBreakdown.customerContributionPence || 0,
      );
      const actualRecoveryPence = Number(actualRoadCharges.riderReimbursementPence || 0);
      patch.roadChargeReimbursement = actualRecoveryPence / 100;
      patch.actualRoadChargeBreakdown = actualRoadCharges;
      patch.roadChargeSettlement = {
        quotedCustomerRoadChargesPence: quotedRoadPence,
        actualRiderRecoveryPence: actualRecoveryPence,
        platformRoadRevenuePence: quotedRoadPence - actualRecoveryPence,
        assignedVehicleId: delivery.assignedVehicleId || null,
        assignedVehicleClass: delivery.assignedVehicleClass || null,
        policyVersion: actualRoadCharges.policyVersion,
      };
      for (const charge of actualRoadCharges.charges) {
        if (charge.type !== "daily_zone_charge" || !charge.liabilityKey) continue;
        const value = liabilitySnapshots.get(charge.liabilityKey);
        if (!value) continue;
        const riderRecoveryPence = Number(charge.riderReimbursementPence || 0);
        const quotedCharge = delivery.roadChargeBreakdown &&
          Array.isArray(delivery.roadChargeBreakdown.charges) &&
          delivery.roadChargeBreakdown.charges.find((item) => item.chargeId === charge.chargeId);
        const customerFeePence = Number(quotedCharge && quotedCharge.customerContributionPence || 0);
        transaction.set(value.ref, {
          chargeId: charge.chargeId,
          assignedVehicleId: delivery.assignedVehicleId,
          assignedVehicleClass: delivery.assignedVehicleClass,
          riderId,
          chargingDate: charge.chargingDate || null,
          incurred: true,
          actualDailyLiabilityPence: Number(charge.amountPence || charge.liabilityAmountPence || 0),
          customerCentralLondonFeesPence: FieldValue.increment(customerFeePence),
          riderRecoveryPence: Number(charge.recoveredAfterPence || 0),
          remainingRiderRecoveryPence: Number(charge.remainingRecoveryPence || 0),
          circumCCZRevenuePence: FieldValue.increment(Math.max(0, customerFeePence - riderRecoveryPence)),
          circumCCZContributionPence: FieldValue.increment(Math.max(0, riderRecoveryPence - customerFeePence)),
          deliveryIds: FieldValue.arrayUnion(found.id),
          updatedAt: FieldValue.serverTimestamp(),
          createdAt: value.snapshot.exists ? value.snapshot.data().createdAt : FieldValue.serverTimestamp(),
        }, {merge: true});
      }
    }
    transaction.set(found.ref, patch, {merge: true});
    if (nextStatus === "delivered") {
      const settlement = settlementValues(
          delivery,
          actualRoadCharges ? actualRoadCharges.riderReimbursement : null,
      );
      if (earningRef && existingEarning && !existingEarning.exists) {
        transaction.set(earningRef, {
          transactionId: found.id,
          deliveryId: found.id,
          riderId,
          type: "delivery_earning",
          amount: settlement.amount,
          deliveryAmount: settlement.deliveryAmount,
          roadChargeReimbursement: settlement.roadReimbursement,
          trustPoints: settlement.trustPoints,
          status: "completed",
          createdAt: FieldValue.serverTimestamp(),
        });
        transaction.set(db.collection("riderEarnings").doc(riderId), {
          availableBalance: FieldValue.increment(settlement.amount),
          deliveryEarningsTotal: FieldValue.increment(settlement.deliveryAmount),
          roadChargeReimbursementsTotal: FieldValue.increment(settlement.roadReimbursement),
          tipsTotal: FieldValue.increment(settlement.tip),
          waitingNoShowTotal: FieldValue.increment(settlement.waiting),
          adjustmentsTotal: FieldValue.increment(settlement.adjustment),
          lifetimeEarnings: FieldValue.increment(settlement.amount),
          totalAmountEarned: FieldValue.increment(settlement.amount),
          completedDeliveries: FieldValue.increment(1),
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
        if (settlement.trustPoints > 0) {
          transaction.set(riderProfileRef,
              riderTrustRankPatch(riderProfileSnapshot ? riderProfileSnapshot.data() : {}, settlement.trustPoints),
              {merge: true});
        }
        patch.settlementId = earningRef.id;
        patch.settlementCompletedAt = FieldValue.serverTimestamp();
        transaction.set(found.ref, patch, {merge: true});
        transaction.set(db.collection("chats").doc(delivery.requestId || found.id), {
          readOnly: true,
          completedAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
      }
    }
    if (activeRef && shouldWriteLocation) {
      transaction.set(
          activeRef,
          {
            deliveryId: found.id,
            requestId: delivery.requestId || found.id,
            riderId,
            status: nextStatus,
            ...liveLocation,
            updatedAt: FieldValue.serverTimestamp(),
          },
          {merge: true},
      );
    }
    return {
      deliveryId: found.id,
      requestId: delivery.requestId || found.id,
      status: nextStatus,
      senderTrackingState: tracking.senderTrackingStateForBackendStatus(nextStatus),
    };
  });
  if (result.verificationFailed) {
    throw new functions.https.HttpsError(
        "failed-precondition",
        `Incorrect PIN. ${Math.max(0, result.attemptsRemaining)} attempts remaining.`,
    );
  }
  return result;
});

exports.updateDeliveryLiveLocation = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Rider must be signed in.");
  }
  const deliveryId = text(data && (data.deliveryId || data.requestId));
  const trackingStatus = text(data && (data.status || data.trackingStatus || "live"));
  if (!deliveryId) {
    throw new functions.https.HttpsError("invalid-argument", "deliveryId is required.");
  }
  const location = validatedLiveLocation(data && data.location);
  if (location.mocked) {
    throw new functions.https.HttpsError("failed-precondition", "Live tracking requires a trusted GPS signal.");
  }

  const db = getFirestore();
  const riderId = context.auth.uid;
  return db.runTransaction(async (transaction) => {
    const found = await findDelivery(db, transaction, deliveryId);
    if (!found) {
      throw new functions.https.HttpsError("not-found", "Delivery not found.");
    }
    const delivery = found.data || {};
    assertRiderOwnsDelivery(delivery, riderId);
    const currentStatus = normalized(delivery.status || delivery.deliveryStatus || delivery.deliveryStage);
    if (["completed", "complete", "delivered", "cancelled", "canceled", "failed", "no_show"].includes(currentStatus)) {
      throw new functions.https.HttpsError("failed-precondition", "Live tracking is not active for this delivery.");
    }

    const now = Date.now();
    const trackingHealth = {
      gpsStatus: location.gpsStatus,
      gpsSignalQuality: location.gpsSignalQuality,
      accuracyMeters: location.accuracy,
      lastFixClientAt: location.clientRecordedAt,
      lastBackendUploadAt: FieldValue.serverTimestamp(),
      fresh: true,
      backgroundCapable: location.backgroundCapable,
      queueDepth: location.queueDepth,
      source: "updateDeliveryLiveLocation",
    };
    const riderLiveLocation = {
      geopoint: new GeoPoint(location.latitude, location.longitude),
      latitude: location.latitude,
      longitude: location.longitude,
      accuracy: location.accuracy,
      accuracyMeters: location.accuracy,
      heading: location.heading,
      speed: location.speed,
      gpsStatus: location.gpsStatus,
      gpsSignalQuality: location.gpsSignalQuality,
      clientRecordedAt: location.clientRecordedAt,
      updatedAt: FieldValue.serverTimestamp(),
    };
    const payload = {
      riderId,
      activeDeliveryId: found.id,
      deliveryId: found.id,
      latitude: location.latitude,
      longitude: location.longitude,
      accuracy: location.accuracy,
      heading: location.heading,
      speed: location.speed,
      status: trackingStatus,
      trackingStatus: "live",
      gpsStatus: location.gpsStatus,
      gpsSignalQuality: location.gpsSignalQuality,
      gpsAccuracyMeters: location.accuracy,
      lastGpsUpdateClientAt: location.clientRecordedAt,
      lastBackendUploadAt: FieldValue.serverTimestamp(),
      trackingHealth,
      clientRecordedAt: location.clientRecordedAt,
      updatedAt: FieldValue.serverTimestamp(),
      riderLiveLocation,
    };
    transaction.set(found.ref.collection("tracking").doc("liveLocation"), payload, {merge: true});
    transaction.set(db.collection("activeDeliveries").doc(found.id), {
      deliveryId: found.id,
      requestId: delivery.requestId || found.id,
      riderId,
      status: trackingStatus,
      riderLiveLocation,
      trackingHealth,
      lastBackendUploadAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    transaction.set(db.collection("riderPresence").doc(riderId), {
      riderId,
      isOnline: true,
      availabilityStatus: "busy",
      busy: true,
      activeDeliveryId: found.id,
      currentLocation: {
        latitude: location.latitude,
        longitude: location.longitude,
        accuracyMeters: location.accuracy,
        heading: location.heading,
        speed: location.speed,
        updatedAt: now,
      },
      lastLocationAt: now,
      gpsStatus: location.gpsStatus,
      gpsSignalQuality: location.gpsSignalQuality,
      dispatchEligible: false,
      connectionStatus: "connected",
      source: "deliveryLiveLocation",
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    return {success: true, deliveryId: found.id, trackingHealth};
  });
});

exports._private = {
  liveLocationPatch,
  shouldWriteLiveLocation,
  distanceMeters,
  signalQuality,
  validatedLiveLocation,
  patchForTransition,
  expectedPin,
  pinAuthorityRequired,
  assertRiderOwnsDelivery,
  assertRiderOperational,
  evidenceRequirements,
  settlementValues,
  highestTrustAward,
  canonicalRiderRankForTrust,
  hasManualRankOverride,
  riderTrustRankPatch,
};
