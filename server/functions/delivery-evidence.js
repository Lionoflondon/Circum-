/* eslint-disable max-len, require-jsdoc */
"use strict";

const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {getStorage} = require("firebase-admin/storage");
const evidence = require("./delivery-evidence-core");

function text(value) {
  return `${value || ""}`.trim();
}

function assignedTo(delivery, uid) {
  return [delivery.riderId, delivery.driverId, delivery.assignedRiderId, delivery.assignedDriverId]
      .map(text).includes(uid);
}

function evidencePurposeForDelivery(delivery = {}) {
  const status = text(delivery.status || delivery.deliveryStatus || delivery.deliveryStage).toLowerCase();
  if (["arrived_at_pickup", "pickup_verification", "pickup_verified"].includes(status)) return "PICKUP";
  if (["collected", "in_transit", "navigating_to_dropoff", "arrived_at_dropoff", "delivery_verification"].includes(status)) {
    return "HANDOVER";
  }
  return null;
}

async function findDelivery(db, deliveryId) {
  const direct = await db.collection("deliveryRequests").doc(deliveryId).get();
  if (direct.exists) return direct;
  const query = await db.collection("deliveryRequests").where("requestId", "==", deliveryId).limit(1).get();
  return query.empty ? null : query.docs[0];
}

exports.recordDeliveryEvidence = functions.runWith({enforceAppCheck: true}).https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Rider must be signed in.");
  const input = {...(data || {})};
  const decision = evidence.validatePhotoInput(input);
  if (!decision.valid) throw new functions.https.HttpsError("invalid-argument", decision.reason);

  const db = getFirestore();
  const deliverySnapshot = await findDelivery(db, decision.deliveryId);
  if (!deliverySnapshot) throw new functions.https.HttpsError("not-found", "Delivery not found.");
  const delivery = deliverySnapshot.data() || {};
  if (!assignedTo(delivery, context.auth.uid)) {
    throw new functions.https.HttpsError("permission-denied", "Only the assigned rider can submit delivery evidence.");
  }
  const status = text(delivery.status || delivery.deliveryStatus || delivery.deliveryStage).toLowerCase();
  if (["delivered", "completed", "cancelled", "failed", "expired", "archived"].includes(status)) {
    throw new functions.https.HttpsError("failed-precondition", "Evidence cannot be added after delivery completion.");
  }

  const file = getStorage().bucket().file(decision.storagePath);
  const [exists] = await file.exists();
  if (!exists) throw new functions.https.HttpsError("failed-precondition", "Evidence photo upload was not found.");
  const [metadata] = await file.getMetadata();
  const actualSize = Number(metadata.size);
  const actualMime = text(metadata.contentType).toLowerCase();
  if (actualMime !== decision.mimeType || actualSize !== decision.fileSize) {
    throw new functions.https.HttpsError("failed-precondition", "Evidence photo metadata does not match the upload.");
  }
  if (text(input.checksum) && text(metadata.md5Hash) && text(input.checksum) !== text(metadata.md5Hash)) {
    throw new functions.https.HttpsError("failed-precondition", "Evidence photo checksum does not match the upload.");
  }
  const purpose = evidencePurposeForDelivery(delivery);
  const declaredPurpose = evidence.evidencePurpose(input.purpose || input.context?.purpose);
  if (!purpose || (declaredPurpose && declaredPurpose !== purpose)) {
    throw new functions.https.HttpsError("failed-precondition", "Evidence does not match the current delivery phase.");
  }

  const recordRef = db.collection("deliveryEvidence").doc(deliverySnapshot.id);
  const photoRef = recordRef.collection("photos").doc(decision.photoId);
  const capturedEventRef = recordRef.collection("events").doc(`${decision.photoId}_captured`);
  const uploadedEventRef = recordRef.collection("events").doc(`${decision.photoId}_uploaded`);
  const photo = evidence.evidenceSummary({
    ...input,
    fileSize: actualSize,
    mimeType: actualMime,
    checksum: text(input.checksum) || text(metadata.md5Hash),
    generation: text(metadata.generation),
    purpose,
    context: {purpose},
    thumbnailPath: `deliveries/${decision.deliveryId}/evidence/thumbnails/${decision.photoId}.jpg`,
  }, context.auth.uid);
  await db.runTransaction(async (transaction) => {
    const existing = await transaction.get(photoRef);
    // Storage finalize may create a thumbnail-only photo document before this
    // callable records the verified upload. Only a fully finalized record is
    // idempotently complete.
    if (existing.exists && evidence.isVerifiedPhotoRecord(existing.data() || {})) return;
    transaction.set(photoRef, {
      ...photo,
      id: decision.photoId,
      deliveryId: deliverySnapshot.id,
      uploadedAt: FieldValue.serverTimestamp(),
      serverTimestamp: FieldValue.serverTimestamp(),
      immutable: true,
      verified: true,
    });
    transaction.set(recordRef, {
      deliveryId: deliverySnapshot.id,
      verifiedPhotoCount: FieldValue.increment(1),
      latestPhotoPath: decision.storagePath,
      latestThumbnailPath: photo.thumbnailPath,
      latestCapturedAt: photo.capturedAt,
      latestDevice: photo.device,
      latestGps: photo.gps,
      latestAccuracy: photo.accuracy,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    transaction.set(capturedEventRef, {
      type: "PHOTO_CAPTURED",
      deliveryId: deliverySnapshot.id,
      photoId: decision.photoId,
      actorUid: context.auth.uid,
      at: FieldValue.serverTimestamp(),
      immutable: true,
    });
    transaction.set(uploadedEventRef, {
      type: "PHOTO_UPLOADED",
      deliveryId: deliverySnapshot.id,
      photoId: decision.photoId,
      actorUid: context.auth.uid,
      at: FieldValue.serverTimestamp(),
      immutable: true,
    });
  });
  return {
    success: true,
    deliveryId: deliverySnapshot.id,
    photoId: decision.photoId,
    storagePath: decision.storagePath,
    verified: true,
  };
});
