/* eslint-disable max-len, require-jsdoc */
"use strict";

const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {getStorage} = require("firebase-admin/storage");
const evidence = require("./delivery-evidence-core");
const {appendOperationalEvent} = require("./delivery-operational-events");

const TYPES = new Set(["pickup", "custody", "handover", "verification", "exception"]);

function text(value, max = 500) {
  return `${value || ""}`.trim().slice(0, max);
}

function canonicalPath(pickupId, evidenceType, storagePath) {
  const prefix = `health_delivery_evidence/${pickupId}/${evidenceType}/`;
  return storagePath.startsWith(prefix) && !storagePath.slice(prefix.length).includes("/");
}

async function verifyHealthEvidence({bucket, pickupId, evidenceType, storagePath, riderId}) {
  if (!TYPES.has(evidenceType) || !canonicalPath(pickupId, evidenceType, storagePath)) {
    throw new Error("Health+ evidence path is not canonical.");
  }
  const file = bucket.file(storagePath);
  const [exists] = await file.exists();
  if (!exists) throw new Error("Health+ evidence upload was not found.");
  const [metadata] = await file.getMetadata();
  const custom = metadata.metadata || {};
  if (text(custom.pickupId) !== pickupId || text(custom.evidenceType) !== evidenceType || text(custom.uploadedBy) !== riderId) {
    throw new Error("Health+ evidence ownership metadata does not match.");
  }
  return evidence.immutableStorageReference({
    storagePath,
    metadata,
    uploadedBy: riderId,
    context: {domain: "health_plus", pickupId, evidenceType},
  });
}

exports.recordHealthPlusEvidence = functions.runWith({enforceAppCheck: true}).https.onCall(async (data, context) => {
  const riderId = context.auth && context.auth.uid;
  if (!riderId) throw new functions.https.HttpsError("unauthenticated", "Rider must be signed in.");
  const pickupId = text(data && data.pickupId, 240);
  const evidenceType = text(data && data.evidenceType, 80).toLowerCase();
  const storagePath = text(data && data.storagePath, 700);
  if (!pickupId || !evidenceType || !storagePath) throw new functions.https.HttpsError("invalid-argument", "Health+ evidence identity is required.");
  const db = getFirestore();
  const pickupRef = db.collection("prescriptionPickups").doc(pickupId);
  const canonicalDeliveryId = `health_${pickupId}`;
  const [pickupSnap, deliverySnap] = await Promise.all([
    pickupRef.get(),
    db.collection("deliveryRequests").doc(canonicalDeliveryId).get(),
  ]);
  const pickup = pickupSnap.exists ? pickupSnap.data() || {} : {};
  const delivery = deliverySnap.exists ? deliverySnap.data() || {} : {};
  const assignedRiderId = text(delivery.assignedRiderId || delivery.riderId ||
    delivery.assignedDriverId || pickup.assignedDriverId);
  if (!pickupSnap.exists || assignedRiderId !== riderId) {
    throw new functions.https.HttpsError("permission-denied", "Only the assigned Rider can submit Health+ evidence.");
  }
  const status = text(pickup.status).toLowerCase();
  if (["delivered", "completed", "cancelled", "failed"].includes(status)) {
    throw new functions.https.HttpsError("failed-precondition", "Health+ evidence cannot be added after closure.");
  }
  let reference;
  try {
    reference = await verifyHealthEvidence({bucket: getStorage().bucket(), pickupId, evidenceType, storagePath, riderId});
  } catch (error) {
    throw new functions.https.HttpsError("failed-precondition", error.message);
  }
  const evidenceRef = db.collection("healthPlusEvidence").doc(pickupId).collection("items").doc(reference.evidenceId);
  const custodyRef = db.collection("healthPlusCustodyArchive").doc(`${pickupId}_evidence_${reference.evidenceId}`);
  await db.runTransaction(async (tx) => {
    const existing = await tx.get(evidenceRef);
    if (existing.exists) return;
    tx.create(evidenceRef, {...reference, deliveryId: text(pickup.deliveryId) || canonicalDeliveryId, pickupId, evidenceType, recordedAt: FieldValue.serverTimestamp()});
    tx.create(custodyRef, {pickupId, deliveryId: text(pickup.deliveryId) || canonicalDeliveryId, eventType: "evidence_uploaded", evidenceId: reference.evidenceId, evidenceType, actorType: "rider", actorId: riderId, statusAfterEvent: status, immutable: true, createdAt: FieldValue.serverTimestamp()});
    tx.set(pickupRef, {latestEvidenceId: reference.evidenceId, evidenceCount: FieldValue.increment(1), evidenceUpdatedAt: FieldValue.serverTimestamp()}, {merge: true});
  });
  await appendOperationalEvent(db, {deliveryId: text(pickup.deliveryId) || canonicalDeliveryId, eventType: "EvidenceUploaded", correlationId: reference.evidenceId, actorType: "rider", actorId: riderId, source: "healthPlusEvidence", metadata: {pickupId, evidenceId: reference.evidenceId, evidenceType, verified: true}});
  return {pickupId, evidenceId: reference.evidenceId, verified: true, immutable: true};
});

exports._private = {canonicalPath, verifyHealthEvidence};
