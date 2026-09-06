/* eslint-disable max-len, require-jsdoc */
"use strict";
const {test, before, after} = require("node:test");
const assert = require("node:assert/strict");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore, Timestamp} = require("firebase-admin/firestore");
const {factory, scopedDatabase} = require("./qa-lifecycle")._test;
let app; let db; let service;
const env = {GCLOUD_PROJECT: "circum-2797c", STRIPE_MODE: "TEST", QA_LIFECYCLE_ENABLED: "true", QA_LIFECYCLE_ALLOWLIST: JSON.stringify({operators: ["operator"], senders: ["sender"], riders: ["rider"]})};
const context = (uid) => ({auth: {uid}, app: {appId: "emulator"}});
before(() => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST);
  app = initializeApp({projectId: "demo-qa-lifecycle"}); db = getFirestore(app); service = factory({db, env});
});
after(async () => {
 await deleteApp(app);
});
async function create(requestId) {
 return (await service.handle({action: "create", requestId, senderId: "sender", riderId: "rider"}, context("operator"))).fixtureId;
}
function runner(fixtureId) {
 return (action, role = "sender", delivery = "a", data = {}) => service.handle({action, fixtureId, delivery, ...data}, context(role));
}
async function complete(run, delivery = "a") {
  for (const action of ["start_heading_to_pickup", "arrived_at_pickup", "verify_collection_pin", "confirm_collected", "start_delivery", "arrived_at_dropoff", "verify_receiver_pin"]) await run(action, "rider", delivery, {pin: action === "verify_collection_pin" ? "2468" : "8642"});
}
test("security fails closed before any fixture is created", async () => {
  for (const ctx of [{}, context("outsider"), {auth: {uid: "operator"}}]) await assert.rejects(service.handle({action: "create"}, ctx));
  for (const patch of [{STRIPE_MODE: "LIVE"}, {GCLOUD_PROJECT: "other"}, {QA_LIFECYCLE_ENABLED: "false"}]) await assert.rejects(factory({db, env: {...env, ...patch}}).handle({action: "create"}, context("operator")));
  assert.equal((await db.collection("qaLifecycleFixtures").get()).size, 0);
});
test("canonical lifecycle, rating, tip, FIFO and reversals remain isolated and idempotent", async () => {
  const fixtureId = await create("normal"); const run = runner(fixtureId);
  assert.equal(await create("normal"), fixtureId);
  await assert.rejects(create("second-active"));
  await assert.rejects(run("book", "rider"));
  await run("book"); await assert.rejects(run("accept", "rider"));
  await run("pay"); await run("accept", "rider");
  await assert.rejects(run("verify_receiver_pin", "rider", "a", {pin: "8642"}));
  await run("capture_tip"); await complete(run);
  await Promise.all(Array.from({length: 4}, () => run("capture_tip")));
  const root = db.collection("qaLifecycleFixtures").doc(fixtureId);
  assert.equal((await root.collection("riderEarnings").doc("rider").get()).data().availableBalance, 16);
  await Promise.all(Array.from({length: 4}, () => run("rate", "sender", "a", {stars: 5, feedback: "Careful and professional", feedbackTags: []})));
  assert.equal((await root.collection("driverRatings").get()).size, 1);
  const view = await run("read", "rider"); assert.equal(view.records.publishedDriverRatings[0].feedbackText, "Careful and professional");
  await assert.rejects(run("rate", "rider", "a", {stars: 5}));
  await run("refund_delivery", "operator");
  assert.equal((await root.collection("riderEarnings").doc("rider").get()).data().availableBalance, 16);
  await run("book", "sender", "b"); await run("pay", "sender", "b"); await run("accept", "rider", "b"); await complete(run, "b");
  await run("rate", "sender", "b", {stars: 2, feedback: "Please review", feedbackTags: ["Safety concern"]});
  assert.equal((await root.collection("supportCases").get()).size, 1);
  const allocation = await run("allocate", "operator", "a", {amountPence: 2000});
  assert.deepEqual(allocation.allocations.map((row) => row.amountPence), [1300, 300, 400]);
  await run("allocate", "operator", "a", {amountPence: 2000});
  await run("refund_tip", "operator", "a", {reason: "duplicate_charge"});
  await run("refund_tip", "operator", "a", {reason: "duplicate_charge"});
  assert.equal((await root.collection("riderEarnings").doc("rider").get()).data().availableBalance, 26);
  await run("book", "sender", "c"); await run("pay", "sender", "c"); await run("accept", "rider", "c"); await run("capture_tip", "sender", "c"); await run("cancel", "sender", "c");
  const c = `qa_${fixtureId}_c`;
  assert.equal((await root.collection("walletTransactions").doc(`delivery_tip_${c}`).get()).exists, false);
  assert.equal((await root.collection("deliveryTips").doc(c).get()).data().reversedPence, 300);
  const fixture = (await root.get()).data(); const scoped = scopedDatabase(db, fixture);
  await assert.rejects(scoped.runTransaction((tx) => tx.set(db.doc("riderEarnings/real"), {availableBalance: 100})));
  await assert.rejects(scoped.runTransaction((tx) => tx.delete(root.collection("walletTransactions").doc(`delivery_tip_qa_${fixtureId}_a`))));
  for (const name of ["deliveryRequests", "riderEarnings", "walletTransactions", "offers", "notifications", "referrals", "payoutRequests"]) assert.equal((await db.collection(name).get()).size, 0, name);
  await run("cleanup", "operator"); await run("cleanup", "operator");
  assert.equal((await root.get()).data().archived, true);
  assert.equal((await root.collection("deliveryEvidence").get()).size, 0);
  assert.ok((await root.collection("walletTransactions").get()).size > 0);
});
test("expiry cleans an interrupted lifecycle without terminal state bypass", async () => {
  const fixtureId = await create("expire"); const run = runner(fixtureId);
  await run("book"); await run("pay"); await run("accept", "rider"); await run("capture_tip");
  await run("start_heading_to_pickup", "rider");
  const root = db.collection("qaLifecycleFixtures").doc(fixtureId);
  await root.update({cleanupDueAt: Timestamp.fromMillis(1), expiresAt: Timestamp.fromMillis(1)});
  await service.expire(); await service.expire();
  assert.equal((await root.get()).data().archived, true);
  assert.equal((await root.collection("riderWalletTransactions").get()).size, 0);
  assert.equal((await root.collection("walletTransactions").get()).size, 1);
});

test("capture racing cancellation leaves no orphan capture or Rider earning", async () => {
  const fixtureId = await create("race"); const run = runner(fixtureId);
  await run("book"); await run("pay"); await run("accept", "rider");
  const results = await Promise.allSettled([run("capture_tip"), run("cancel"), run("capture_tip"), run("cancel")]);
  assert.ok(results.some((result) => result.status === "fulfilled"));
  await run("cancel");
  const root = db.collection("qaLifecycleFixtures").doc(fixtureId);
  const objects = (await root.collection("qaProviderObjects").get()).docs.map((doc) => doc.data());
  for (const capture of objects.filter((row) => row.id.startsWith("qa_pi_"))) assert.equal(objects.filter((row) => row.payment_intent === capture.id).length, 1);
  assert.equal((await root.collection("riderWalletTransactions").get()).size, 0);
  await run("cleanup", "operator");
});
