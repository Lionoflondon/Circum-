/* eslint-disable no-console, max-len */
"use strict";

const {initializeApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const movement = require("../movement-ledger");

initializeApp();

/**
 * Projects source records into deterministic movement documents.
 * @param {FirebaseFirestore.QuerySnapshot} snapshot Source records.
 * @param {Function} projector Movement projection function.
 * @param {string} idField Deterministic delivery ID prefix.
 * @return {Promise<{linked: number, skipped: number}>} Backfill totals.
 */
async function backfillCollection(snapshot, projector, idField) {
  let linked = 0;
  let skipped = 0;
  for (const doc of snapshot.docs) {
    const data = doc.data() || {};
    const expectedId = `${idField}_${doc.id}`;
    if (data.deliveryId === expectedId) {
      skipped++;
      continue;
    }
    await projector(doc.id, data);
    linked++;
  }
  return {linked, skipped};
}

/** Runs the idempotent Gifts and Health+ movement backfill. */
async function main() {
  const db = getFirestore();
  const [gifts, health] = await Promise.all([
    db.collection("giftRequests").get(),
    db.collection("prescriptionPickups").get(),
  ]);
  const giftResult = await backfillCollection(
      gifts,
      (id, data) => movement.projectGift(db, id, data),
      "gift",
  );
  const healthResult = await backfillCollection(
      health,
      (id, data) => movement.projectHealth(db, id, data),
      "health",
  );
  console.log(JSON.stringify({gifts: giftResult, healthPlus: healthResult}, null, 2));
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
