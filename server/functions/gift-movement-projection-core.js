/* eslint-disable max-len */
"use strict";

const {createHash} = require("node:crypto");
const {FieldValue} = require("firebase-admin/firestore");
const {giftMovement, riderGiftStoryVoiceRedaction} = require("./movement-ledger");

async function projectLatestGiftMovement(db, giftId) {
  const giftRef = db.collection("giftRequests").doc(giftId);
  const deliveryId = `gift_${giftId}`;
  const deliveryRef = db.collection("deliveryRequests").doc(deliveryId);
  return db.runTransaction(async (tx) => {
    const gift = await tx.get(giftRef);
    if (!gift.exists) return {status: "source_deleted"};
    const delivery = await tx.get(deliveryRef);
    const data = gift.data() || {};
    const sourceVersion = gift.updateTime;
    const claimId = createHash("sha256")
        .update(`${giftId}:${sourceVersion.seconds}:${sourceVersion.nanoseconds}`)
        .digest("hex");
    const claimRef = db.collection("giftMovementProjectionClaims").doc(claimId);
    const claim = await tx.get(claimRef);
    const projectedVersion = delivery.exists && (delivery.data() || {}).giftMovementSourceVersion;
    if (claim.exists) {
      return {status: projectedVersion && projectedVersion.isEqual(sourceVersion) ?
        "already_projected" : "manual_review_claim_target_mismatch"};
    }
    if (projectedVersion && projectedVersion.isEqual(sourceVersion)) return {status: "already_projected"};
    const movement = Object.fromEntries(Object.entries(giftMovement(giftId, data))
        .filter(([, value]) => value !== undefined));
    tx.set(deliveryRef, {
      ...movement,
      ...riderGiftStoryVoiceRedaction(),
      giftMovementSourceVersion: sourceVersion,
    }, {merge: true});
    tx.create(claimRef, {
      status: "completed", sourceVersion,
      completedAt: FieldValue.serverTimestamp(),
    });
    if (data.deliveryId !== deliveryId || data.serviceType !== "GIFTS" || data.sourceModule !== "gifts") {
      tx.set(giftRef, {
        deliveryId, serviceType: "GIFTS", sourceModule: "gifts",
        movementLinkedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    }
    return {status: "projected"};
  });
}

module.exports = {projectLatestGiftMovement};
