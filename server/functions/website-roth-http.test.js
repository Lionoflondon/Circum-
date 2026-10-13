/* eslint-disable max-len, require-jsdoc */
"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const Stripe = require("stripe");
const {createWebsiteRothServer} = require("./cloud-run-website-roth");
test("HTTP rejects missing App Check and forged Stripe events; accepts correctly signed fixture", async () => {
  const stripe = new Stripe("sk_test_local_fixture");
  const secret = "whsec_local_fixture_only";
  let finalized = 0;
  let failNext = false;
  const service = {request: async () => ({ok: true}), finalize: async () => {
finalized++;
if (failNext) {
 failNext = false; throw new Error("temporary backend failure");
}
}};
  const server = createWebsiteRothServer({service, stripe, webhookSecret: secret, verifyAppCheck: async (token) => {
if (token !== "test-only-valid") throw new Error("invalid");
}});
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const url = `http://127.0.0.1:${server.address().port}`;
  try {
    assert.equal((await fetch(`${url}/api/roth/request`, {method: "POST", body: "{}"})).status, 503);
    const payload = JSON.stringify({id: "evt_test", type: "checkout.session.completed", data: {object: {id: "cs_test", metadata: {type: "website_roth_top_up"}}}});
    assert.equal((await fetch(`${url}/webhook`, {method: "POST", body: payload, headers: {"stripe-signature": "forged"}})).status, 400);
    assert.equal(finalized, 0);
    const signature = stripe.webhooks.generateTestHeaderString({payload, secret});
    assert.equal((await fetch(`${url}/webhook`, {method: "POST", body: payload, headers: {"stripe-signature": signature}})).status, 200);
    assert.equal(finalized, 1);
    failNext = true;
    assert.equal((await fetch(`${url}/webhook`, {method: "POST", body: payload, headers: {"stripe-signature": signature}})).status, 500);
    assert.equal((await fetch(`${url}/webhook`, {method: "POST", body: payload, headers: {"stripe-signature": signature}})).status, 200);
  } finally {
await new Promise((resolve) => server.close(resolve));
}
});

test("runtime refuses default database, LIVE keys, missing allowlist and live enablement", () => {
  const {testRuntimeConfig} = require("./cloud-run-website-roth");
  const env = {WEBSITE_ROTH_ENABLED: "true", WEBSITE_ROTH_LIVE: "false", STRIPE_MODE: "test", FIRESTORE_DATABASE_ID: "roth-website-test", STRIPE_SECRET_KEY: "sk_test_fixture", WEBSITE_ROTH_WEBHOOK_SECRET: "whsec_fixture", WEBSITE_ROTH_OTP_SECRET: "a".repeat(32), WEBSITE_ROTH_TEST_UIDS: "test-user"};
  assert.equal(testRuntimeConfig(env).databaseId, "roth-website-test");
  for (const patch of [{FIRESTORE_DATABASE_ID: "(default)"}, {STRIPE_SECRET_KEY: "sk_live_fixture"}, {WEBSITE_ROTH_TEST_UIDS: ""}, {WEBSITE_ROTH_LIVE: "true"}, {STRIPE_MODE: "live"}]) assert.throws(() => testRuntimeConfig({...env, ...patch}));
});

test("runtime isolation requires actual named read permission and explicit default permission denial", async () => {
  const {verifyTestDatabaseIsolation} = require("./cloud-run-website-roth");
  const database = (read) => ({collection: () => ({doc: () => ({get: read})})});
  const allowed = database(async () => ({}));
  const denied = database(async () => {
throw Object.assign(new Error("denied"), {code: 7});
});
  assert.equal(await verifyTestDatabaseIsolation(allowed, denied), true);
  await assert.rejects(verifyTestDatabaseIsolation(allowed, allowed), /default database/);
  await assert.rejects(verifyTestDatabaseIsolation(denied, denied));
});
