/* eslint-disable max-len, require-jsdoc */
"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore, Timestamp} = require("firebase-admin/firestore");
const {runLegacyWorker, expiredDrafts, membershipCompletion} = require("./legacy-scheduled-recovery");
const {processTick} = require("./legacy-recovery-http");
const {processNoShowSettlement} = require("./legacy-no-show-settlement");
async function fixture(name, run) {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST);
  const app = initializeApp({projectId: `demo-legacy-recovery-${name}`}, name);
  try {
await run(getFirestore(app));
} finally {
await deleteApp(app);
}
}
test("draft refresh between query and commit preserves the renewed draft", () => fixture("draft", async (db) => {
  const now = Date.now(); const ref = db.doc("senderBookingDrafts/draft");
  await ref.set({status: "draft", expiresAt: Timestamp.fromMillis(now - 1)});
  const raced = {collection: db.collection.bind(db), runTransaction: async (run) => {
    await ref.update({expiresAt: Timestamp.fromMillis(now + 60000)}); return db.runTransaction(run);
  }};
  assert.equal((await expiredDrafts({db: raced, now, limit: 20})).deleted, 0);
  assert.ok((await ref.get()).exists);
}));
test("completed membership authority is observed without regranting permissions", () => fixture("membership", async (db) => {
  await db.doc("systemMigrationState/business_memberships_v2").set({status: "completed"});
  assert.deepEqual(await membershipCompletion({db}), {alreadyCompleted: true, membershipsChanged: 0});
  assert.equal((await db.collection("businessMemberships").get()).size, 0);
  await db.doc("systemMigrationState/business_memberships_v2").update({status: "running"});
  await assert.rejects(membershipCompletion({db}), /requires_review/);
}));
test("scheduler retry/coalescing budgets never acknowledge a failed scan", () => fixture("receipt", async (db) => {
  const worker = "reconcileStaleDeliveryLocks"; const now = Date.now(); const tick = {messageId: "1", publishTime: new Date(now - 604000000).toISOString(), ageSeconds: 604000};
  await db.doc(`deliveryWorkerControl/${worker}`).set({enabled: true, maxAcknowledgements: 2});
  await assert.rejects(processTick({db, worker, tick, now, run: async () => {
throw new Error("crash");
}}), /crash/);
  assert.equal((await db.collection("deliveryWorkerReceipts").get()).size, 0);
  let scans = 0; const run = async () => {
scans++; return {safe: true};
};
  await processTick({db, worker, tick, now, run}); await processTick({db, worker, tick, now, run});
  await processTick({db, worker, tick: {...tick, messageId: "2"}, now, run});
  assert.equal(scans, 1); assert.equal((await db.doc(`deliveryWorkerControl/${worker}`).get()).data().acknowledged, 2);
  await assert.rejects(processTick({db, worker, tick: {...tick, messageId: "3"}, now, run}), /bounded_cutover_paused/);
}));
test("concurrent no-show retries deduct the existing paid amount once and call no provider writes", () => fixture("noshow", async (db) => {
  await db.doc("deliveryRequests/job").set({status: "sender_no_show_pickup", riderId: "rider", senderId: "sender", paymentSessionId: "session", paymentStatus: "paid", paidAmount: 7, remainingAmount: 0, rothAppliedAmount: 7});
  await db.doc("senderPaymentSessions/session").set({userId: "sender", rothAppliedAmount: 7, rothDebitStatus: "completed", rothDebitTransactionId: "debit"});
  await db.doc("walletTransactions/debit").set({status: "completed", uid: "sender", balanceType: "rothCredit", referenceId: "session", relatedEntityId: "job", amount: -7});
  await db.doc("noShowSettlements/job").set({state: "SETTLEMENT_PENDING", riderId: "rider"});
  const stripe = new Proxy({}, {get: () => {
throw new Error("Provider access forbidden");
}});
  await Promise.all(Array.from({length: 4}, () => processNoShowSettlement({db, stripe, deliveryId: "job"})));
  assert.equal((await db.doc("riderEarnings/rider").get()).data().availableBalance, 4);
  assert.equal((await db.collection("riderEarningTransactions").get()).size, 1);
  assert.equal((await db.collection("platformSettlementTransactions").get()).size, 1);
  assert.equal((await db.doc("noShowSettlements/job").get()).data().additionalCustomerCharge, 0);
}));
test("no-show retries cannot overwrite changed financial or Rider authority", () => fixture("noshow-race", async (db) => {
  const ref = db.doc("deliveryRequests/job");
  await ref.set({status: "sender_no_show_pickup", riderId: "rider", senderId: "sender", paymentSessionId: "session", paymentStatus: "paid", paidAmount: 7, remainingAmount: 0, rothAppliedAmount: 7});
  await db.doc("senderPaymentSessions/session").set({userId: "sender", rothAppliedAmount: 7, rothDebitStatus: "completed", rothDebitTransactionId: "debit"});
  await db.doc("walletTransactions/debit").set({status: "completed", uid: "sender", balanceType: "rothCredit", referenceId: "session", relatedEntityId: "job", amount: -7}); await db.doc("noShowSettlements/job").set({state: "SETTLEMENT_PENDING", riderId: "rider"});
  const raced = {collection: db.collection.bind(db), runTransaction: async (run) => {
await ref.update({refundPending: true}); return db.runTransaction(run);
}};
  await assert.rejects(processNoShowSettlement({db: raced, stripe: {}, deliveryId: "job"}), /authority_changed/);
  assert.equal((await db.collection("riderEarningTransactions").get()).size, 0);
}));
test("renewed Gift Story token and current video survive expired-token cleanup", () => fixture("gift-renewal", async (db) => {
  const now = Date.now(); await db.doc("giftStoryAccessTokens/old").set({giftRequestId: "gift", expiresAt: Timestamp.fromMillis(now - 1)});
  await db.doc("giftRequests/gift").set({giftStoryAccessTokenHash: "new", giftStoryVideoExpiresAt: Timestamp.fromMillis(now + 60000), giftStoryRenderedVideoPath: "gifts/gift/story/exports/sound/new.webm", giftStoryVideoStatus: "ready"});
  const bucket = {file: () => {
throw new Error("Current media cannot be touched");
}};
  assert.equal((await runLegacyWorker({db, worker: "cleanupExpiredGiftStories", bucket, now, limit: 20})).mediaExpired, 0);
  assert.equal((await db.doc("giftRequests/gift").get()).data().giftStoryVideoStatus, "ready");
}));
test("Gift voice cleanup preserves active reservations and never calls Stripe", () => fixture("voice-reservation", async (db) => {
  const now = Date.now(); await db.doc("giftPaymentDrafts/draft").set({createdAt: Timestamp.fromMillis(now - 2 * 86400000), paymentStatus: "checkout_pending", giftCheckoutProtocol: 1, giftCheckoutReservationId: "reservation", voiceNote: {storagePath: "gift_requests/sender_1/voice/original.webm"}});
  const bucket = {file: () => {
throw new Error("Reserved media cannot be touched");
}};
  assert.equal((await runLegacyWorker({db, worker: "cleanupExpiredGiftVoiceDrafts", bucket, now, limit: 20})).reviewRequired, 1);
  assert.ok((await db.doc("giftPaymentDrafts/draft").get()).data().voiceNote);
}));
test("a paused Health+ schedule cannot be revived by a stale scan", () => fixture("health-pause", async (db) => {
  const now = Date.now(); const ref = db.doc("recurringPickupSchedules/schedule");
  await ref.set({status: "active", paused: false, nextPickupAt: Timestamp.fromMillis(now + 60000), frequency: "weekly"});
  const raced = {collection: db.collection.bind(db), runTransaction: async (run) => {
await ref.update({paused: true}); return db.runTransaction(run);
}};
  await runLegacyWorker({db: raced, worker: "generateHealthPlusRecurringBookings", now, limit: 20});
  assert.equal((await db.collection("prescriptionPickups").get()).size, 0);
}));
