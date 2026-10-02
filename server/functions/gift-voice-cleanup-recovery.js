/* eslint-disable max-len, require-jsdoc */
"use strict";
const {createHash} = require("node:crypto");
const {FieldValue, Timestamp} = require("firebase-admin/firestore");
const {parseGiftVoiceStoragePath} = require("./gift-voice-media");
async function cleanupVoice({db, bucket, now = Date.now(), limit = 20}) {
  const candidates = await db.collection("giftPaymentDrafts").where("createdAt", "<=", Timestamp.fromMillis(now - 86400000)).where("paymentStatus", "in", ["payment_pending", "checkout_pending"]).limit(limit).get();
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
      const jobId = createHash("sha256").update(`${doc.id}:${path}`).digest("hex");
      tx.set(db.collection("giftVoiceCleanupJobs").doc(jobId), {path, giftDraftId: doc.id, state: "pending", createdAt: FieldValue.serverTimestamp()}, {merge: true});
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
  return result;
}
module.exports = {cleanupVoice};
