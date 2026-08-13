/* eslint-disable max-len, require-jsdoc */
"use strict";

const crypto = require("crypto");
const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {getStorage} = require("firebase-admin/storage");

const ALLOWED_STAGES = new Set(["pickup", "handover", "discrepancy"]);
const ALLOWED_TYPES = new Set(["image/jpeg", "image/png", "image/webp"]);
const MAX_BYTES = 8 * 1024 * 1024;
const text = (value) => `${value || ""}`.trim();

function requireFirstParty(context) {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Rider must be signed in.");
  if (!context.app) throw new functions.https.HttpsError("failed-precondition", "Security verification is required.");
}

function decodeImage(data) {
  const contentType = text(data && data.contentType).toLowerCase();
  if (!ALLOWED_TYPES.has(contentType)) throw new functions.https.HttpsError("invalid-argument", "Use a JPEG, PNG or WebP image.");
  const encoded = text(data && data.imageBase64);
  if (!encoded || encoded.length > Math.ceil(MAX_BYTES * 4 / 3) + 16) throw new functions.https.HttpsError("invalid-argument", "Evidence image is missing or too large.");
  const bytes = Buffer.from(encoded, "base64");
  if (!bytes.length || bytes.length > MAX_BYTES) throw new functions.https.HttpsError("invalid-argument", "Evidence image is missing or too large.");
  const signatureValid = contentType === "image/jpeg" ?
    bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff :
    contentType === "image/png" ?
      bytes.length >= 8 && bytes.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) :
      bytes.length >= 12 && bytes.subarray(0, 4).toString("ascii") === "RIFF" && bytes.subarray(8, 12).toString("ascii") === "WEBP";
  if (!signatureValid) throw new functions.https.HttpsError("invalid-argument", "The evidence file does not match its image type.");
  return {bytes, contentType};
}

async function assignedDelivery(db, deliveryId, riderId) {
  const direct = await db.collection("deliveryRequests").doc(deliveryId).get();
  if (!direct.exists) throw new functions.https.HttpsError("not-found", "Delivery not found.");
  const delivery = direct.data() || {};
  const assigned = text(delivery.riderId || delivery.driverId || delivery.assignedRiderId || delivery.assignedDriverId);
  if (assigned !== riderId) throw new functions.https.HttpsError("permission-denied", "Only the assigned Rider can upload evidence.");
  const status = text(delivery.status || delivery.deliveryStatus).toLowerCase();
  if (["cancelled", "canceled", "failed", "delivered", "completed"].includes(status)) {
    throw new functions.https.HttpsError("failed-precondition", "Evidence cannot be added in this delivery state.");
  }
  return direct;
}

exports.submitDeliveryEvidence = functions.https.onCall(async (data, context) => {
  requireFirstParty(context);
  const deliveryId = text(data && data.deliveryId);
  const stage = text(data && data.stage).toLowerCase();
  if (!deliveryId || !ALLOWED_STAGES.has(stage)) throw new functions.https.HttpsError("invalid-argument", "A valid delivery evidence stage is required.");
  const {bytes, contentType} = decodeImage(data);
  const riderId = context.auth.uid;
  const db = getFirestore();
  await assignedDelivery(db, deliveryId, riderId);
  const checksumSha256 = crypto.createHash("sha256").update(bytes).digest("hex");
  const evidenceId = crypto.createHash("sha256").update(`${deliveryId}:${riderId}:${stage}:${checksumSha256}`).digest("hex");
  const evidenceRef = db.collection("deliveryEvidence").doc(evidenceId);
  const existing = await evidenceRef.get();
  if (existing.exists) return {evidenceId, stage, status: "verified", idempotent: true};
  const extension = contentType === "image/png" ? "png" : contentType === "image/webp" ? "webp" : "jpg";
  const storagePath = `delivery_evidence/${deliveryId}/${riderId}/${stage}/${evidenceId}.${extension}`;
  const file = getStorage().bucket().file(storagePath);
  await file.save(bytes, {
    resumable: false,
    validation: "crc32c",
    metadata: {contentType, cacheControl: "private,no-store", metadata: {deliveryId, riderId, stage, evidenceId, checksumSha256}},
  });
  const [metadata] = await file.getMetadata();
  try {
    await evidenceRef.create({
      evidenceId,
      deliveryId,
      riderId,
      stage,
      purpose: stage === "handover" ? "delivery_handover" : stage === "pickup" ? "delivery_pickup" : "delivery_discrepancy",
      storagePath,
      generation: text(metadata.generation),
      checksumSha256,
      contentType,
      size: bytes.length,
      status: "verified",
      immutable: true,
      createdAt: FieldValue.serverTimestamp(),
    });
  } catch (error) {
    if (error && (error.code === 6 || error.code === "already-exists")) {
      return {evidenceId, stage, status: "verified", idempotent: true};
    }
    throw error;
  }
  return {evidenceId, stage, status: "verified", idempotent: false};
});

module.exports._private = {decodeImage, ALLOWED_STAGES, ALLOWED_TYPES, MAX_BYTES};
