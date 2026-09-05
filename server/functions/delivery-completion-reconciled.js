/* eslint-disable max-len, require-jsdoc */
"use strict";

const functions = require("firebase-functions/v1");
const {
  getFirestore,
  FieldValue,
  GeoPoint,
} = require("firebase-admin/firestore");
const tracking = require("./delivery-completion-policy");
const {highestTrustAward} = require("./trust-award");
const {planRoadChargeSettlement, pence} = require("./road-charge-settlement");
const {
  standardSettlementAllowed,
  settlementProduct,
} = require("./settlement-product-guard");
const {evaluateActualTraversal} = require("./actual-road-traversal");
const {roadChargesFor} = require("./road-charge-settlement");
const {
  createEntitlement,
  settleEntitlementToRoth,
} = require("./scheduled-road-charge-refunds");
const {
  buildDeliveryCompletedEvent,
  publishDeliveryCompleted,
} = require("./delivery-completed-event");
const evidenceAuthority = require("./delivery-evidence")._private;

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
  if (![lat1, lon1, lat2, lon2].every(Number.isFinite)) {
    return Number.POSITIVE_INFINITY;
  }
  const radians = (deg) => (deg * Math.PI) / 180;
  const dLat = radians(lat2 - lat1);
  const dLon = radians(lon2 - lon1);
  const rLat1 = radians(lat1);
  const rLat2 = radians(lat2);
  const h =
    Math.sin(dLat / 2) ** 2 +
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
  const turned = headingDelta(
    previousLocation.heading,
    next.riderLiveLocation.heading,
  );
  if (moved >= 25 || turned >= 15) return true;
  return ageMs >= 30000;
}

async function findDelivery(db, transaction, deliveryId) {
  const directRef = db.collection("deliveryRequests").doc(deliveryId);
  const direct = await transaction.get(directRef);
  if (direct.exists) {
    return {ref: directRef, id: direct.id, data: direct.data()};
  }

  const query = await transaction.get(
    db
      .collection("deliveryRequests")
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
    throw new functions.https.HttpsError(
      "permission-denied",
      "Only the assigned rider can update this delivery.",
    );
  }
}

function assertRiderOperational(rider = {}) {
  const state = normalized(
    rider.accountState ||
      rider.accountStatus ||
      rider.status ||
      rider.approvalStatus,
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
    return text(
      privateDelivery.collectionPin ||
        privateDelivery.pickupPin ||
        protection.collectionPin,
    );
  }
  if (action === "verify_receiver_pin" || action === "complete_delivery") {
    return text(
      privateDelivery.deliveryPin ||
        privateDelivery.receiverPin ||
        privateDelivery.dropoffPin ||
        protection.deliveryPin,
    );
  }
  return "";
}

function isHandoverAction(action) {
  return action === "verify_receiver_pin" || action === "complete_delivery";
}

function pinAuthorityRequired(delivery, action) {
  if (action !== "verify_collection_pin" && action !== "verify_receiver_pin") {
    return false;
  }
  const protection = delivery.vanguardProtection || {};
  return (
    delivery.vanguardProtocolEnabled === true ||
    delivery.vanguardEnabled === true ||
    delivery.requiresVanguard === true ||
    protection.enabled === true
  );
}

function pinAttemptField(action) {
  return isHandoverAction(action) ?
    "deliveryPinAttemptCount" :
    "collectionPinAttemptCount";
}

function evidenceRequirements(delivery, action, evidence = {}) {
  const pickup = action === "verify_collection_pin";
  const handover = isHandoverAction(action);
  if (!pickup && !handover) return {valid: true};
  const required = pickup ?
    delivery.verificationRequired === true ||
      delivery.requiresVerification === true ||
      delivery.requiresVanguard === true :
    delivery.deliveryPhotoRequired === true ||
      delivery.requiresVanguard === true ||
      delivery.secureHandoverRequired === true;
  if (!required) return {valid: true};
  if (!text(evidence.photoUrl) && !text(evidence.evidenceId)) {
    return {valid: false, reason: "A delivery evidence photo is required."};
  }
  if (pickup && evidence.conditionConfirmed !== true) {
    return {valid: false, reason: "Parcel condition must be confirmed."};
  }
  if (pickup && evidence.riderDeclarationAccepted !== true) {
    return {valid: false, reason: "Rider declaration is required."};
  }
  if (
    pickup &&
    delivery.weightVerificationRequired === true &&
    !(Number(evidence.actualWeightKg) > 0)
  ) {
    return {valid: false, reason: "Actual parcel weight is required."};
  }
  if (
    handover &&
    !text(evidence.recipientName) &&
    evidence.recipientConfirmed !== true
  ) {
    return {valid: false, reason: "Recipient confirmation is required."};
  }
  return {valid: true};
}

function settlementValues(delivery = {}) {
  const canonical = require("./delivery-tracking")._private.settlementValues(
    delivery,
  );
  const base = canonical.amount;
  const breakdown = delivery.riderEarningBreakdown || {};
  const tip = Number(
    breakdown.tip || delivery.riderTip || delivery.tipAmount || 0,
  );
  const waiting = Number(
    breakdown.waiting ||
      delivery.riderWaitingEarning ||
      delivery.noShowEarning ||
      0,
  );
  const adjustment = Number(
    breakdown.adjustment || delivery.riderAdjustment || 0,
  );
  const amount = Number.isFinite(base) ? base : 0;
  return {
    amount:
      Number.isFinite(amount) && amount > 0 ?
        Math.round(amount * 100) / 100 :
        0,
    deliveryAmount: Math.max(
      0,
      Math.round((amount - tip - waiting - adjustment) * 100) / 100,
    ),
    tip: Number.isFinite(tip) ? Math.round(tip * 100) / 100 : 0,
    waiting: Number.isFinite(waiting) ? Math.round(waiting * 100) / 100 : 0,
    adjustment: Number.isFinite(adjustment) ?
      Math.round(adjustment * 100) / 100 :
      0,
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
  return (
    profile.rankOverride === true ||
    `${profile.rankSource || ""}`.toLowerCase() === "manual" ||
    text(profile.rankUpdatedBy) ||
    text(profile.rankReason)
  );
}

function riderTrustRankPatch(profile = {}, awardedTrustPoints = 0) {
  const currentTrust = Number(
    profile.trustPoints || profile.riderTrustPoints || 0,
  );
  const awarded = Number(awardedTrustPoints);
  const trustPoints = Math.max(
    0,
    (Number.isFinite(currentTrust) ? currentTrust : 0) +
      (Number.isFinite(awarded) ? awarded : 0),
  );
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

function patchForTransition({
  action,
  nextStatus,
  riderId,
  pinVerified = false,
}) {
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
    if (pinVerified) {
      patch.deliveryPinVerified = true;
      patch.deliveryPinVerifiedAt = now;
      patch.deliveryPinVerifiedBy = riderId;
    }
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

function transitionPolicyDecision(delivery, currentStatus, nextStatus) {
  if (
    tracking.canTransitionDeliveryStatusForPolicy(
      delivery,
      currentStatus,
      nextStatus,
    )
  ) {
    return {allowed: true, message: ""};
  }
  if (
    currentStatus === "arrived_at_pickup" &&
    nextStatus === "collected" &&
    tracking.pickupVerificationRequired(delivery)
  ) {
    return {
      allowed: false,
      message:
        "Complete the required pickup verification before collecting this delivery.",
    };
  }
  return {
    allowed: false,
    message: `Cannot move delivery from ${currentStatus} to ${nextStatus}.`,
  };
}

async function updateDeliveryTrackingStatusHandler(
  data,
  context,
  db = getFirestore(),
) {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "Rider must be signed in.",
    );
  }
  const deliveryId = text(data && (data.deliveryId || data.requestId));
  const action = normalized(data && data.action);
  const nextStatus = tracking.statusForRiderAction(action);
  if (!deliveryId) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "deliveryId is required.",
    );
  }
  if (!nextStatus) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Unsupported rider tracking action.",
    );
  }

  const riderId = context.auth.uid;
  const refundEntitlementIds = [];
  const result = await db.runTransaction(async (transaction) => {
    const found = await findDelivery(db, transaction, deliveryId);
    if (!found) {
      throw new functions.https.HttpsError("not-found", "Delivery not found.");
    }
    const delivery = found.data || {};
    assertRiderOwnsDelivery(delivery, riderId);

    const riderRef = db.collection("riders").doc(riderId);
    const riderSnapshot = await transaction.get(riderRef);
    if (!(context.auth.token && context.auth.token.founderRider === true)) {
      assertRiderOperational(riderSnapshot.data());
    }

    const currentStatus = normalized(
      delivery.status || delivery.deliveryStatus || "requested",
    );
    if (
      currentStatus === nextStatus ||
      (nextStatus === "delivered" && currentStatus === "completed")
    ) {
      return {
        deliveryId: found.id,
        requestId: delivery.requestId || found.id,
        status: currentStatus,
        senderTrackingState:
          tracking.senderTrackingStateForBackendStatus(currentStatus),
        idempotent: true,
      };
    }
    if (delivery.cancellationSettlementStatus) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "Cancellation is being reconciled.",
      );
    }
    const transitionDecision = transitionPolicyDecision(
      delivery,
      currentStatus,
      nextStatus,
    );
    if (!transitionDecision.allowed) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        transitionDecision.message,
      );
    }
    if (nextStatus === "delivered" && !standardSettlementAllowed(delivery)) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        `Settlement for ${settlementProduct(delivery)} deliveries must use its domain completion authority.`,
      );
    }

    if (
      nextStatus === "delivered" &&
      require("./delivery-tracking")._private.settlementValues(delivery)
        .requiresReview
    ) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "Authoritative Rider payout requires reconciliation before completion.",
      );
    }
    const evidence =
      data && data.evidence && typeof data.evidence === "object" ?
        data.evidence :
        {};
    const evidenceDecision = evidenceRequirements(delivery, action, evidence);
    if (!evidenceDecision.valid) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        evidenceDecision.reason,
      );
    }

    const verificationStage =
      action === "verify_collection_pin" ?
        "pickup" :
        action === "verify_receiver_pin" ?
          "handover" :
          null;
    if ((evidence.photoUrl || evidence.evidenceId) && !verificationStage) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Evidence must accompany its verification action.",
      );
    }
    const resolvedEvidence = verificationStage ?
      await evidenceAuthority.resolve({
          db,
          transaction,
          deliveryId: found.id,
          riderId,
          requiredStage: verificationStage,
          evidence,
        }) :
      null;
    if (
      nextStatus === "delivered" &&
      !["paid", "succeeded", "success", "roth_paid", "stripe_paid"].includes(
        normalized(delivery.paymentStatus || delivery.paymentState),
      )
    ) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "Delivery payment authority is not complete.",
      );
    }
    const privateRef = db.collection("deliveryRequestsPrivate").doc(found.id);
    const privateSnapshot = await transaction.get(privateRef);
    const privateDelivery = privateSnapshot.exists ?
      privateSnapshot.data() || {} :
      {};
    const evidenceRecordRef = db.collection("deliveryEvidence").doc(found.id);
    const evidenceRecordSnapshot = await transaction.get(evidenceRecordRef);
    if (nextStatus === "delivered") {
      await evidenceAuthority.completionProof({
        db,
        transaction,
        deliveryId: found.id,
        riderId,
        resolved: resolvedEvidence,
      });
    }
    const pickupRequired =
      Boolean(expectedPin(privateDelivery, "verify_collection_pin")) ||
      pinAuthorityRequired(delivery, "verify_collection_pin") ||
      delivery.verificationRequired === true ||
      delivery.requiresVerification === true;
    if (
      ["confirm_collected", "start_delivery", "verify_receiver_pin"].includes(
        action,
      ) &&
      pickupRequired &&
      delivery.collectionPinVerified !== true
    ) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "Verify the collection PIN and pickup evidence before continuing.",
      );
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
        transaction.set(
          privateRef,
          {
            [attemptField]: attempts + 1,
            lastPinAttemptAt: FieldValue.serverTimestamp(),
            vanguardReviewRequired: attempts + 1 >= 5,
            vanguardLastFailedStage: isHandoverAction(action) ?
              "delivery" :
              "collection",
            updatedAt: FieldValue.serverTimestamp(),
          },
          {merge: true},
        );
        return {verificationFailed: true, attemptsRemaining: 4 - attempts};
      }
    }

    const patch = patchForTransition({
      action,
      nextStatus,
      riderId,
      pinVerified: Boolean(requiredPin),
    });
    if (Object.keys(evidence).length > 0) {
      patch[isHandoverAction(action) ? "handoverEvidence" : "pickupEvidence"] =
        {
          ...evidence,
          recordedAt: FieldValue.serverTimestamp(),
          recordedBy: riderId,
        };
      if (nextStatus === "delivered" && evidence.evidenceId) {
        patch.evidenceId = text(evidence.evidenceId);
      }
    }
    if (action === "report_issue") {
      const issue =
        data && data.issue && typeof data.issue === "object" ? data.issue : {};
      patch.deliveryIssue = {
        category: text(issue.category || "other"),
        notes: text(issue.notes),
        evidenceUrls: Array.isArray(issue.evidenceUrls) ?
          issue.evidenceUrls :
          [],
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
      shouldWriteLocation = shouldWriteLiveLocation(
        activeSnapshot.data(),
        liveLocation,
      );
    }
    const earningRef =
      nextStatus === "delivered" ?
        db.collection("riderEarningTransactions").doc(found.id) :
        null;
    const existingEarning = earningRef ?
      await transaction.get(earningRef) :
      null;
    const assignedVehicle = {
      id: delivery.assignedVehicleId,
      type: delivery.assignedVehicleClass,
      ...(delivery.assignedVehicleSnapshot || {}),
    };
    const roadSettlement =
      nextStatus === "delivered" ?
        planRoadChargeSettlement({
            deliveryId: found.id,
            riderId,
            delivery,
            assignedVehicle,
          }) :
        {
            effects: [],
            dailyUpdates: [],
            reimbursementPence: 0,
            reimbursement: 0,
          };
    const roadEffectRefs = roadSettlement.effects.map((effect) =>
      db.collection("riderRoadChargeTransactions").doc(effect.id),
    );
    const dailyRefs = roadSettlement.dailyUpdates.map((update) =>
      db.collection("roadChargeDailyLiabilities").doc(update.id),
    );
    const roadEffectSnapshots = await Promise.all(
      roadEffectRefs.map((ref) => transaction.get(ref)),
    );
    const dailySnapshots = await Promise.all(
      dailyRefs.map((ref) => transaction.get(ref)),
    );
    const freshDailyState = {};
    roadSettlement.dailyUpdates.forEach((update, index) => {
      freshDailyState[update.id] = dailySnapshots[index].exists ?
        dailySnapshots[index].data() :
        {};
    });
    const finalRoadSettlement =
      nextStatus === "delivered" ?
        planRoadChargeSettlement({
            deliveryId: found.id,
            riderId,
            delivery,
            assignedVehicle,
            dailyState: freshDailyState,
          }) :
        roadSettlement;
    const riderProfileRef =
      settlementValues(delivery).trustPoints > 0 ?
        db.collection("riderProfiles").doc(riderId) :
        null;
    const riderProfileSnapshot = riderProfileRef ?
      await transaction.get(riderProfileRef) :
      null;
    const existingAward = Number(delivery.trustPointsAwarded);
    const existingLedgerAward =
      existingEarning && existingEarning.exists ?
        Number(existingEarning.data()?.trustPoints) :
        NaN;
    const canonicalAward =
      Number.isFinite(existingAward) && existingAward >= 0 ?
        existingAward :
        Number.isFinite(existingLedgerAward) && existingLedgerAward >= 0 ?
          existingLedgerAward :
          settlementValues(delivery).trustPoints;
    if (nextStatus === "delivered") {
      patch.trustPointsAwarded = canonicalAward;
      patch.evidenceSummary = {
        recordPath: `deliveryEvidence/${found.id}`,
        verifiedPhotoCount: Number(
          evidenceRecordSnapshot.data()?.verifiedPhotoCount || 0,
        ),
        latestPhotoPath: evidenceRecordSnapshot.data()?.latestPhotoPath || null,
        latestThumbnailPath:
          evidenceRecordSnapshot.data()?.latestThumbnailPath || null,
        latestCapturedAt:
          evidenceRecordSnapshot.data()?.latestCapturedAt || null,
        latestDevice: evidenceRecordSnapshot.data()?.latestDevice || null,
        latestGps: evidenceRecordSnapshot.data()?.latestGps || null,
        latestAccuracy: evidenceRecordSnapshot.data()?.latestAccuracy || null,
        types: ["PHOTO"],
        verifiedAt: FieldValue.serverTimestamp(),
      };
    }
    if (
      nextStatus === "delivered" &&
      delivery.deliveryTime &&
      delivery.deliveryTime.type === "scheduled" &&
      ["standard", "business"].includes(settlementProduct(delivery))
    ) {
      const traversalRef = db
        .collection("deliveryTraversalEvidence")
        .doc(found.id);
      const traversalSnapshot = await transaction.get(traversalRef);
      const traversal = traversalSnapshot.exists ?
        traversalSnapshot.data() || {} :
        {};
      const actualTraversal = evaluateActualTraversal({
        deliveryId: found.id,
        riderId,
        assignedVehicle,
        points: traversal.points,
      });
      transaction.set(
        traversalRef,
        {
          ...actualTraversal,
          completeness: actualTraversal.evidenceCompleteness,
          reconciledAt: FieldValue.serverTimestamp(),
        },
        {merge: true},
      );
      patch.actualRoadTraversalFacts = actualTraversal;
      if (actualTraversal.evidenceCompleteness === "COMPLETE") {
        for (const charge of roadChargesFor(delivery)) {
          const entitlement = createEntitlement({
            deliveryId: found.id,
            quoteId: delivery.quoteId,
            charge,
            actualEvidence: {
              authoritative: true,
              incurred: actualTraversal.status === "INCURRED",
            },
          });
          entitlement.refundOwnerType =
            delivery.businessMode === true ||
            delivery.businessId ||
            delivery.businessAccountId ?
              "business" :
              "sender";
          entitlement.refundOwnerId =
            entitlement.refundOwnerType === "business" ?
              delivery.businessId || delivery.businessAccountId :
              delivery.senderId || delivery.userId;
          entitlement.refundOwnerEmail =
            delivery.senderEmail || delivery.userEmail || null;
          const actualCharge = actualTraversal.charges.find(
            (item) => item.chargeId === charge.chargeId,
          );
          const prepaidPence = Number(
            charge.customerContributionPence || charge.amountPence || 0,
          );
          const actualPence = Number(
            (actualCharge &&
              (actualCharge.customerContributionPence ||
                actualCharge.amountPence)) ||
              0,
          );
          entitlement.refundablePence = Math.max(0, prepaidPence - actualPence);
          if (entitlement.refundablePence === 0) entitlement.state = "CLOSED";
          transaction.set(
            db
              .collection("roadChargeRefundEntitlements")
              .doc(entitlement.entitlementId),
            {
              ...entitlement,
              actualTraversalVersion: actualTraversal.version,
              actualTraversalStatus: actualTraversal.status,
              createdAt: FieldValue.serverTimestamp(),
              updatedAt: FieldValue.serverTimestamp(),
            },
            {merge: true},
          );
          refundEntitlementIds.push(entitlement.entitlementId);
        }
      }
    }
    if (nextStatus === "delivered") {
      transaction.set(
        evidenceRecordRef.collection("events").doc("delivery_completed"),
        {
          type: "DELIVERY_COMPLETED",
          deliveryId: found.id,
          actorUid: riderId,
          at: FieldValue.serverTimestamp(),
          immutable: true,
        },
        {merge: false},
      );
      transaction.set(
        evidenceRecordRef,
        {
          completedAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        },
        {merge: true},
      );
    }
    evidenceAuthority.writeVerified({
      db,
      transaction,
      resolved: resolvedEvidence,
      deliveryId: found.id,
      riderId,
    });
    transaction.set(found.ref, patch, {merge: true});
    if (nextStatus === "delivered") {
      publishDeliveryCompleted({
        transaction,
        db,
        event: buildDeliveryCompletedEvent({
          deliveryId: found.id,
          delivery,
          riderId,
          trustPoints: canonicalAward,
          verification: {
            pickupPinVerified:
              delivery.collectionPinVerified === true ||
              delivery.pickupPinVerified === true,
            deliveryPinVerified:
              Boolean(requiredPin) || delivery.deliveryPinVerified === true,
            evidenceVerified: evidenceDecision.valid,
          },
          evidence,
        }),
      });
      const settlement = settlementValues(delivery);
      if (earningRef && existingEarning && !existingEarning.exists) {
        transaction.set(earningRef, {
          transactionId: found.id,
          deliveryId: found.id,
          riderId,
          type: "delivery_earning",
          amount: settlement.amount + finalRoadSettlement.reimbursement,
          baseAmount: settlement.amount,
          roadReimbursement: finalRoadSettlement.reimbursement,
          trustPoints: settlement.trustPoints,
          status: "completed",
          createdAt: FieldValue.serverTimestamp(),
        });
        finalRoadSettlement.effects.forEach((effect, index) => {
          if (roadEffectSnapshots[index] && roadEffectSnapshots[index].exists) {
            return;
          }
          transaction.create(roadEffectRefs[index], {
            ...effect,
            reimbursement: Math.round(effect.reimbursementPence) / 100,
            settlementId: earningRef.id,
            createdAt: FieldValue.serverTimestamp(),
          });
        });
        finalRoadSettlement.dailyUpdates.forEach((update, index) => {
          const effect = finalRoadSettlement.effects.find(
            (item) =>
              item.chargeId === update.charge.chargeId &&
              item.role === "ccz_recovery",
          );
          if (!effect || effect.reimbursementPence <= 0) return;
          const current = dailySnapshots[index].exists ?
            dailySnapshots[index].data() :
            {};
          transaction.set(
            dailyRefs[index],
            {
              vehicleId: assignedVehicle.id || null,
              vehicleClass: assignedVehicle.type || null,
              chargingDate: update.charge.chargingDate,
              recoveredPence:
                pence(current.recoveredPence) + effect.reimbursementPence,
              customerContributionPence:
                pence(current.customerContributionPence) +
                effect.customerAmountPence,
              updatedAt: FieldValue.serverTimestamp(),
            },
            {merge: true},
          );
        });
        transaction.set(
          db.collection("riderEarnings").doc(riderId),
          {
            availableBalance: FieldValue.increment(
              settlement.amount + finalRoadSettlement.reimbursement,
            ),
            deliveryEarningsTotal: FieldValue.increment(
              settlement.deliveryAmount,
            ),
            roadChargeReimbursementsTotal: FieldValue.increment(
              finalRoadSettlement.reimbursement,
            ),
            tipsTotal: FieldValue.increment(settlement.tip),
            waitingNoShowTotal: FieldValue.increment(settlement.waiting),
            adjustmentsTotal: FieldValue.increment(settlement.adjustment),
            lifetimeEarnings: FieldValue.increment(
              settlement.amount + finalRoadSettlement.reimbursement,
            ),
            totalAmountEarned: FieldValue.increment(
              settlement.amount + finalRoadSettlement.reimbursement,
            ),
            completedDeliveries: FieldValue.increment(1),
            updatedAt: FieldValue.serverTimestamp(),
          },
          {merge: true},
        );
        if (settlement.trustPoints > 0) {
          transaction.set(
            riderProfileRef,
            riderTrustRankPatch(
              riderProfileSnapshot ? riderProfileSnapshot.data() : {},
              settlement.trustPoints,
            ),
            {merge: true},
          );
        }
        patch.settlementId = earningRef.id;
        patch.settlementCompletedAt = FieldValue.serverTimestamp();
        transaction.set(found.ref, patch, {merge: true});
        transaction.set(
          db.collection("chats").doc(delivery.requestId || found.id),
          {
            readOnly: true,
            completedAt: FieldValue.serverTimestamp(),
            updatedAt: FieldValue.serverTimestamp(),
          },
          {merge: true},
        );
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
      senderTrackingState:
        tracking.senderTrackingStateForBackendStatus(nextStatus),
      refundOwnerType:
        delivery.businessMode === true ||
        delivery.businessId ||
        delivery.businessAccountId ?
          "business" :
          "sender",
      refundOwnerId:
        delivery.businessId ||
        delivery.businessAccountId ||
        delivery.senderId ||
        delivery.userId ||
        null,
      refundOwnerEmail: delivery.senderEmail || delivery.userEmail || null,
    };
  });
  if (refundEntitlementIds.length > 0) {
    for (const entitlementId of [...new Set(refundEntitlementIds)]) {
      const refundOwner =
        result.refundOwnerType === "business" ?
          {type: "business", id: result.refundOwnerId} :
          {
              type: "sender",
              id: result.refundOwnerId,
              email: result.refundOwnerEmail,
            };
      result.roadChargeRefund = await settleEntitlementToRoth({
        db,
        entitlementId,
        owner: refundOwner,
      });
    }
  }
  if (result.verificationFailed) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      `Incorrect PIN. ${Math.max(0, result.attemptsRemaining)} attempts remaining.`,
    );
  }
  return result;
}

exports.updateDeliveryTrackingStatus = functions
  .runWith({enforceAppCheck: true})
  .https.onCall(updateDeliveryTrackingStatusHandler);

async function completeDeliveryHandler(data, context, db = getFirestore()) {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "Rider must be signed in.",
    );
  }
  const deliveryId = text(data && (data.deliveryId || data.requestId));
  const deliveryPin = text(data && (data.deliveryPin || data.pin));
  if (!deliveryId) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "deliveryId is required.",
      {reasonCode: "DELIVERY_ID_REQUIRED"},
    );
  }
  const evidence =
    data && data.evidence && typeof data.evidence === "object" ?
      {...data.evidence} :
      {};
  if (data && data.evidenceId && !evidence.evidenceId) {
    evidence.evidenceId = text(data.evidenceId);
  }
  return updateDeliveryTrackingStatusHandler(
    {
      deliveryId,
      action: "verify_receiver_pin",
      ...(deliveryPin ? {pin: deliveryPin} : {}),
      evidence,
    },
    context,
    db,
  );
}

exports.completeDelivery = functions
  .runWith({enforceAppCheck: true})
  .https.onCall(completeDeliveryHandler);

exports._private = {completeDeliveryHandler};
