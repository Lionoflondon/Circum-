/* eslint-disable max-len, require-jsdoc */
"use strict";
const functions = require("firebase-functions/v1");
const {createHash} = require("node:crypto");
const {FieldValue} = require("firebase-admin/firestore");
const pathId = (path) => createHash("sha256").update(path).digest("hex");
function cleanupRef(db, kind, path) {
  return db.collection(kind === "story" ? "giftStoryCleanupJobs" : "giftVoiceCleanupJobs").doc(pathId(path));
}
async function assertNotRetired(tx, db, kind, path) {
  if (!path) return;
  const retired = await tx.get(cleanupRef(db, kind, path));
  if (retired.exists) throw new functions.https.HttpsError("failed-precondition", "Gift media has expired. Upload a new file.");
}
async function finalizeStory({db, giftId, path, mime, expiresAt, authorize}) {
  const ref = db.collection("giftRequests").doc(giftId);
  return db.runTransaction(async (tx) => {
    const current = await tx.get(ref);
    if (!current.exists) throw new functions.https.HttpsError("not-found", "Gift Story not found.");
    const gift = {...current.data(), id: giftId};
    await assertNotRetired(tx, db, "story", path);
    if (!await authorize(gift)) throw new functions.https.HttpsError("permission-denied", "Gift Story access required.");
    const previous = gift.giftStoryRenderedVideoPath;
    if (previous && previous !== path) tx.set(cleanupRef(db, "story", previous), {path: previous, giftId, state: "pending", reason: "superseded", createdAt: FieldValue.serverTimestamp()}, {merge: true});
    tx.set(ref, {giftStoryRenderedVideoPath: path,
      ...(path.includes("/exports/silent/") ? {giftStorySilentVersionUrl: path} : {giftStorySoundVersionUrl: path}),
      giftStoryVideoMime: mime, giftStoryVideoStatus: "ready", giftStoryVideoRenderedAt: FieldValue.serverTimestamp(),
      giftStoryVideoExpiresAt: expiresAt, giftStoryUpdatedAt: FieldValue.serverTimestamp()}, {merge: true});
    return {ok: true, expiresAt: expiresAt.toMillis()};
  });
}
module.exports = {cleanupRef, assertNotRetired, finalizeStory};
