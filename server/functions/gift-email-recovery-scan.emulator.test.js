"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const {scanGiftRecoveryPage} = require("./gift-email-reconciliation");

test("indexed forward Gift recovery scans post-policy paid and delivered Gifts without writes", async () => {
  assert(process.env.FIRESTORE_EMULATOR_HOST, "Emulator only");
  const app = initializeApp({projectId: "demo-gift-email-recovery-scan"}, "gift-email-recovery-scan");
  const db = getFirestore(app);
  const policyEffectiveAt = "2026-09-26T14:30:00.000Z";
  const eventAt = "2026-09-26T14:31:00.000Z";
  const nowMs = Date.parse("2026-09-26T14:40:00.000Z");
  try {
    await Promise.all([
      db.doc("giftRequests/paid-a").set({paymentStatus: "paid", walletContributionGbp: 10,
        senderEmail: "sender@example.test", status: "approved", paidAt: eventAt,
        updatedAt: "2026-09-26T14:39:00.000Z"}),
      db.doc("giftRequests/old-a").set({paymentStatus: "paid", walletContributionGbp: 10,
        senderEmail: "old@example.test", status: "approved", paidAt: "2026-09-26T14:00:00.000Z",
        updatedAt: "2026-09-26T14:39:00.000Z"}),
      db.doc("giftRequests/delivered-a").set({status: "delivered", senderEmail: "sender@example.test",
        deliveredAt: eventAt, updatedAt: "2026-09-26T14:39:00.000Z"}),
      db.doc("walletTransactions/gift_roth_paid-a").set({status: "completed", amount: -10,
        referenceId: "paid-a"}),
    ]);
    const paid = await scanGiftRecoveryPage({db, kind: "paid", limit: 1, policyEffectiveAt, nowMs});
    assert.equal(paid.examined, 1);
    assert.deepEqual(paid.candidates.map((item) => item.giftId), ["paid-a"]);
    const delivered = await scanGiftRecoveryPage({db, kind: "deliveries", limit: 1, policyEffectiveAt, nowMs});
    assert.deepEqual(delivered.candidates.map((item) => item.giftId), ["delivered-a"]);
    assert.equal((await db.collection("emailQueue").get()).empty, true);
  } finally {
    await deleteApp(app);
  }
});
