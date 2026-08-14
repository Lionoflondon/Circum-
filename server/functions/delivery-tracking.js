/* eslint-disable max-len, require-jsdoc */
"use strict";

const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue, GeoPoint} = require("firebase-admin/firestore");
const {getStorage} = require("firebase-admin/storage");
const tracking = require("./sender-tracking-state-core");
const {highestTrustAward} = require("./trust-award");
const {planRoadChargeSettlement, pence} = require("./road-charge-settlement");
const {standardSettlementAllowed, settlementProduct} = require("./settlement-product-guard");
const {appendPoint, evaluateActualTraversal} = require("./actual-road-traversal");
const {roadChargesFor} = require("./road-charge-settlement");
const {createEntitlement, settleEntitlementToRoth} = require("./scheduled-road-charge-refunds");

function text(value) {
  return `${value || ""}`.trim();
}

function normalized(value) {
  return tracking.normalizeStatus(value);
}

function shouldCaptureTraversalPoint(status) {
  return ["collected", "navigating_to_dropoff", "arrived_at_dropoff"].includes(normalized(status));
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
  if (!text(evidence.evidenceId)) {
    return {valid: false, reason: "Canonical delivery evidence is required."};
  }
  return {valid: true};
}

function evidenceRequired(delivery, action) {
  const pickup = action === "verify_collection_pin";
  const handover = action === "verify_receiver_pin";
  if (!pickup && !handover) return false;
  return pickup ?
    delivery.verificationRequired === true ||
      delivery.requiresVerification === true ||
      delivery.requiresVanguard === true :
    delivery.deliveryPhotoRequired === true ||
      delivery.requiresVanguard === true ||
      delivery.secureHandoverRequired === true;
}

function evidenceStageForAction(action) {
  if (action === "verify_collection_pin") return "pickup";
  if (action === "verify_receiver_pin") return "dropoff";
  return "";
}

function stageMatches(action, stage) {
  const expected = evidenceStageForAction(action);
  const normalizedStage = normalized(stage);
  if (expected === "pickup") return ["pickup", "collection"].includes(normalizedStage);
  if (expected === "dropoff") return ["dropoff", "handover", "delivery"].includes(normalizedStage);
  return true;
}

function evidenceIsFinalized(evidence = {}) {
  const status = normalized(evidence.status);
  return status === "finalized" ||
    status === "verified" ||
    status === "accepted" ||
    !!(evidence.finalizedAt || evidence.verifiedAt);
}

function canonicalMediaReference(evidence = {}) {
  return text(
      evidence.storageObject ||
      evidence.storagePath ||
      evidence.path ||
      evidence.canonicalMediaReference ||
      evidence.mediaReference,
  );
}

function canonicalEvidenceDecision({
  evidenceId,
  evidence,
  deliveryId,
  riderId,
  action,
}) {
  const cleanId = text(evidenceId || evidence && evidence.evidenceId);
  if (!cleanId) return {valid: false, reason: "Canonical delivery evidence is required."};
  if (!evidence) return {valid: false, reason: "Canonical delivery evidence was not found."};
  if (text(evidence.deliveryId) !== text(deliveryId)) {
    return {valid: false, reason: "Evidence does not belong to this delivery."};
  }
  if (text(evidence.riderId) !== text(riderId)) {
    return {valid: false, reason: "Evidence does not belong to this rider."};
  }
  if (!stageMatches(action, evidence.stage || evidence.lifecycleStage || evidence.evidenceStage)) {
    return {valid: false, reason: "Evidence was recorded for the wrong delivery stage."};
  }
  if (!evidenceIsFinalized(evidence)) {
    return {valid: false, reason: "Delivery evidence is still uploading."};
  }
  const mediaReference = canonicalMediaReference(evidence);
  if (!mediaReference) {
    return {valid: false, reason: "Delivery evidence media is not available."};
  }
  return {
    valid: true,
    evidenceId: cleanId,
    stage: evidenceStageForAction(action),
    canonicalMediaReference: mediaReference,
    contentType: text(evidence.contentType) || null,
  };
}

function sanitizedEvidencePatch(decision, riderId) {
  return {
    evidenceId: decision.evidenceId,
    stage: decision.stage,
    canonicalMediaReference: decision.canonicalMediaReference,
    ...(decision.contentType ? {contentType: decision.contentType} : {}),
    recordedAt: FieldValue.serverTimestamp(),
    recordedBy: riderId,
  };
}

async function canonicalEvidenceForTransition({db, transaction, deliveryId, riderId, action, delivery, evidence}) {
  const supplied = evidence && typeof evidence === "object" ? evidence : {};
  const requiresEvidence = evidenceRequired(delivery, action);
  const evidenceId = text(supplied.evidenceId);
  if ((supplied.photoUrl || supplied.imageUrl || supplied.url) && !evidenceId) {
    throw new functions.https.HttpsError(
        "failed-precondition",
        "A canonical evidence ID is required for delivery evidence.",
    );
  }
  if (!requiresEvidence && !evidenceId) return null;
  const evidenceRef = db.collection("deliveryEvidence").doc(evidenceId);
  const snapshot = await transaction.get(evidenceRef);
  const decision = canonicalEvidenceDecision({
    evidenceId,
    evidence: snapshot.exists ? snapshot.data() : null,
    deliveryId,
    riderId,
    action,
  });
  if (!decision.valid) {
    throw new functions.https.HttpsError("failed-precondition", decision.reason);
  }
  return decision;
}

function normalizeContentType(value) {
  const contentType = text(value || "image/jpeg").toLowerCase();
  if (!/^image\/(jpeg|jpg|png|webp|heic|heif)$/.test(contentType)) {
    throw new functions.https.HttpsError("invalid-argument", "Unsupported evidence image type.");
  }
  return contentType === "image/jpg" ? "image/jpeg" : contentType;
}

function extensionForContentType(contentType) {
  if (contentType === "image/png") return "png";
  if (contentType === "image/webp") return "webp";
  if (contentType === "image/heic") return "heic";
  if (contentType === "image/heif") return "heif";
  return "jpg";
}

function decodeImageBytes(imageBase64) {
  const encoded = text(imageBase64);
  if (!encoded) {
    throw new functions.https.HttpsError("invalid-argument", "Evidence image is required.");
  }
  const bytes = Buffer.from(encoded.replace(/^data:image\/[A-Za-z0-9.+-]+;base64,/, ""), "base64");
  if (!bytes.length) {
    throw new functions.https.HttpsError("invalid-argument", "Evidence image is empty.");
  }
  if (bytes.length > 8 * 1024 * 1024) {
    throw new functions.https.HttpsError("resource-exhausted", "Evidence image is too large.");
  }
  return bytes;
}

function settlementValues(delivery = {}) {
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
  const amount = Number.isFinite(base) ? base : 0;
  return {
    amount: Number.isFinite(amount) && amount > 0 ? Math.round(amount * 100) / 100 : 0,
    deliveryAmount: Math.max(0, Math.round((amount - tip - waiting - adjustment) * 100) / 100),
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

function transitionPolicyDecision(delivery, currentStatus, nextStatus) {
  if (tracking.canTransitionDeliveryStatusForPolicy(delivery, currentStatus, nextStatus)) {
    return {allowed: true, message: ""};
  }
  if (currentStatus === "arrived_at_pickup" && nextStatus === "collected" &&
      tracking.pickupVerificationRequired(delivery)) {
    return {
      allowed: false,
      message: "Complete the required pickup verification before collecting this delivery.",
    };
  }
  return {
    allowed: false,
    message: `Cannot move delivery from ${currentStatus} to ${nextStatus}.`,
  };
}

exports.recordDeliveryEvidence = functions.runWith({enforceAppCheck: true}).https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Rider must be signed in.");
  }
  const deliveryId = text(data && (data.deliveryId || data.requestId));
  const action = normalized(data && data.action);
  const stage = text(data && data.stage) || evidenceStageForAction(action);
  if (!deliveryId) {
    throw new functions.https.HttpsError("invalid-argument", "deliveryId is required.");
  }
  const normalizedStage = normalized(stage);
  if (!["pickup", "collection", "dropoff", "handover", "delivery"].includes(normalizedStage)) {
    throw new functions.https.HttpsError("invalid-argument", "Evidence stage is not valid for this action.");
  }
  const contentType = normalizeContentType(data && data.contentType);
  const bytes = decodeImageBytes(data && (data.imageBase64 || data.base64 || data.bytesBase64));
  const db = getFirestore();
  const riderId = context.auth.uid;
  const evidenceRef = db.collection("deliveryEvidence").doc();
  const extension = extensionForContentType(contentType);
  let canonicalDeliveryId = deliveryId;

  await db.runTransaction(async (transaction) => {
    const found = await findDelivery(db, transaction, deliveryId);
    if (!found) {
      throw new functions.https.HttpsError("not-found", "Delivery not found.");
    }
    const delivery = found.data || {};
    assertRiderOwnsDelivery(delivery, riderId);
    canonicalDeliveryId = found.id;
    const currentStatus = normalized(delivery.status || delivery.deliveryStatus || delivery.deliveryStage);
    if (["completed", "complete", "delivered", "cancelled", "canceled", "failed", "no_show"].includes(currentStatus)) {
      throw new functions.https.HttpsError("failed-precondition", "Evidence cannot be attached to this delivery state.");
    }
  });

  const canonicalStage = ["pickup", "collection"].includes(normalizedStage) ? "pickup" : "dropoff";
  const storagePath = `deliveryEvidence/${canonicalDeliveryId}/${riderId}/${evidenceRef.id}.${extension}`;

  await getStorage().bucket().file(storagePath).save(bytes, {
    metadata: {
      contentType,
      metadata: {
        deliveryId: canonicalDeliveryId,
        riderId,
        evidenceId: evidenceRef.id,
        stage: canonicalStage,
        source: text(data && data.sourceSurface) || "rider",
      },
    },
    resumable: false,
  });

  await evidenceRef.set({
    evidenceId: evidenceRef.id,
    deliveryId: canonicalDeliveryId,
    riderId,
    evidenceType: "photo",
    stage: canonicalStage,
    lifecycleStage: canonicalStage,
    storageObject: storagePath,
    storagePath,
    contentType,
    sourceSurface: text(data && data.sourceSurface) || "rider",
    visibility: stage === "dropoff" || stage === "handover" ? "sender_safe" : "rider_admin",
    status: "finalized",
    finalizedAt: FieldValue.serverTimestamp(),
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });

  return {
    success: true,
    evidenceId: evidenceRef.id,
    deliveryId: canonicalDeliveryId,
    stage: canonicalStage,
    contentType,
  };
});

exports.getDeliveryEvidenceAccess = functions.runWith({enforceAppCheck: true}).https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Sign in first.");
  }
  const evidenceId = text(data && data.evidenceId);
  if (!evidenceId) {
    throw new functions.https.HttpsError("invalid-argument", "evidenceId is required.");
  }
  const snapshot = await getFirestore().collection("deliveryEvidence").doc(evidenceId).get();
  if (!snapshot.exists) {
    throw new functions.https.HttpsError("not-found", "Evidence not found.");
  }
  const evidence = snapshot.data() || {};
  const deliveryId = text(evidence.deliveryId);
  const deliverySnapshot = await getFirestore().collection("deliveryRequests").doc(deliveryId).get();
  const delivery = deliverySnapshot.exists ? deliverySnapshot.data() || {} : {};
  const uid = context.auth.uid;
  const senderId = text(delivery.senderId || delivery.userId || delivery.customerId);
  const riderId = text(delivery.riderId || delivery.assignedRiderId);
  const isAdmin = context.auth.token && (context.auth.token.admin === true || context.auth.token.role === "admin");
  const visibility = normalized(evidence.visibility);
  const senderAllowed = uid === senderId && ["sender_safe", "proof_of_delivery", "public_to_sender"].includes(visibility);
  const riderAllowed = uid === riderId && text(evidence.riderId) === uid;
  if (!isAdmin && !senderAllowed && !riderAllowed) {
    throw new functions.https.HttpsError("permission-denied", "You cannot access this evidence.");
  }
  const storagePath = canonicalMediaReference(evidence);
  if (!storagePath) {
    throw new functions.https.HttpsError("failed-precondition", "Evidence media is unavailable.");
  }
  const [url] = await getStorage().bucket().file(storagePath).getSignedUrl({
    version: "v4",
    action: "read",
    expires: Date.now() + 10 * 60 * 1000,
  });
  return {
    success: true,
    evidenceId,
    deliveryId,
    url,
    expiresAt: Date.now() + 10 * 60 * 1000,
    contentType: text(evidence.contentType) || null,
  };
});

exports.updateDeliveryTrackingStatus = functions.runWith({enforceAppCheck: true}).https.onCall(async (data, context) => {
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
    const transitionDecision = transitionPolicyDecision(delivery, currentStatus, nextStatus);
    if (!transitionDecision.allowed) {
      throw new functions.https.HttpsError("failed-precondition", transitionDecision.message);
    }
    if (nextStatus === "delivered" && !standardSettlementAllowed(delivery)) {
      throw new functions.https.HttpsError(
          "failed-precondition",
          `Settlement for ${settlementProduct(delivery)} deliveries must use its domain completion authority.`,
      );
    }

    const evidence = data && data.evidence && typeof data.evidence === "object" ? data.evidence : {};
    const evidenceDecision = evidenceRequirements(delivery, action, evidence);
    if (!evidenceDecision.valid) {
      throw new functions.https.HttpsError("failed-precondition", evidenceDecision.reason);
    }
    const canonicalEvidence = await canonicalEvidenceForTransition({
      db,
      transaction,
      deliveryId: found.id,
      riderId,
      action,
      delivery,
      evidence,
    });


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
    if (canonicalEvidence) {
      patch[action === "verify_receiver_pin" ? "handoverEvidence" : "pickupEvidence"] = {
        ...sanitizedEvidencePatch(canonicalEvidence, riderId),
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
    const assignedVehicle = {
      id: delivery.assignedVehicleId,
      type: delivery.assignedVehicleClass,
      ...(delivery.assignedVehicleSnapshot || {}),
    };
    const roadSettlement = nextStatus === "delivered" ?
      planRoadChargeSettlement({
        deliveryId: found.id,
        riderId,
        delivery,
        assignedVehicle,
      }) : {effects: [], dailyUpdates: [], reimbursementPence: 0, reimbursement: 0};
    const roadEffectRefs = roadSettlement.effects.map((effect) =>
      db.collection("riderRoadChargeTransactions").doc(effect.id));
    const dailyRefs = roadSettlement.dailyUpdates.map((update) =>
      db.collection("roadChargeDailyLiabilities").doc(update.id));
    const roadEffectSnapshots = await Promise.all(roadEffectRefs.map((ref) => transaction.get(ref)));
    const dailySnapshots = await Promise.all(dailyRefs.map((ref) => transaction.get(ref)));
    const freshDailyState = {};
    roadSettlement.dailyUpdates.forEach((update, index) => {
      freshDailyState[update.id] = dailySnapshots[index].exists ? dailySnapshots[index].data() : {};
    });
    const finalRoadSettlement = nextStatus === "delivered" ?
      planRoadChargeSettlement({deliveryId: found.id, riderId, delivery, assignedVehicle, dailyState: freshDailyState}) : roadSettlement;
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
    if (nextStatus === "delivered" && delivery.deliveryTime &&
        delivery.deliveryTime.type === "scheduled" &&
        ["standard", "business"].includes(settlementProduct(delivery))) {
      const traversalRef = db.collection("deliveryTraversalEvidence").doc(found.id);
      const traversalSnapshot = await transaction.get(traversalRef);
      const traversal = traversalSnapshot.exists ? traversalSnapshot.data() || {} : {};
      const actualTraversal = evaluateActualTraversal({
        deliveryId: found.id,
        riderId,
        assignedVehicle,
        points: traversal.points,
      });
      transaction.set(traversalRef, {
        ...actualTraversal,
        completeness: actualTraversal.evidenceCompleteness,
        reconciledAt: FieldValue.serverTimestamp(),
      }, {merge: true});
      patch.actualRoadTraversalFacts = actualTraversal;
      if (actualTraversal.evidenceCompleteness === "COMPLETE") {
        for (const charge of roadChargesFor(delivery)) {
          const entitlement = createEntitlement({
            deliveryId: found.id,
            quoteId: delivery.quoteId,
            charge,
            actualEvidence: {authoritative: true, incurred: actualTraversal.status === "INCURRED"},
          });
          entitlement.refundOwnerType = delivery.businessMode === true || delivery.businessId || delivery.businessAccountId ? "business" : "sender";
          entitlement.refundOwnerId = entitlement.refundOwnerType === "business" ?
            delivery.businessId || delivery.businessAccountId : delivery.senderId || delivery.userId;
          entitlement.refundOwnerEmail = delivery.senderEmail || delivery.userEmail || null;
          const actualCharge = actualTraversal.charges.find((item) => item.chargeId === charge.chargeId);
          const prepaidPence = Number(charge.customerContributionPence || charge.amountPence || 0);
          const actualPence = Number(actualCharge && (actualCharge.customerContributionPence || actualCharge.amountPence) || 0);
          entitlement.refundablePence = Math.max(0, prepaidPence - actualPence);
          if (entitlement.refundablePence === 0) entitlement.state = "CLOSED";
          transaction.set(db.collection("roadChargeRefundEntitlements").doc(entitlement.entitlementId), {
            ...entitlement,
            actualTraversalVersion: actualTraversal.version,
            actualTraversalStatus: actualTraversal.status,
            createdAt: FieldValue.serverTimestamp(),
            updatedAt: FieldValue.serverTimestamp(),
          }, {merge: true});
          refundEntitlementIds.push(entitlement.entitlementId);
        }
      }
    }
    transaction.set(found.ref, patch, {merge: true});
    if (nextStatus === "delivered") {
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
          if (roadEffectSnapshots[index] && roadEffectSnapshots[index].exists) return;
          transaction.create(roadEffectRefs[index], {
            ...effect,
            reimbursement: Math.round(effect.reimbursementPence) / 100,
            settlementId: earningRef.id,
            createdAt: FieldValue.serverTimestamp(),
          });
        });
        finalRoadSettlement.dailyUpdates.forEach((update, index) => {
          const effect = finalRoadSettlement.effects.find((item) =>
            item.chargeId === update.charge.chargeId && item.role === "ccz_recovery");
          if (!effect || effect.reimbursementPence <= 0) return;
          const current = dailySnapshots[index].exists ? dailySnapshots[index].data() : {};
          transaction.set(dailyRefs[index], {
            vehicleId: assignedVehicle.id || null,
            vehicleClass: assignedVehicle.type || null,
            chargingDate: update.charge.chargingDate,
            recoveredPence: pence(current.recoveredPence) + effect.reimbursementPence,
            customerContributionPence: pence(current.customerContributionPence) + effect.customerAmountPence,
            updatedAt: FieldValue.serverTimestamp(),
          }, {merge: true});
        });
        transaction.set(db.collection("riderEarnings").doc(riderId), {
          availableBalance: FieldValue.increment(settlement.amount + finalRoadSettlement.reimbursement),
          deliveryEarningsTotal: FieldValue.increment(settlement.deliveryAmount),
          roadChargeReimbursementsTotal: FieldValue.increment(finalRoadSettlement.reimbursement),
          tipsTotal: FieldValue.increment(settlement.tip),
          waitingNoShowTotal: FieldValue.increment(settlement.waiting),
          adjustmentsTotal: FieldValue.increment(settlement.adjustment),
          lifetimeEarnings: FieldValue.increment(settlement.amount + finalRoadSettlement.reimbursement),
          totalAmountEarned: FieldValue.increment(settlement.amount + finalRoadSettlement.reimbursement),
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
      refundOwnerType: delivery.businessMode === true || delivery.businessId || delivery.businessAccountId ? "business" : "sender",
      refundOwnerId: delivery.businessId || delivery.businessAccountId || delivery.senderId || delivery.userId || null,
      refundOwnerEmail: delivery.senderEmail || delivery.userEmail || null,
    };
  });
  if (refundEntitlementIds.length > 0) {
    for (const entitlementId of [...new Set(refundEntitlementIds)]) {
      const refundOwner = result.refundOwnerType === "business" ?
        {type: "business", id: result.refundOwnerId} :
        {type: "sender", id: result.refundOwnerId, email: result.refundOwnerEmail};
      result.roadChargeRefund = await settleEntitlementToRoth({db, entitlementId, owner: refundOwner});
    }
  }
  if (result.verificationFailed) {
    throw new functions.https.HttpsError(
        "failed-precondition",
        `Incorrect PIN. ${Math.max(0, result.attemptsRemaining)} attempts remaining.`,
    );
  }
  return result;
});

exports.updateDeliveryLiveLocation = functions.runWith({enforceAppCheck: true}).https.onCall(async (data, context) => {
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
    if (shouldCaptureTraversalPoint(currentStatus)) {
      const evidenceRef = db.collection("deliveryTraversalEvidence").doc(found.id);
      const evidenceSnapshot = await transaction.get(evidenceRef);
      const existing = evidenceSnapshot.exists ? evidenceSnapshot.data() || {} : {};
      transaction.set(evidenceRef, {
        deliveryId: found.id,
        riderId,
        assignedVehicleId: delivery.assignedVehicleId || null,
        assignedVehicleClass: delivery.assignedVehicleClass || null,
        evidenceVersion: "2026-08-actual-road-traversal-v1",
        points: appendPoint(existing.points, {
          latitude: location.latitude,
          longitude: location.longitude,
          at: new Date().toISOString(),
        }),
        completeness: "PARTIAL",
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    }
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
  transitionPolicyDecision,
  expectedPin,
  pinAuthorityRequired,
  assertRiderOwnsDelivery,
  assertRiderOperational,
  evidenceRequirements,
  evidenceRequired,
  evidenceStageForAction,
  stageMatches,
  evidenceIsFinalized,
  canonicalMediaReference,
  canonicalEvidenceDecision,
  sanitizedEvidencePatch,
  normalizeContentType,
  decodeImageBytes,
  settlementValues,
  highestTrustAward,
  canonicalRiderRankForTrust,
  hasManualRankOverride,
  shouldCaptureTraversalPoint,
  riderTrustRankPatch,
};
