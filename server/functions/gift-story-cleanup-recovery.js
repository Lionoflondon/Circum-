/* eslint-disable max-len, require-jsdoc */
"use strict";
const {cleanupRef} = require("./gift-media-cleanup-authority");
const {FieldValue, Timestamp} = require("firebase-admin/firestore");
const millis = (v) => typeof v?.toMillis === "function" ? v.toMillis() : 0;
async function cleanupGiftStories({db, bucket, now = Date.now(), limit = 20}) {
  const snapshot = await db.collection("giftStoryAccessTokens").where("expiresAt", "<=", Timestamp.fromMillis(now)).limit(limit).get();
  const result = {scanned: snapshot.size, tokensExpired: 0, mediaExpired: 0, mediaDeleted: 0};
  for (const doc of snapshot.docs) {
    const outcome = await db.runTransaction(async (tx) => {
      const token = await tx.get(doc.ref); const record = token.data() || {};
      if (!token.exists || !millis(record.expiresAt) || millis(record.expiresAt) > now) return {expired: false};
      const giftId = String(record.giftRequestId || "");
      if (!giftId || giftId.includes("/")) throw new Error("invalid_gift_cleanup_authority");
      const giftRef = db.collection("giftRequests").doc(giftId); const giftSnap = await tx.get(giftRef); const gift = giftSnap.data() || {};
      const currentHash = gift.giftStoryAccessTokenHash || gift.recipientStoryTokenHash;
      const expireMedia = giftSnap.exists && (!currentHash || currentHash === doc.id) && millis(gift.giftStoryVideoExpiresAt) > 0 && millis(gift.giftStoryVideoExpiresAt) <= now;
      if (expireMedia) {
        const paths = [gift.giftStoryRenderedVideoPath, gift.giftStorySilentVersionUrl, gift.giftStorySoundVersionUrl].filter((p) => typeof p === "string" && p.startsWith(`gifts/${giftId}/story/exports/`));
        for (const path of new Set(paths)) {
          tx.set(cleanupRef(db, "story", path), {path, giftId, tokenId: doc.id, state: "pending", createdAt: FieldValue.serverTimestamp()}, {merge: true});
        }
        tx.set(giftRef, {giftStoryRenderedVideoPath: FieldValue.delete(), giftStorySilentVersionUrl: FieldValue.delete(), giftStorySoundVersionUrl: FieldValue.delete(),
          giftStoryAccessToken: FieldValue.delete(), giftStoryAccessTokenHash: FieldValue.delete(), recipientStoryToken: FieldValue.delete(), recipientStoryTokenHash: FieldValue.delete(), recipientStoryUrl: FieldValue.delete(),
          giftStoryAccessStatus: "expired", giftStoryVideoStatus: "expired", giftStoryUpdatedAt: FieldValue.serverTimestamp()}, {merge: true});
      }
      tx.delete(doc.ref); return {expired: true, expireMedia};
    });
    if (outcome.expired) result.tokensExpired++;
    if (outcome.expireMedia) result.mediaExpired++;
  }
  const jobs = await db.collection("giftStoryCleanupJobs").where("state", "==", "pending").limit(limit).get();
  for (const job of jobs.docs) {
    const {path, giftId} = job.data();
    const latest = (await db.collection("giftRequests").doc(giftId).get()).data() || {};
    // Never erase a current replacement referenced by a renewed Gift Story.
    const renewed = millis(latest.giftStoryVideoExpiresAt) > now && [latest.giftStoryRenderedVideoPath, latest.giftStorySilentVersionUrl, latest.giftStorySoundVersionUrl].includes(path);
    if (!renewed) await bucket.file(path).delete({ignoreNotFound: true});
    await job.ref.set({state: renewed ? "preserved_replacement" : "completed", completedAt: FieldValue.serverTimestamp()}, {merge: true});
    if (!renewed) result.mediaDeleted++;
  }
  return result;
}
module.exports = {cleanupGiftStories};
