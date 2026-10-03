/* eslint-disable max-len, require-jsdoc */
"use strict";
const assert = require("node:assert/strict");
const test = require("node:test");
const Module = require("node:module");
const actualFirestore = require("firebase-admin/firestore");

function fixture({hasAccount = true, email = "target@example.test"} = {}) {
  const docs = new Map([["adminUsers/operator", {active: true}], ["riderProfiles/target", {...(hasAccount ? {stripeConnectAccountId: "acct_target"} : {}), ...(email ? {email} : {})}]]);
  const writes = [];
  let auditSequence = 0;
  const db = {collection: (collection) => ({add: async (data) => {
const id = `audit_${auditSequence++}`; writes.push(`${collection}/${id}`); docs.set(`${collection}/${id}`, data); return {id};
}, doc: (id) => ({
    get: async () => ({exists: docs.has(`${collection}/${id}`), data: () => docs.get(`${collection}/${id}`)}),
    set: async (data, options) => {
      writes.push(`${collection}/${id}`);
      docs.set(`${collection}/${id}`, options?.merge ? {...docs.get(`${collection}/${id}`), ...data} : data);
    },
  })})};
  db.batch = () => {
    const pending = [];
    return {set(ref, data, options) {
pending.push(() => ref.set(data, options)); return this;
}, commit: async () => Promise.all(pending.map((write) => write()))};
  };
  const original = Module._load;
  delete require.cache[require.resolve("./rider-connect")];
  let rider;
  try {
    Module._load = function(id, parent, isMain) {
      return id === "firebase-admin/firestore" ? {...actualFirestore, getFirestore: () => db} : original.call(this, id, parent, isMain);
    };
    rider = require("./rider-connect");
  } finally {
    Module._load = original;
  }
  const calls = [];
  const account = (id) => ({id, type: "express", livemode: true, details_submitted: true, charges_enabled: true, payouts_enabled: true, requirements: {currently_due: [], past_due: []}});
  const stripe = {_circumStripeMode: "live", accounts: {
    retrieve: async (id) => {
calls.push({operation: "retrieve", id}); return account(id);
},
    create: async (data, options) => {
calls.push({operation: "create", data, options}); return account("acct_target");
},
    createLoginLink: async (id) => {
calls.push({operation: "management", id}); return {url: "https://example.test/manage"};
},
  }, accountLinks: {create: async (data) => {
calls.push({operation: "onboarding", data}); return {url: "https://example.test/onboard"};
}}};
  const admin = {auth: {uid: "operator", token: {role: "super_admin", email: "operator@example.test"}}, app: {appId: "unit-fixture"}};
  return {rider, stripe, admin, docs, writes, calls};
}
const operations = ["createStripeConnectAccountForRider", "createStripeOnboardingLink", "syncStripeConnectStatus", "createStripeAccountManagementLink"];

test("authorized Rider manager Connect calls target the requested Rider, never the operator profile", async () => {
  for (const operation of operations) {
    const f = fixture();
    await f.rider[operation](f.stripe).run({riderId: "target"}, f.admin);
    assert.ok(f.writes.every((path) => path.endsWith("/target")), operation);
    assert.ok(f.calls.some((call) => call.operation === "retrieve" && call.id === "acct_target"), operation);
    assert.equal(f.docs.has("riderProfiles/operator"), false, operation);
    assert.ok(f.calls.every((call) => !call.id || call.id === "acct_target"), operation);
  }
});

test("Riders cannot spoof another Rider in any Connect operation", async () => {
  for (const operation of operations) {
    const f = fixture();
    const context = {auth: {uid: "ordinary", token: {role: "rider"}}, app: {appId: "unit-fixture"}};
    await assert.rejects(f.rider[operation](f.stripe).run({riderId: "target", role: "super_admin"}, context), {code: "permission-denied"});
    assert.equal(f.calls.length, 0, operation);
    assert.equal(f.writes.length, 0, operation);
  }
});

test("an active admin record without Rider review capability cannot delegate Connect calls", async () => {
  for (const operation of operations) {
    const f = fixture();
    const context = {...f.admin, auth: {...f.admin.auth, token: {role: "support_admin"}}};
    await assert.rejects(f.rider[operation](f.stripe).run({riderId: "target"}, context), {code: "permission-denied"});
    assert.equal(f.calls.length, 0, operation);
    assert.equal(f.writes.length, 0, operation);
  }
});

test("delegated account creation preserves target identity and never substitutes the operator email", async () => {
  const f = fixture({hasAccount: false, email: ""});
  const handler = f.rider.createStripeConnectAccountForRider(f.stripe);
  await handler.run({riderId: "target"}, f.admin);
  await handler.run({riderId: "target"}, f.admin);
  const creates = f.calls.filter((call) => call.operation === "create");
  assert.equal(creates.length, 1);
  assert.equal(creates[0].data.metadata.riderId, "target");
  assert.equal(creates[0].data.email, undefined);
  assert.equal(creates[0].options.idempotencyKey, "rider_connect_account_target_initial");
});

test("existing self-service Connect callers retain implicit authenticated Rider identity", async () => {
  const f = fixture({hasAccount: false, email: ""});
  const context = {auth: {uid: "target", token: {email: "self@example.test"}}, app: {appId: "unit-fixture"}};
  await f.rider.createStripeConnectAccountForRider(f.stripe).run({}, context);
  const created = f.calls.find((call) => call.operation === "create");
  assert.equal(created.data.metadata.riderId, "target");
  assert.equal(created.data.email, "self@example.test");
});
