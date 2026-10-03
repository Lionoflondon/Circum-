/* eslint-disable max-len, require-jsdoc */
"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {initializeApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const {factory, testProvider, scopedDb} = require("./qa-gift-journey");
const credentials = {identities: {admin: {uid: "qa_admin", email: "admin@example.test"}, sender: {uid: "qa_sender", email: "sender@example.test"}, rider: {uid: "qa_rider", email: "rider@example.test"}}};
const context = (role) => ({auth: {uid: credentials.identities[role].uid, token: {email: credentials.identities[role].email}}, app: {appId: "qa"}});
function stripeFixture() {
  const customers = new Map(); const intents = new Map(); let creates = 0;
  return {customers: {
    create: async (p) => {
const r = {id: "cus_test", livemode: false, ...p}; customers.set(r.id, r); return r;
},
    retrieve: async (id) => customers.get(id), del: async (id) => {
customers.delete(id); return {deleted: true};
},
  }, paymentIntents: {
    create: async (p) => {
creates++; const r = {id: "pi_test", livemode: false, status: "requires_payment_method", ...p}; intents.set(r.id, r); return r;
},
    retrieve: async (id) => intents.get(id),
    confirm: async (id) => {
const r = {...intents.get(id), status: "succeeded", amount_received: 5000}; intents.set(id, r); return r;
},
    list: async () => ({data: [...intents.values()], has_more: false}),
    cancel: async (id) => {
intents.get(id).status = "canceled"; return intents.get(id);
},
  }, get creates() {
return creates;
}};
}
test("QA provider rejects live/foreign objects and non-fixed checkout", async () => {
  const p = testProvider({paymentIntents: {retrieve: async () => ({livemode: true})}}, "fixture");
  await assert.rejects(p.paymentIntents.retrieve("pi"), /TEST provider/);
  await assert.rejects(p.paymentIntents.create({amount: 100, currency: "gbp"}, {}), /Fixed one-off/);
  assert.throws(() => factory({secret: "sk_live_fake"}), /TEST provider/);
});
test("authenticated private Gift checkout, canonical admin and Story lifecycle, replay, isolation and cleanup", {skip: !process.env.FIRESTORE_EMULATOR_HOST}, async () => {
  initializeApp({projectId: "demo-gifts-qa-route", storageBucket: "demo-gifts-qa-route.appspot.com"});
  const raw = getFirestore(); const stripe = stripeFixture();
  const handler = factory({raw, stripe, secret: "sk_test_private", credentials}).handle;
  await assert.rejects(handler({action: "prepare", requestId: "a"}, {auth: {uid: "foreign"}, app: {appId: "qa"}}), /Approved QA/);
  await assert.rejects(handler({action: "prepare", requestId: "a"}, {auth: {uid: "qa_admin"}}), /App Check/);
  await assert.rejects(handler({action: "prepare", requestId: "a"}, context("sender")), /Wrong QA actor/);
  const prepared = await handler({action: "prepare", requestId: "test_lifecycle"}, context("admin")); const fid = prepared.fixtureId;
  const call = (role, action, rest = {}) => handler({fixtureId: fid, action, ...rest}, context(role));
  try {
    assert.equal((await handler({action: "prepare", requestId: "test_lifecycle"}, context("admin"))).fixtureId, fid);
    await assert.rejects(handler({action: "prepare", requestId: "another"}, context("admin")), /cleaned first/);
    const db = scopedDb(raw, fid); assert.throws(() => db.collection("giftStoryRuntimeFixtures"), /scope/);
    await assert.rejects(db.runTransaction((tx) => tx.set(raw.collection("giftRequests").doc("foreign"), {})), /scope/);
    await call("sender", "checkout"); await call("sender", "checkout"); assert.equal(stripe.creates, 1);
    await assert.rejects(call("sender", "confirm_test_payment"), /Wrong QA actor/);
    const originalTransaction = raw.runTransaction.bind(raw); let failNotification = true;
    raw.runTransaction = (fn) => originalTransaction((tx) => fn(new Proxy(tx, {get(target, key) {
      if (key === "set") {
return (ref, ...args) => {
        if (failNotification && ref.path.includes("/state/notifications/records/")) {
          failNotification = false; throw new Error("simulated notification failure after payment");
        }
        return target.set(ref, ...args);
      };
}
      const value = target[key]; return typeof value === "function" ? value.bind(target) : value;
    }})));
    await assert.rejects(call("admin", "confirm_test_payment"), /simulated notification failure/);
    assert.equal((await call("sender", "read")).paymentStatus, "paid");
    assert.equal((await call("admin", "confirm_test_payment")).paymentStatus, "paid");
    assert.equal((await call("admin", "confirm_test_payment")).idempotent, true);
    await assert.rejects(call("admin", "advance", {status: "ready_for_gift_delivery"}), /Out-of-order/);
    for (const status of ["approved", "curation_started", "ready_for_gift_delivery"]) {
await call("admin", "advance", {status}); await call("admin", "advance", {status});
}
    await assert.rejects(call("sender", "complete_delivery"), /Wrong QA actor/);
    assert.equal((await call("rider", "complete_delivery")).storyUnlocked, true); await call("rider", "complete_delivery");
    const result = await call("sender", "read"); assert.equal(result.storyUnlocked, true); assert.equal(result.emailCount, 5); assert.equal(result.notificationCount, 6); assert.ok(result.emailStates.every((e) => e.status === "sent"));
    assert.ok((await call("sender", "story")).story); await assert.rejects(call("rider", "story"), /access denied|not found/);
    assert.equal((await raw.collection("giftRequests").get()).size, 0); assert.equal((await raw.collection("emailQueue").get()).size, 0);
  } finally {
    const clean = await call("admin", "cleanup"); assert.equal(clean.rootExists, false); assert.equal(clean.remainingSubcollections, 0);
  }
});
