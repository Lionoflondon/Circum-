"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const {scanGiftRecoveryPage} = require("./gift-email-reconciliation");

test("indexed Gift recovery scans page synthetic paid Gifts and completed deliveries without writes", async () => {
  assert(process.env.FIRESTORE_EMULATOR_HOST, "Emulator only");
  const app = initializeApp({projectId: "demo-gift-email-recovery-scan"}, "gift-email-recovery-scan");
  const db = getFirestore(app);
  try {
    await Promise.all([
      db.doc("giftRequests/paid-a").set({paymentStatus: "paid", walletContributionGbp: 10,
        senderEmail: "sender@example.test", status: "approved", deliveryId: "delivery-a"}),
      db.doc("giftRequests/pending-b").set({paymentStatus: "pending", walletContributionGbp: 0}),
      db.doc("deliveryRequests/delivery-a").set({status: "completed", serviceType: "gifts",
        giftRequestId: "paid-a"}),
    ]);
    const paid = await scanGiftRecoveryPage({db, kind: "paid", limit: 1});
    assert.equal(paid.examined, 1);
    assert.deepEqual(paid.candidates.map((item) => item.giftId), ["paid-a"]);
    const completed = await scanGiftRecoveryPage({db, kind: "deliveries", limit: 1});
    assert.deepEqual(completed.candidates.map((item) => item.deliveryId), ["delivery-a"]);
    assert.equal((await db.collection("emailQueue").get()).empty, true);
  } finally {
    await deleteApp(app);
  }
});
