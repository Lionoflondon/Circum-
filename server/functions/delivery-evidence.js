/* eslint-disable max-len, require-jsdoc */
"use strict";

const crypto = require("node:crypto");
const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {getStorage} = require("firebase-admin/storage");
const {requireAppCheck} = require("./callable-guard");

const MAX_EVIDENCE_BYTES = 12 * 1024 * 1024;
const ALLOWED_IMAGE_TYPES = new Set(["image/jpeg", "image/jpg", "image/png", "image/webp", "image/heic"]);

function text(value, max = 500) {
  return `${value || ""}`.trim().slice(0, max);
}

function hasRole(context, role) {
  const token = context.auth && context.auth.token || {};
  return token.adminRole === role ||
    token.role === role ||
    (Array.isArray(token.roles) && token.roles.includes(role));
}

function isAdmin(context) {
  return ["super_admin", "operations_admin", "support_agent", "driver_manager"].some((role) => hasRole(context, role));
}

async function findDelivery(db, deliveryId) {
  const cleanId = text(deliveryId, 160);
  const directRef = db.collection("deliveryRequests").doc(cleanId);
  const direct = await directRef.get();
  if (direct.exists) return {ref: directRef, id: direct.id, data: direct.data() || {}};
  const query = await db.collection("deliveryRequests")
      .where("requestId", "==", cleanId)
      .limit(1)
      .get();
  if (query.empty) return null;
  const doc = query.docs[0];
  return {ref: doc.ref, id: doc.id, data: doc.data() || {}};
}

function assignedRiderId(delivery = {}) {
  return text(delivery.riderId || delivery.driverId || delivery.assignedRiderId || delivery.assignedDriverId, 160);
}

function assertAssignedRider(delivery, riderId) {
  if (assignedRiderId(delivery) !== riderId) {
    throw new functions.https.HttpsError("permission-denied", "Only the assigned rider can submit delivery evidence.");
  }
}

function normalizeEvidenceType(value) {
  const clean = text(value, 80).toLowerCase().replace(/[-\s]+/g, "_");
  if (["pickup", "pickup_proof", "collection", "collection_proof"].includes(clean)) return "pickup_proof";
  if (["completion", "completion_proof", "proof_of_delivery", "handover"].includes(clean)) return "completion_proof";
  if (["discrepancy", "adjudication", "load_discrepancy"].includes(clean)) return "discrepancy";
  return "operational_evidence";
}

function normalizeLifecycleStage(value, evidenceType) {
  const clean = text(value, 80).toLowerCase().replace(/[-\s]+/g, "_");
  if (clean) return clean;
  if (evidenceType === "pickup_proof") return "pickup";
  if (evidenceType === "completion_proof") return "completion";
  return "operational";
}

function visibilityFor(evidenceType, delivery = {}) {
  if (evidenceType === "completion_proof") {
    if (delivery.isHealthPlus === true || delivery.healthPlus === true) return "rider_admin";
    return "rider_sender_admin";
  }
  if (evidenceType === "pickup_proof") return "rider_admin";
  return "rider_admin";
}

function decodeImage(data) {
  const contentType = text(data.contentType, 120).toLowerCase();
  if (!ALLOWED_IMAGE_TYPES.has(contentType)) {
    throw new functions.https.HttpsError("invalid-argument", "Unsupported evidence image type.");
  }
  const raw = text(data.fileBase64 || data.imageBase64 || data.base64, Math.ceil(MAX_EVIDENCE_BYTES * 1.4) + 128)
      .replace(/^data:image\/[a-z0-9.+-]+;base64,/i, "")
      .replace(/\s/g, "");
  if (!raw) throw new functions.https.HttpsError("invalid-argument", "Evidence image is required.");
  const bytes = Buffer.from(raw, "base64");
  if (!bytes.length || bytes.length > MAX_EVIDENCE_BYTES) {
    throw new functions.https.HttpsError("invalid-argument", "Evidence image is too large.");
  }
  return {bytes, contentType};
}

function extensionFor(contentType) {
  if (contentType === "image/png") return "png";
  if (contentType === "image/webp") return "webp";
  if (contentType === "image/heic") return "heic";
  return "jpg";
}

function evidenceStoragePath({deliveryId, riderId, evidenceId, contentType}) {
  return `deliveryEvidence/${deliveryId}/${riderId}/${evidenceId}.${extensionFor(contentType)}`;
}

exports.recordDeliveryEvidence = functions.https.onCall(async (data, context) => {
  requireAppCheck(context);
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Rider must be signed in.");
  const deliveryId = text(data && (data.deliveryId || data.requestId), 160);
  if (!deliveryId) throw new functions.https.HttpsError("invalid-argument", "deliveryId is required.");
  const {bytes, contentType} = decodeImage(data || {});
  const db = getFirestore();
  const found = await findDelivery(db, deliveryId);
  if (!found) throw new functions.https.HttpsError("not-found", "Delivery not found.");
  const delivery = found.data || {};
  const riderId = context.auth.uid;
  assertAssignedRider(delivery, riderId);
  const status = text(delivery.status || delivery.deliveryStatus || delivery.deliveryStage, 80).toLowerCase();
  if (["delivered", "completed", "cancelled", "canceled", "failed"].includes(status)) {
    throw new functions.https.HttpsError("failed-precondition", "Evidence is closed for this delivery.");
  }
  const evidenceType = normalizeEvidenceType(data && data.evidenceType);
  const lifecycleStage = normalizeLifecycleStage(data && data.lifecycleStage, evidenceType);
  const evidenceRef = db.collection("deliveryEvidence").doc();
  const storagePath = evidenceStoragePath({
    deliveryId: found.id,
    riderId,
    evidenceId: evidenceRef.id,
    contentType,
  });
  await getStorage().bucket().file(storagePath).save(bytes, {
    metadata: {
      contentType,
      metadata: {
        deliveryId: found.id,
        riderId,
        evidenceId: evidenceRef.id,
        evidenceType,
        lifecycleStage,
        source: "recordDeliveryEvidence",
      },
    },
    resumable: false,
  });
  const record = {
    evidenceId: evidenceRef.id,
    deliveryId: found.id,
    requestId: delivery.requestId || found.id,
    riderId,
    evidenceType,
    lifecycleStage,
    storagePath,
    contentType,
    sizeBytes: bytes.length,
    sourceSurface: text(data && data.sourceSurface, 80) || "rider",
    visibility: visibilityFor(evidenceType, delivery),
    status: "finalized",
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };
  await evidenceRef.set(record);
  await db.collection("deliveryEvidenceEvents").doc(`${evidenceRef.id}_recorded`).set({
    ...record,
    eventType: "delivery_evidence_recorded",
    actorId: riderId,
    actorType: "rider",
  });
  return {
    ok: true,
    evidenceId: evidenceRef.id,
    deliveryId: found.id,
    evidenceType,
    lifecycleStage,
    visibility: record.visibility,
    status: record.status,
  };
});

exports.getDeliveryEvidenceAccess = functions.https.onCall(async (data, context) => {
  requireAppCheck(context);
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Sign in required.");
  const evidenceId = text(data && data.evidenceId, 160);
  if (!evidenceId) throw new functions.https.HttpsError("invalid-argument", "evidenceId is required.");
  const db = getFirestore();
  const snap = await db.collection("deliveryEvidence").doc(evidenceId).get();
  if (!snap.exists) throw new functions.https.HttpsError("not-found", "Evidence not found.");
  const evidence = snap.data() || {};
  const found = await findDelivery(db, evidence.deliveryId || evidence.requestId);
  const delivery = found ? found.data || {} : {};
  const uid = context.auth.uid;
  const senderId = text(delivery.senderId || delivery.userId || delivery.customerId, 160);
  const riderId = text(evidence.riderId || assignedRiderId(delivery), 160);
  const visibility = text(evidence.visibility || "rider_admin", 80);
  const riderAllowed = uid === riderId;
  const senderAllowed = uid === senderId && visibility.includes("sender");
  if (!riderAllowed && !senderAllowed && !isAdmin(context)) {
    throw new functions.https.HttpsError("permission-denied", "You cannot view this delivery evidence.");
  }
  const nonce = crypto.randomBytes(8).toString("hex");
  const expiresAt = Date.now() + 10 * 60 * 1000;
  const [url] = await getStorage().bucket().file(evidence.storagePath).getSignedUrl({
    version: "v4",
    action: "read",
    expires: expiresAt,
  });
  return {
    ok: true,
    evidenceId,
    deliveryId: evidence.deliveryId,
    evidenceType: evidence.evidenceType,
    lifecycleStage: evidence.lifecycleStage,
    contentType: evidence.contentType,
    accessUrl: url,
    expiresAt,
    nonce,
  };
});

exports._private = {
  evidenceStoragePath,
  normalizeEvidenceType,
  normalizeLifecycleStage,
  visibilityFor,
};
