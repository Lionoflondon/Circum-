/* eslint-disable max-len, require-jsdoc */
"use strict";

const functions = require("firebase-functions/v1");
const {riderCallable} = require("./rider-app-check");
const {start: startLatency} = require("./latency-observability");
const {getFirestore, FieldValue, GeoPoint} = require("firebase-admin/firestore");
const tracking = require("./sender-tracking-state-core");
const evidenceAuthority = require("./delivery-evidence")._private;

function text(value) {
  return `${value || ""}`.trim();
}

function normalized(value) {
  return tracking.normalizeStatus(value);
}

function scheduledPickupMillis(delivery = {}) {
  const deliveryTime = delivery.deliveryTime && typeof delivery.deliveryTime === "object" ? delivery.deliveryTime : {};
  const value = delivery.scheduledAt || delivery.scheduledFor || delivery.scheduledDateTime ||
    delivery.scheduledDate || deliveryTime.scheduledAt || deliveryTime.scheduledDate;
  if (!value) return 0;
  if (typeof value === "number") return value;
  if (typeof value.toMillis === "function") return value.toMillis();
  if (value instanceof Date) return value.getTime();
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function scheduledOperationalTransitionAllowed(delivery = {}, nextStatus, now = Date.now()) {
  const deliveryTime = delivery.deliveryTime && typeof delivery.deliveryTime === "object" ? delivery.deliveryTime : {};
  const scheduled = deliveryTime.type === "scheduled" || delivery.isScheduled === true ||
    delivery.scheduledAt || delivery.scheduledFor || delivery.scheduledDateTime ||
    delivery.scheduledDate || deliveryTime.scheduledAt || deliveryTime.scheduledDate;
  if (!scheduled) return {allowed: true};
  const operationalStatuses = new Set([
    "navigating_to_pickup", "en_route_to_pickup", "arrived_at_pickup", "rider_arrived_pickup",
    "waiting", "pickup_verification", "pickup_verified", "collected", "picked_up", "in_transit",
    "navigating_to_dropoff", "arrived_at_dropoff", "pin_required", "delivered", "completed",
  ]);
  if (!operationalStatuses.has(nextStatus)) return {allowed: true};
  const pickupAt = scheduledPickupMillis(delivery);
  if (pickupAt && now < pickupAt) {
    return {allowed: false, reason: "scheduled_pickup_not_started", pickupAt};
  }
  return {allowed: true};
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
  if (!text(evidence.photoUrl) && !text(evidence.evidenceId)) return {valid: false, reason: "A delivery evidence photo is required."};
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

function settlementValues(delivery = {}) {
  const explicit = [
    delivery.riderEarning,
    delivery.estimatedEarnings,
    delivery.riderShare,
    delivery.riderPayout,
  ].map(Number).find((value) => Number.isFinite(value) && value > 0);
  const eligibleFare = Number(delivery.riderEligibleFare);
  const hasProvenance = Number.isFinite(eligibleFare) && eligibleFare > 0 &&
      delivery.riderPayoutCalculationVersion === "65_35_v1";
  const base = explicit || (hasProvenance ? Math.round(eligibleFare * 0.65 * 100) / 100 : 0);
  const breakdown = delivery.riderEarningBreakdown || {};
  const tip = Number(breakdown.tip || delivery.riderTip || delivery.tipAmount || 0);
  const waiting = Number(breakdown.waiting || delivery.riderWaitingEarning || delivery.noShowEarning || 0);
  const adjustment = Number(breakdown.adjustment || delivery.riderAdjustment || 0);
  const amount = Number.isFinite(base) ? base : 0;
  return {
    amount: Number.isFinite(amount) && amount > 0 ? Math.round(amount * 100) / 100 : 0,
    amountSource: explicit ? "explicit_rider_earning" : hasProvenance ? "computed_authoritative_65_35" : "no_authoritative_payout",
    requiresReview: !explicit && !hasProvenance,
    deliveryAmount: Math.max(0, Math.round((amount - tip - waiting - adjustment) * 100) / 100),
    tip: Number.isFinite(tip) ? Math.round(tip * 100) / 100 : 0,
    waiting: Number.isFinite(waiting) ? Math.round(waiting * 100) / 100 : 0,
    adjustment: Number.isFinite(adjustment) ? Math.round(adjustment * 100) / 100 : 0,
    trustPoints: highestTrustAward(delivery),
  };
}

function highestTrustAward(delivery = {}) {
  const text = `${delivery.category || delivery.deliveryType || delivery.serviceType || ""}`.toLowerCase();
  const enabled = (key) => delivery[key] === true;
  if (enabled("isHealthPlus") || enabled("healthPlus") || text.includes("health")) return 6;
  if (enabled("isGift") || enabled("gift") || text.includes("gift")) return 5;
  if (enabled("isScheduled") || enabled("scheduled") || delivery.scheduledAt || text.includes("scheduled")) return 5;
  if (enabled("requiresVanguard") || enabled("vanguard") || text.includes("vanguard")) return 4;
  if (enabled("isHeavyDuty") || enabled("heavyDuty") || text.includes("heavy")) return 4;
  if (enabled("isBusiness") || enabled("business") || text.includes("business")) return 3;
  if (enabled("isMarketplace") || enabled("marketplace") || text.includes("marketplace")) return 2;
  return 1;
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

exports.updateDeliveryTrackingStatus = riderCallable(async (data, context) => {
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
    if (delivery.cancellationSettlementStatus === "pending_reconciliation") {
      throw new functions.https.HttpsError("failed-precondition", "Cancellation is being reconciled. Delivery actions are paused.");
    }

    const riderRef = db.collection("riders").doc(riderId);
    const riderSnapshot = await transaction.get(riderRef);
    assertRiderOperational(riderSnapshot.data());

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
    const scheduleDecision = scheduledOperationalTransitionAllowed(delivery, nextStatus);
    if (!scheduleDecision.allowed) {
      throw new functions.https.HttpsError(
          "failed-precondition",
          "This scheduled delivery is not ready for pickup yet.",
          {reason: scheduleDecision.reason, pickupAt: scheduleDecision.pickupAt},
      );
    }

    const evidence = data && data.evidence && typeof data.evidence === "object" ? data.evidence : {};
    const evidenceDecision = evidenceRequirements(delivery, action, evidence);
    if (!evidenceDecision.valid) {
      throw new functions.https.HttpsError("failed-precondition", evidenceDecision.reason);
    }


    const verificationStage = action === "verify_collection_pin" ? "pickup" : action === "verify_receiver_pin" ? "handover" : null;
    if ((evidence.photoUrl || evidence.evidenceId) && !verificationStage) throw new functions.https.HttpsError("invalid-argument", "Evidence must accompany its verification action.");
    const resolvedEvidence = verificationStage ? await evidenceAuthority.resolve({db, transaction, deliveryId: found.id, riderId, requiredStage: verificationStage, evidence}) : null;
    if (nextStatus === "delivered") {
      if (!["paid", "succeeded", "success", "roth_paid", "stripe_paid"].includes(normalized(delivery.paymentStatus || delivery.paymentState))) throw new functions.https.HttpsError("failed-precondition", "Delivery payment authority is not complete.");
      await evidenceAuthority.completionProof({db, transaction, deliveryId: found.id, riderId, resolved: resolvedEvidence});
    }
    const privateRef = db.collection("deliveryRequestsPrivate").doc(found.id);
    const privateSnapshot = await transaction.get(privateRef);
    const privateDelivery = privateSnapshot.exists ? privateSnapshot.data() || {} : {};
    const pickupVerificationRequired = Boolean(expectedPin(privateDelivery, "verify_collection_pin")) ||
      pinAuthorityRequired(delivery, "verify_collection_pin") ||
      delivery.verificationRequired === true || delivery.requiresVerification === true;
    if (["confirm_collected", "start_delivery", "verify_receiver_pin"].includes(action) &&
        pickupVerificationRequired && delivery.collectionPinVerified !== true) {
      throw new functions.https.HttpsError("failed-precondition", "Verify the collection PIN and pickup evidence before continuing.");
    }
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
        deliveryId: found.id,
        riderId,
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
    const riderProfileRef = settlementValues(delivery).trustPoints > 0 ?
      db.collection("riderProfiles").doc(riderId) : null;
    const riderProfileSnapshot = riderProfileRef ? await transaction.get(riderProfileRef) : null;
    const settlement = nextStatus === "delivered" ? settlementValues(delivery) : null;
    if (settlement && settlement.requiresReview) {
      Object.assign(patch, {
        status: "settlement_pending",
        deliveryStatus: "settlement_pending",
        deliveryStage: "settlement_pending",
        settlementStatus: "pending_authority",
        settlementIssue: "missing_authoritative_payout",
        settlementAmountSource: settlement.amountSource,
        completionIntent: {
          riderId,
          requestedAction: action,
          recordedAt: FieldValue.serverTimestamp(),
        },
        settlementNextRetryAt: FieldValue.serverTimestamp(),
      });
      delete patch.deliveredAt;
      delete patch.completedAt;
    }
    evidenceAuthority.writeVerified({db, transaction, resolved: resolvedEvidence, deliveryId: found.id, riderId});
    if (resolvedEvidence) {
patch[action === "verify_receiver_pin" ? "handoverEvidence" : "pickupEvidence"] = {
      ...patch[action === "verify_receiver_pin" ? "handoverEvidence" : "pickupEvidence"],
      evidenceId: resolvedEvidence.id, canonicalMediaReference: resolvedEvidence.record.storagePath,
    };
}
    transaction.set(found.ref, patch, {merge: true});
    if (nextStatus === "delivered") {
      if (settlement.requiresReview) {
        // The completion proof is retained, but terminal delivery is deferred
        // until automated reconciliation can settle authoritative finances.
      } else if (earningRef && existingEarning && !existingEarning.exists) {
        transaction.set(earningRef, {
          transactionId: found.id,
          deliveryId: found.id,
          riderId,
          type: "delivery_earning",
          amount: settlement.amount,
          amountSource: settlement.amountSource,
          trustPoints: settlement.trustPoints,
          status: "completed",
          createdAt: FieldValue.serverTimestamp(),
        });
        transaction.set(db.collection("riderEarnings").doc(riderId), {
          availableBalance: FieldValue.increment(settlement.amount),
          deliveryEarningsTotal: FieldValue.increment(settlement.deliveryAmount),
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
        patch.settlementStatus = "completed";
        patch.settlementAmountSource = settlement.amountSource;
        patch.settlementCompletedAt = FieldValue.serverTimestamp();
        patch.trustPointsAwarded = settlement.trustPoints;
        transaction.set(found.ref, patch, {merge: true});
        transaction.set(db.collection("chats").doc(delivery.requestId || found.id), {
          readOnly: true,
          completedAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
        transaction.set(db.collection("riderPresence").doc(riderId), {
          activeDeliveryId: FieldValue.delete(),
          currentDeliveryId: FieldValue.delete(),
          busy: false,
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
        transaction.set(db.collection("riders").doc(riderId), {
          activeDeliveryId: FieldValue.delete(),
          currentDeliveryId: FieldValue.delete(),
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
        transaction.set(db.collection("riderProfiles").doc(riderId), {
          activeDeliveryId: FieldValue.delete(),
          currentDeliveryId: FieldValue.delete(),
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
        transaction.set(db.collection("activeDeliveries").doc(found.id), {
          status: "completed",
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
      status: settlement && settlement.requiresReview ? "settlement_pending" : nextStatus,
      senderTrackingState: tracking.senderTrackingStateForBackendStatus(
          settlement && settlement.requiresReview ? "settlement_pending" : nextStatus,
      ),
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

exports.updateDeliveryLiveLocation = riderCallable(async (data, context) => {
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
  const completeTracking = startLatency("TRACKING_WRITE", {correlationId: deliveryId});
  const result = await db.runTransaction(async (transaction) => {
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
  completeTracking({success: true, deliveryId: result.deliveryId});
  return result;
});

async function reconcileSettlementPendingDelivery(db, deliveryId) {
  return db.runTransaction(async (transaction) => {
    const deliveryRef = db.collection("deliveryRequests").doc(deliveryId);
    const deliverySnapshot = await transaction.get(deliveryRef);
    if (!deliverySnapshot.exists) return {deliveryId, status: "missing"};
    const delivery = deliverySnapshot.data() || {};
    if (normalized(delivery.status) !== "settlement_pending") {
      return {deliveryId, status: normalized(delivery.status), idempotent: true};
    }
    const riderId = text(
        delivery.riderId || delivery.assignedRiderId || delivery.driverId,
    );
    if (!riderId) return {deliveryId, status: "pending_authority"};
    const privateSnapshot = await transaction.get(db.collection("deliveryRequestsPrivate").doc(deliveryId));
    const privateDelivery = privateSnapshot.data() || {};
    try {
      if (!["paid", "succeeded", "success", "roth_paid", "stripe_paid"].includes(normalized(delivery.paymentStatus || delivery.paymentState)) || delivery.cancellationSettlementStatus) {
        throw new functions.https.HttpsError("failed-precondition", "Payment or cancellation authority is unresolved.");
      }
      if ((expectedPin(privateDelivery, "verify_collection_pin") || pinAuthorityRequired(delivery, "verify_collection_pin")) && delivery.collectionPinVerified !== true) {
        throw new functions.https.HttpsError("failed-precondition", "Pickup verification is incomplete.");
      }
      if ((expectedPin(privateDelivery, "verify_receiver_pin") || pinAuthorityRequired(delivery, "verify_receiver_pin")) && delivery.deliveryPinVerified !== true) {
        throw new functions.https.HttpsError("failed-precondition", "Handover verification is incomplete.");
      }
      const evidence = delivery.handoverEvidence || {};
      const resolved = await evidenceAuthority.resolve({db, transaction, deliveryId, riderId, requiredStage: "handover", evidence});
      await evidenceAuthority.completionProof({db, transaction, deliveryId, riderId, resolved});
    } catch (error) {
      transaction.set(deliveryRef, {settlementIssue: "completion_authority_unresolved", settlementAttemptCount: FieldValue.increment(1), settlementLastAttemptAt: FieldValue.serverTimestamp()}, {merge: true});
      return {deliveryId, status: "pending_authority", reason: "completion_authority_unresolved"};
    }
    const settlement = settlementValues(delivery);
    if (settlement.requiresReview) {
      transaction.set(deliveryRef, {
        settlementStatus: "pending_authority",
        settlementAttemptCount: FieldValue.increment(1),
        settlementLastAttemptAt: FieldValue.serverTimestamp(),
      }, {merge: true});
      return {deliveryId, status: "pending_authority"};
    }
    const earningRef = db.collection("riderEarningTransactions").doc(deliveryId);
    const profileRef = db.collection("riderProfiles").doc(riderId);
    const [earningSnapshot, profileSnapshot] = await Promise.all([
      transaction.get(earningRef),
      transaction.get(profileRef),
    ]);
    if (!earningSnapshot.exists) {
      transaction.set(earningRef, {
        transactionId: deliveryId,
        deliveryId,
        riderId,
        type: "delivery_earning",
        amount: settlement.amount,
        amountSource: settlement.amountSource,
        trustPoints: settlement.trustPoints,
        status: "completed",
        createdAt: FieldValue.serverTimestamp(),
      });
      transaction.set(db.collection("riderEarnings").doc(riderId), {
        availableBalance: FieldValue.increment(settlement.amount),
        deliveryEarningsTotal: FieldValue.increment(settlement.deliveryAmount),
        tipsTotal: FieldValue.increment(settlement.tip),
        waitingNoShowTotal: FieldValue.increment(settlement.waiting),
        adjustmentsTotal: FieldValue.increment(settlement.adjustment),
        lifetimeEarnings: FieldValue.increment(settlement.amount),
        totalAmountEarned: FieldValue.increment(settlement.amount),
        completedDeliveries: FieldValue.increment(1),
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
      if (settlement.trustPoints > 0) {
        transaction.set(
            profileRef,
            riderTrustRankPatch(profileSnapshot.exists ? profileSnapshot.data() : {}, settlement.trustPoints),
            {merge: true},
        );
      }
    }
    const completedAt = FieldValue.serverTimestamp();
    transaction.set(deliveryRef, {
      status: "delivered",
      deliveryStatus: "delivered",
      deliveryStage: "delivered",
      deliveryPinVerified: true,
      deliveryPinVerifiedAt: completedAt,
      deliveryPinVerifiedBy: riderId,
      deliveredAt: completedAt,
      completedAt,
      settlementId: earningRef.id,
      settlementStatus: "completed",
      settlementIssue: FieldValue.delete(),
      settlementAmountSource: settlement.amountSource,
      settlementCompletedAt: completedAt,
      settlementNextRetryAt: FieldValue.delete(),
      trustPointsAwarded: settlement.trustPoints,
      pendingNotification: {
        recipient: "sender",
        message: "Your delivery is complete.",
        triggeredByState: "delivered",
        createdAt: Date.now(),
      },
      updatedAt: completedAt,
    }, {merge: true});
    transaction.set(db.collection("chats").doc(delivery.requestId || deliveryId), {
      readOnly: true,
      completedAt,
      updatedAt: completedAt,
    }, {merge: true});
    for (const collection of ["riderPresence", "riders", "riderProfiles"]) {
      transaction.set(db.collection(collection).doc(riderId), {
        activeDeliveryId: FieldValue.delete(),
        currentDeliveryId: FieldValue.delete(),
        ...(collection === "riderPresence" ? {busy: false} : {}),
        updatedAt: completedAt,
      }, {merge: true});
    }
    transaction.set(db.collection("activeDeliveries").doc(deliveryId), {
      status: "completed",
      completedAt,
      updatedAt: completedAt,
    }, {merge: true});
    return {deliveryId, status: "delivered", reconciled: true};
  });
}

exports.reconcilePendingDeliverySettlements = functions.pubsub
    .schedule("every 5 minutes")
    .onRun(async () => {
      const db = getFirestore();
      const snapshot = await db.collection("deliveryRequests")
          .where("settlementStatus", "==", "pending_authority")
          .limit(100)
          .get();
      const results = [];
      for (const document of snapshot.docs) {
        results.push(await reconcileSettlementPendingDelivery(db, document.id));
      }
      return {scanned: snapshot.size, results};
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
  reconcileSettlementPendingDelivery,
  scheduledPickupMillis,
  scheduledOperationalTransitionAllowed,
};
