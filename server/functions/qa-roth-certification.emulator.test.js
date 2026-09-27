/* eslint-disable max-len, require-jsdoc */
"use strict";
const {test, before, after, mock} = require("node:test");
const assert = require("node:assert/strict");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore, Timestamp} = require("firebase-admin/firestore");
const {getAuth} = require("firebase-admin/auth");
const {scopedDatabase} = require("./qa-lifecycle")._test;
const qaRoth = require("./qa-roth-certification");
const qaSpecial = require("./qa-special-flow")._test;

let app; let db;
before(() => {
  assert(process.env.FIRESTORE_EMULATOR_HOST, "Emulator only");
  app = initializeApp({projectId: "demo-qa-roth"});
  db = getFirestore();
  mock.method(getAuth(), "getUserByEmail", async (email) => ({uid: "qa_sender", email}));
});
after(async () => {
  mock.restoreAll(); await deleteApp(app);
});

test("QA Roth-only and TEST split use canonical ledger and finalization once inside the fixture", async () => {
  const fixture = {id: "qa_roth_fixture", isSyntheticQa: true, qaCreatedBy: "qa_operator", qaCreatedAt: Timestamp.now(), senderId: "qa_sender", riderId: "qa_rider", expiresAt: Timestamp.fromMillis(Date.now() + 3600000), archived: false};
  await db.collection("qaSpecialFlowFixtures").doc(fixture.id).create(fixture);
  const collections = ["wallets", "senderWallets", "walletTransactions", "giftPaymentDrafts", "giftCheckoutOrigins", "giftCheckoutReservations", "giftRequests", "giftPaymentEvents", "giftRecurringSeries", "giftRecurringRenewals", "deliveryRequests"];
  const qa = scopedDatabase(db, fixture, false, "qaSpecialFlowFixtures", collections);
  const email = "qa-sender@example.invalid";
  const uid = fixture.senderId;
  const intents = new Map();
  const stripe = {paymentIntents: {create: async (input, options) => {
    assert.equal(input.amount, 4300);
    assert.equal(input.metadata.qaFixtureId, fixture.id);
    assert.equal(input.metadata.isSyntheticQa, "true");
    if (!intents.has(options.idempotencyKey)) intents.set(options.idempotencyKey, {id: `pi_test_${intents.size + 1}`, livemode: false, status: "succeeded", amount: input.amount, amount_received: input.amount, currency: input.currency, metadata: input.metadata});
    return intents.get(options.idempotencyKey);
  }}};
  const args = {qa, fixture, uid, email, stripe};
  assert.deepEqual(await qaRoth.seed(args), {balance: 57, idempotent: false});
  assert.deepEqual(await qaRoth.seed(args), {balance: 57, idempotent: true});
  const only = await qaRoth.pay({...args, type: "roth_only"});
  assert.equal(only.rothApplied, 50); assert.equal(only.cardAmount, 0);
  assert.equal((await qaRoth.pay({...args, type: "roth_only"})).idempotent, true);
  const split = await qaRoth.pay({...args, type: "split"});
  assert.equal(split.rothApplied, 7); assert.equal(split.cardAmount, 43);
  assert.equal((await qaRoth.pay({...args, type: "split"})).idempotent, true);
  assert.equal(intents.size, 1);
  assert.equal((await qaRoth.insufficient(args)).balanceUnchanged, true);
  const read = await qaRoth.read(args);
  assert.equal(read.balance, 0); assert.equal(read.completedDebits, 2); assert.equal(read.giftCount, 2);
  const first = await qaRoth.reconcile(args); const second = await qaRoth.reconcile(args);
  assert.equal(first.errors, 0); assert.equal(second.effective, 0); assert.equal(second.errors, 0);
  assert.equal((await db.collection("wallets").get()).size, 0);
  assert.equal((await db.collection("walletTransactions").get()).size, 0);
  assert.equal((await db.collection("giftRequests").get()).size, 0);
});

test("private Roth action requires allowlisted QA Sender Auth and App Check", async () => {
  const fixture = {id: "a".repeat(64), isSyntheticQa: true, qaCreatedBy: "qa_operator", qaCreatedAt: Timestamp.now(), senderId: "qa_sender", riderId: "qa_rider", expiresAt: Timestamp.fromMillis(Date.now() + 3600000), archived: false};
  await db.collection("qaSpecialFlowFixtures").doc(fixture.id).create(fixture);
  const env = {GCLOUD_PROJECT: "circum-2797c", STRIPE_MODE: "TEST", CIRCUM_QA_STRIPE_SECRET_KEY: "sk_test_fixture", QA_LIFECYCLE_ENABLED: "true", QA_LIFECYCLE_ALLOWLIST: JSON.stringify({operators: ["qa_operator"], senders: ["qa_sender"], riders: ["qa_rider"]})};
  const f = qaSpecial.factory({db, env, stripe: {}});
  const request = {action: "roth", scenario: "prepare", fixtureId: fixture.id, balance: 999999, transactionStatus: "completed"};
  const context = {auth: {uid: "qa_sender", token: {email: "qa-sender@example.invalid"}}, app: {appId: "qa-app"}};
  await assert.rejects(f.handle(request, {...context, app: undefined}), /attestation/);
  await assert.rejects(f.handle(request, {...context, auth: {uid: "ordinary", token: {email: "ordinary@example.invalid"}}}), /not permitted/);
  await assert.rejects(f.handle(request, {...context, auth: {uid: "qa_operator", token: {email: "qa-operator@example.invalid"}}}), /QA Sender required/);
  assert.equal((await f.handle(request, context)).balance, 57);
  assert.equal((await f.handle({action: "roth", scenario: "read", fixtureId: fixture.id}, context)).balance, 57);
  assert.equal((await db.doc(`qaSpecialFlowFixtures/${fixture.id}/wallets/qa-sender@example.invalid`).get()).data().balance, 57);
});
