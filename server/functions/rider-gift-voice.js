/* eslint-disable max-len, require-jsdoc */
"use strict";

const functions = require("firebase-functions/v1");
const {getFirestore} = require("firebase-admin/firestore");
const {getStorage} = require("firebase-admin/storage");
const {riderCallable} = require("./rider-app-check");
const {parseGiftVoiceStoragePath, isAllowedGiftVoiceMime} = require("./gift-voice-media");

const URL_LIFETIME_MS = 5 * 60 * 1000;
const AUTHORIZED_STATES = new Set([
  "accepted", "navigating_to_pickup", "arrived_at_pickup", "waiting",
  "pickup_verification", "pickup_verified", "collected", "picked_up",
  "navigating_to_dropoff", "in_transit", "arrived_at_dropoff", "pin_required",
]);

function text(value) {
  return `${value || ""}`.trim();
}

function authorizeRiderGiftVoice(delivery, riderId) {
  const assignedRiderId = text(delivery.assignedRiderId || delivery.riderId);
  if (!riderId || assignedRiderId !== riderId) {
    throw new functions.https.HttpsError("permission-denied", "This voice note is available only to the assigned Rider.");
  }
  const status = text(delivery.status).toLowerCase().replace(/[\s-]+/g, "_");
  if (!AUTHORIZED_STATES.has(status)) {
    throw new functions.https.HttpsError("failed-precondition", "Accept this Gift delivery before playing its voice note.");
  }
  const voice = delivery.voiceNote && typeof delivery.voiceNote === "object" ? delivery.voiceNote : {};
  const parsed = parseGiftVoiceStoragePath(voice.storagePath);
  const mimeType = text(voice.mimeType || "audio/webm");
  if (!parsed || !isAllowedGiftVoiceMime(mimeType)) {
    throw new functions.https.HttpsError("not-found", "This Gift delivery has no playable voice note.");
  }
  return {
    storagePath: parsed.storagePath,
    mimeType,
    durationSeconds: Number(voice.durationSeconds || 0),
  };
}

const getRiderGiftVoicePlayback = riderCallable(async (data, context) => {
  if (!context.auth || !context.auth.uid) {
    throw new functions.https.HttpsError("unauthenticated", "Sign in as a Rider.");
  }
  const deliveryId = text(data && data.deliveryId);
  if (!deliveryId) {
    throw new functions.https.HttpsError("invalid-argument", "deliveryId is required.");
  }
  const snapshot = await getFirestore().collection("deliveryRequests").doc(deliveryId).get();
  if (!snapshot.exists) {
    throw new functions.https.HttpsError("not-found", "Delivery not found.");
  }
  const voice = authorizeRiderGiftVoice(snapshot.data() || {}, context.auth.uid);
  const expiresAt = Date.now() + URL_LIFETIME_MS;
  const [playbackUrl] = await getStorage().bucket().file(voice.storagePath).getSignedUrl({
    version: "v4",
    action: "read",
    expires: expiresAt,
  });
  return {
    playbackUrl,
    expiresAt,
    mimeType: voice.mimeType,
    durationSeconds: voice.durationSeconds,
  };
});

module.exports = {
  authorizeRiderGiftVoice,
  getRiderGiftVoicePlayback,
};
