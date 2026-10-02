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

test("retired Story media cannot be resurrected by a concurrent finalization", () => fixture("story-retired", async (db) => {
  const {cleanupRef, finalizeStory} = require("./gift-media-cleanup-authority");
  const path = "gifts/gift/story/exports/sound/old.webm";
  await db.doc("giftRequests/gift").set({senderId: "sender", giftStoryVideoStatus: "expired"});
  await cleanupRef(db, "story", path).set({path, state: "pending"});
  await assert.rejects(finalizeStory({db, giftId: "gift", path, mime: "video/webm", expiresAt: Timestamp.fromMillis(Date.now() + 60000), authorize: async () => true}), /expired/);
  assert.equal((await db.doc("giftRequests/gift").get()).data().giftStoryVideoStatus, "expired");
}));
test("a retired voice path is rejected before any checkout reservation or provider call", () => fixture("voice-retired", async (db) => {
  const {cleanupRef} = require("./gift-media-cleanup-authority"); const {reserve} = require("./gift-checkout-reservations");
  const path = "gift_requests/sender_1/voice/original.webm";
  const ref = db.doc("giftPaymentDrafts/draft");
  await ref.set({senderId: "sender", giftCheckoutProtocol: 1, grossBudget: 50, paymentStatus: "payment_pending", voiceNote: {storagePath: path}});
  await db.doc("giftCheckoutOrigins/draft").set({senderId: "sender"}); await cleanupRef(db, "voice", path).set({path, state: "pending"});
  await assert.rejects(reserve({db, giftRef: ref, uid: "sender", split: {walletContributionGbp: 0, remainingGbp: 50}, nativePayment: true}), /expired/);
  assert.equal((await db.collection("giftCheckoutReservations").get()).size, 0);
}));
test("reconciliation writes one audit receipt from an atomic ledger snapshot and changes no balances", () => fixture("earnings-audit", async (db) => {
  await db.doc("riderEarnings/rider").set({availableBalance: 4});
  await db.doc("riderEarningTransactions/earning").set({riderId: "rider", type: "delivery_earning", amount: 4, idempotencyKey: "earning"});
  const args = {db, worker: "scheduledRiderEarningsReconciliation", now: Date.now(), limit: 20};
  await runLegacyWorker(args); await runLegacyWorker(args);
  assert.equal((await db.collection("riderEarningsReconciliations").get()).size, 1);
  const row = (await db.doc("riderEarnings/rider").get()).data(); assert.equal(row.availableBalance, 4); assert.equal(row.reconciliationRequired, false);
  assert.equal((await db.collection("riderEarningTransactions").get()).size, 1);
}));

test("an existing cancellation settlement blocks no-show allocation even without a deliveryId field", () => fixture("noshow-cancellation", async (db) => {
  await db.doc("deliveryRequests/job").set({status: "sender_no_show_pickup", riderId: "rider", senderId: "sender", paymentSessionId: "session", paymentStatus: "paid", paidAmount: 7, remainingAmount: 0, rothAppliedAmount: 7});
  await db.doc("senderPaymentSessions/session").set({userId: "sender", rothAppliedAmount: 7, rothDebitStatus: "completed", rothDebitTransactionId: "debit"});
  await db.doc("walletTransactions/debit").set({status: "completed", uid: "sender", balanceType: "rothCredit", referenceId: "session", relatedEntityId: "job", amount: -7});
  await db.doc("noShowSettlements/job").set({state: "SETTLEMENT_PENDING", riderId: "rider"});
  await db.doc("deliveryCancellationSettlements/job").set({state: "pending_refund"});
  await assert.rejects(processNoShowSettlement({db, stripe: {}, deliveryId: "job"}), /other_settlement_authority/);
  assert.equal((await db.collection("riderEarningTransactions").get()).size, 0);
  assert.equal((await db.collection("platformSettlementTransactions").get()).size, 0);
}));
test("private QA expiry certification reads only the selected fixture and retries actual cleanup safely", () => fixture("qa-expiry", async (db) => {
  const {fixtureCollection} = require("./qa-expiry-recovery-http");
  const root = db.collection("qaLifecycleFixtures"); const id = "a".repeat(64); const other = "b".repeat(64);
  const data = {id, isSyntheticQa: true, testOnly: true, qaCreatedBy: "operator", senderId: "sender", riderId: "rider", expiresAt: Timestamp.fromMillis(1), cleanupDueAt: Timestamp.fromMillis(1), archived: false};
  await root.doc(id).set(data); await root.doc(other).set({...data, id: other});
  const scoped = {collection: (name) => name === "qaLifecycleFixtures" ? fixtureCollection(root, id) : db.collection(name), doc: db.doc.bind(db), batch: db.batch.bind(db), runTransaction: db.runTransaction.bind(db)};
  const env = {GCLOUD_PROJECT: "circum-2797c", STRIPE_MODE: "TEST", QA_LIFECYCLE_ENABLED: "true", QA_LIFECYCLE_ALLOWLIST: JSON.stringify({operators: ["operator"], senders: ["sender"], riders: ["rider"]})};
  let providerCleanup = 0;
  const owner = require("./qa-lifecycle")._test.factory({db: scoped, env, providerFactory: () => ({cleanup: async () => {
providerCleanup++;
}})});
  assert.deepEqual(await owner.expire(), {archived: 1}); assert.deepEqual(await owner.expire(), {archived: 0});
  assert.equal((await root.doc(id).get()).data().archived, true); assert.equal((await root.doc(other).get()).data().archived, false); assert.equal(providerCleanup, 1);
  assert.throws(() => fixtureCollection(root, id).doc(other), /cross_fixture_access/);
  await assert.rejects(fixtureCollection(root, id).where("unexpected", "==", true).get(), /unsupported_fixture_query/);
}));
