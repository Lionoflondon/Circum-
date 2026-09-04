/* eslint-disable max-len, require-jsdoc */
"use strict";

const functions = require("firebase-functions/v1");
const {FieldValue, Timestamp} = require("firebase-admin/firestore");
const {getFirestore} = require("firebase-admin/firestore");
const {getStorage} = require("firebase-admin/storage");

const GIFT_VOICE_MIME_TYPES = new Set([
  "audio/webm",
  "audio/mpeg",
  "audio/mp4",
  "audio/aac",
  "audio/ogg",
]);
const GIFT_VOICE_MAX_BYTES = 60 * 1024 * 1024;
const GIFT_VOICE_MAX_DURATION_SECONDS = 60;
const ABANDONED_DRAFT_HOURS = 24;

function text(value) {
  return `${value || ""}`.trim();
}

function parseGiftVoiceStoragePath(storagePath) {
  const path = text(storagePath);
  const match = path.match(/^gift_requests\/([^/]+)_([0-9]+)\/voice\/original\.webm$/);
  if (!match) return null;
  return {
    ownerId: match[1],
    uploadedAtMillis: Number(match[2]),
    storagePath: path,
  };
}

function isAllowedGiftVoiceMime(mimeType) {
  return GIFT_VOICE_MIME_TYPES.has(text(mimeType));
}

function sanitizeGiftVoiceNoteMetadata(voiceNote, senderId) {
  if (!voiceNote || typeof voiceNote !== "object" || Array.isArray(voiceNote)) return null;
  const storagePath = text(voiceNote.storagePath);
  const parsed = parseGiftVoiceStoragePath(storagePath);
  if (!parsed || parsed.ownerId !== senderId) {
    throw new functions.https.HttpsError("permission-denied", "Gift voice note does not belong to this account.");
  }
  const mimeType = text(voiceNote.mimeType || "audio/webm");
  if (!isAllowedGiftVoiceMime(mimeType)) {
    throw new functions.https.HttpsError("invalid-argument", "Gift voice note format is not supported.");
  }
  const durationSeconds = Number(voiceNote.durationSeconds || 0);
  if (!Number.isFinite(durationSeconds) || durationSeconds < 1 || durationSeconds > GIFT_VOICE_MAX_DURATION_SECONDS) {
    throw new functions.https.HttpsError("invalid-argument", "Gift voice note duration is invalid.");
  }
  const downloadUrl = text(voiceNote.downloadUrl);
  if (!downloadUrl) {
    throw new functions.https.HttpsError("invalid-argument", "Gift voice note is missing playback metadata.");
  }
  return {
    hasVoiceNote: true,
    durationSeconds,
    storagePath,
    downloadUrl,
    mimeType,
    createdAt: voiceNote.createdAt || null,
    uploadStatus: "uploaded",
    retryState: "none",
    version: 1,
    ownerId: senderId,
  };
}

async function verifyGiftVoiceStorageObject({bucket, voiceNote, senderId}) {
  const sanitized = sanitizeGiftVoiceNoteMetadata(voiceNote, senderId);
  if (!sanitized) return null;
  const file = bucket.file(sanitized.storagePath);
  const [exists] = await file.exists();
  if (!exists) {
    throw new functions.https.HttpsError("failed-precondition", "Gift voice note upload was not found.");
  }
  const [metadata] = await file.getMetadata();
  const contentType = text(metadata.contentType || sanitized.mimeType);
  if (!isAllowedGiftVoiceMime(contentType)) {
    throw new functions.https.HttpsError("invalid-argument", "Gift voice note upload format is not supported.");
  }
  const size = Number(metadata.size || 0);
  if (!Number.isFinite(size) || size <= 0 || size > GIFT_VOICE_MAX_BYTES) {
    throw new functions.https.HttpsError("invalid-argument", "Gift voice note upload size is invalid.");
  }
  const custom = metadata.metadata || {};
  const ownerId = text(custom.ownerId || custom.uploadedBy || sanitized.ownerId);
  if (ownerId !== senderId) {
    throw new functions.https.HttpsError("permission-denied", "Gift voice note upload owner does not match this account.");
  }
  return sanitized;
}

function giftVoiceLifecycleAudit({
  action,
  actorUid,
  giftDraftId = null,
  giftRequestId = null,
  storagePath = null,
  outcome = "success",
  reason = null,
}) {
  return {
    action,
    actorUid: actorUid || "system",
    giftDraftId: giftDraftId || null,
    giftRequestId: giftRequestId || null,
    storagePath: storagePath || null,
    outcome,
    reason: reason || null,
    createdAt: FieldValue.serverTimestamp(),
  };
}

async function auditGiftVoiceLifecycle(db, payload) {
  await db.collection("giftVoiceMediaAudit").doc().set(giftVoiceLifecycleAudit(payload));
}

async function deleteGiftVoiceStoragePath({bucket, db, storagePath, actorUid = "system", giftDraftId = null, giftRequestId = null, reason}) {
  const path = text(storagePath);
  if (!path || !parseGiftVoiceStoragePath(path)) return false;
  await bucket.file(path).delete({ignoreNotFound: true});
  if (db) {
    await auditGiftVoiceLifecycle(db, {
      action: "gift_voice_media_deleted",
      actorUid,
      giftDraftId,
      giftRequestId,
      storagePath: path,
      reason,
    });
  }
  return true;
}

async function cleanupExpiredGiftVoiceDraftsCore({
  db = getFirestore(),
  bucket = getStorage().bucket(),
  now = Timestamp.now(),
  limit = 200,
} = {}) {
  const cutoff = Timestamp.fromMillis(now.toMillis() - ABANDONED_DRAFT_HOURS * 60 * 60 * 1000);
  const snapshot = await db.collection("giftPaymentDrafts")
      .where("createdAt", "<=", cutoff)
      .where("paymentStatus", "in", ["payment_pending", "checkout_pending"])
      .limit(limit)
      .get();
  let scanned = 0;
  let deletedMedia = 0;
  for (const doc of snapshot.docs) {
    scanned += 1;
    const draft = doc.data() || {};
    const path = text(draft.voiceNote && draft.voiceNote.storagePath);
    if (!path || !parseGiftVoiceStoragePath(path)) continue;
    await deleteGiftVoiceStoragePath({
      bucket,
      db,
      storagePath: path,
      actorUid: "system",
      giftDraftId: doc.id,
      reason: "abandoned_gift_payment_draft",
    });
    await doc.ref.set({
      voiceNote: FieldValue.delete(),
      voiceNoteCleanupStatus: "deleted",
      voiceNoteCleanedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    deletedMedia += 1;
  }
  return {scanned, deletedMedia};
}

async function cleanupGiftVoiceMediaForAccount({
  db = getFirestore(),
  bucket = getStorage().bucket(),
  uid,
  batch = null,
}) {
  const deleted = [];
  const collections = [
    {name: "giftPaymentDrafts", field: "senderId"},
    {name: "giftRequests", field: "senderId"},
  ];
  for (const collection of collections) {
    const snapshot = await db.collection(collection.name)
        .where(collection.field, "==", uid)
        .limit(100)
        .get();
    for (const doc of snapshot.docs) {
      const data = doc.data() || {};
      const path = text(data.voiceNote && data.voiceNote.storagePath);
      if (!path || !parseGiftVoiceStoragePath(path)) continue;
      await deleteGiftVoiceStoragePath({
        bucket,
        db,
        storagePath: path,
        actorUid: uid,
        giftDraftId: collection.name === "giftPaymentDrafts" ? doc.id : null,
        giftRequestId: collection.name === "giftRequests" ? doc.id : null,
        reason: "account_closure",
      });
      deleted.push(path);
      const patch = {
        voiceNote: FieldValue.delete(),
        voiceNoteCleanupStatus: "deleted",
        voiceNoteCleanedAt: FieldValue.serverTimestamp(),
      };
      if (batch) batch.set(doc.ref, patch, {merge: true});
      else await doc.ref.set(patch, {merge: true});
    }
  }
  return {deletedMedia: deleted.length, storagePaths: deleted};
}

const cleanupExpiredGiftVoiceDrafts = functions.pubsub.schedule("every 24 hours").onRun(async () => cleanupExpiredGiftVoiceDraftsCore());
const onGiftRequestVoiceMediaDeleted = functions.firestore
    .document("giftRequests/{giftRequestId}")
    .onDelete(async (snapshot, context) => {
      const gift = snapshot.data() || {};
      const path = text(gift.voiceNote && gift.voiceNote.storagePath);
      if (!path) return null;
      await deleteGiftVoiceStoragePath({
        bucket: getStorage().bucket(),
        db: getFirestore(),
        storagePath: path,
        actorUid: "system",
        giftRequestId: context.params.giftRequestId,
        reason: "gift_request_deleted",
      });
      return null;
    });

module.exports = {
  ABANDONED_DRAFT_HOURS,
  GIFT_VOICE_MAX_BYTES,
  GIFT_VOICE_MAX_DURATION_SECONDS,
  cleanupExpiredGiftVoiceDrafts,
  cleanupExpiredGiftVoiceDraftsCore,
  cleanupGiftVoiceMediaForAccount,
  deleteGiftVoiceStoragePath,
  giftVoiceLifecycleAudit,
  onGiftRequestVoiceMediaDeleted,
  parseGiftVoiceStoragePath,
  sanitizeGiftVoiceNoteMetadata,
  verifyGiftVoiceStorageObject,
};
