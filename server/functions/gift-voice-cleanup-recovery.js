/* eslint-disable max-len, require-jsdoc */
"use strict";
const {createHash} = require("node:crypto");
const {FieldValue, Timestamp, FieldPath} = require("firebase-admin/firestore");
const {cleanupRef} = require("./gift-media-cleanup-authority");
const {parseGiftVoiceStoragePath} = require("./gift-voice-media");
async function cleanupVoice({db, bucket, now = Date.now(), limit = 20}) {
  const scanRef = db.collection("giftVoiceCleanupScans").doc("current");
  const cursor = (await scanRef.get()).data() || {};
  let query = db.collection("giftPaymentDrafts").where("createdAt", "<=", Timestamp.fromMillis(now - 86400000)).where("paymentStatus", "in", ["payment_pending", "checkout_pending"])
      .orderBy("createdAt").orderBy(FieldPath.documentId());
  if (cursor.lastCreatedAt?.toMillis && typeof cursor.lastDraftId === "string" && cursor.lastDraftId && !cursor.lastDraftId.includes("/")) query = query.startAfter(cursor.lastCreatedAt, cursor.lastDraftId);
  const candidates = await query.limit(limit).get();
  const result = {scanned: candidates.size, detached: 0, deleted: 0, reviewRequired: 0};
  for (const doc of candidates.docs) {
    const status = await db.runTransaction(async (tx) => {
      const current = await tx.get(doc.ref); const draft = current.data() || {};
      const reservationId = `gift_${createHash("sha256").update(doc.id).digest("hex")}_1`;
      const reservation = await tx.get(db.collection("giftCheckoutReservations").doc(reservationId));
      const path = draft.voiceNote?.storagePath;
      if (!current.exists || !["payment_pending", "checkout_pending"].includes(draft.paymentStatus) || !draft.createdAt?.toMillis || draft.createdAt.toMillis() > now - 86400000 || !parseGiftVoiceStoragePath(path)) return "skipped";
      // Only the current reservation protocol proves that no hidden provider
      // object exists. Never erase media from a live/legacy checkout.
      if (draft.giftCheckoutProtocol !== 1 || reservation.exists || draft.giftCheckoutReservationId || draft.stripePaymentIntentId || draft.stripeCheckoutSessionId) return "review";
      const otherDrafts = await tx.get(db.collection("giftPaymentDrafts").where("voiceNote.storagePath", "==", path).limit(2));
      if (otherDrafts.docs.some((other) => other.id !== doc.id)) return "review";
      tx.set(cleanupRef(db, "voice", path), {path, giftDraftId: doc.id, state: "pending", createdAt: FieldValue.serverTimestamp()}, {merge: true});
      tx.set(doc.ref, {voiceNote: FieldValue.delete(), voiceNoteCleanupStatus: "pending_delete", updatedAt: FieldValue.serverTimestamp()}, {merge: true});
      return "detached";
    });
    if (status === "detached") result.detached++; if (status === "review") result.reviewRequired++;
  }
  const jobs = await db.collection("giftVoiceCleanupJobs").where("state", "==", "pending").limit(limit).get();
  for (const job of jobs.docs) {
    const data = job.data();
    const draft = (await db.collection("giftPaymentDrafts").doc(data.giftDraftId).get()).data() || {};
    const linked = await db.collection("giftRequests").where("voiceNote.storagePath", "==", data.path).limit(1).get();
    if (draft.voiceNote?.storagePath === data.path || !linked.empty) {
      await job.ref.set({state: "preserved_replacement"}, {merge: true}); continue;
    }
    await bucket.file(data.path).delete({ignoreNotFound: true});
    await job.ref.set({state: "completed", completedAt: FieldValue.serverTimestamp()}, {merge: true}); result.deleted++;
  }
  // Reviewed legacy/reserved drafts remain untouched, but cannot permanently
  // occupy the first page. Advance only after every retirement job succeeds;
  // a crash before this point repeats the same idempotent page.
  const last = candidates.docs[candidates.size - 1];
  await scanRef.set(candidates.size === limit && last ? {
    lastCreatedAt: last.data().createdAt, lastDraftId: last.id, updatedAt: FieldValue.serverTimestamp(),
  } : {lastCreatedAt: null, lastDraftId: null, updatedAt: FieldValue.serverTimestamp()});
  return result;
}
module.exports = {cleanupVoice};
