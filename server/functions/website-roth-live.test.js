/* eslint-disable max-len, require-jsdoc */
"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const Stripe = require("stripe");
const {liveRuntimeConfig, verifyLiveDatabaseIsolation, assertWalletOwner, guardedWalletDatabase, liveCheckoutProvider, createWebsiteRothLiveServer, trustedClientKey, assertWalletAccounting} = require("./cloud-run-website-roth-live");
const env = {WEBSITE_ROTH_LIVE_ENABLED: "true", STRIPE_MODE: "live", FIRESTORE_DATABASE_ID: "(default)", STRIPE_SECRET_KEY: "sk_live_fixture", WEBSITE_ROTH_WEBHOOK_SECRET: "whsec_fixture", WEBSITE_ROTH_OTP_SECRET: "a".repeat(32), WEBSITE_ROTH_STRIPE_ACCOUNT: "acct_fixture", WEBSITE_ROTH_LIVE_UIDS: "owner"};
test("LIVE candidate requires its own credentials, database and allowlist; public mode requires exact-source certification", () => {
  const config = liveRuntimeConfig(env);
  assert.equal(config.publicEnabled, false); assert(config.allowedUids.has("owner"));
  assert.equal(config.returnBase, "https://circumuk.com/roth/live-cert/");
  for (const patch of [{STRIPE_SECRET_KEY: "sk_test_fixture"}, {FIRESTORE_DATABASE_ID: "roth-website-test"}, {WEBSITE_ROTH_LIVE_UIDS: ""}, {STRIPE_MODE: "test"}, {FIRESTORE_EMULATOR_HOST: "127.0.0.1:8080"}, {WEBSITE_ROTH_LIVE_PUBLIC: "true"}]) assert.throws(() => liveRuntimeConfig({...env, ...patch}));
  const sha = "a".repeat(40);
  assert.equal(liveRuntimeConfig({...env, WEBSITE_ROTH_LIVE_PUBLIC: "true", CIRCUM_SOURCE_SHA: sha, WEBSITE_ROTH_PRODUCTION_CERTIFIED_SHA: sha}).allowedUids, null);
  assert.throws(() => liveRuntimeConfig({...env, WEBSITE_ROTH_LIVE_PUBLIC: "true", CIRCUM_SOURCE_SHA: sha, WEBSITE_ROTH_PRODUCTION_CERTIFIED_SHA: "b".repeat(40)}));
});
test("LIVE identity must read its database and be denied TEST access", async () => {
  const database = (get) => ({collection: () => ({doc: () => ({get})})});
  const allowed = database(async () => ({}));
  const denied = database(async () => {
throw Object.assign(Error("denied"), {code: 7});
});
  assert.equal(await verifyLiveDatabaseIsolation(allowed, denied), true);
  await assert.rejects(verifyLiveDatabaseIsolation(allowed, allowed));
  await assert.rejects(verifyLiveDatabaseIsolation(denied, denied));
});
test("wallet owner and freeze checks guard the financial transaction before writes", async () => {
  assertWalletOwner({exists: false}, "owner");
  assertWalletOwner({exists: true, data: () => ({uid: "owner"})}, "owner");
  assert.throws(() => assertWalletOwner({exists: true, data: () => ({uid: "other"})}, "owner"));
  assert.throws(() => assertWalletOwner({exists: true, data: () => ({uid: "owner", isFrozen: true})}, "owner", {requireAvailable: true}));
  let writes = 0;
  const db = {runTransaction: (fn) => fn({getAll: async () => [{exists: true, data: () => ({uid: "other"})}], create: () => {
writes++;
}})};
  await assert.rejects(guardedWalletDatabase(db, "owner").runTransaction(async (tx) => {
await tx.getAll({parent: {id: "wallets"}}); tx.create();
}));
  assert.equal(writes, 0);
});
test("LIVE Checkout pins its return path and marks both provider artifacts without changing idempotency", async () => {
  let captured;
  const sessions = {create: async (params, options) => {
captured = {params, options}; return {};
}, retrieve() {}, expire() {}};
  await liveCheckoutProvider({checkout: {sessions}}, "https://circumuk.com/roth/live-cert/").checkout.sessions.create({metadata: {type: "website_roth_top_up"}, payment_intent_data: {metadata: {orderId: "owned"}}}, {idempotencyKey: "same"});
  assert.equal(captured.params.metadata.websiteRealm, "live");
  assert.equal(captured.params.payment_intent_data.metadata.websiteRealm, "live");
  assert.equal(captured.params.success_url, "https://circumuk.com/roth/live-cert/?payment=returned");
  assert.equal(captured.options.idempotencyKey, "same");
});
test("LIVE HTTP verifies signatures and realm; TEST events never finalize a LIVE purchase", async () => {
  const stripe = new Stripe("sk_live_fixture"); const secret = "whsec_fixture"; let finalized = 0;
  const server = createWebsiteRothLiveServer({service: {finalize: async () => {
finalized++;
}}, stripe, webhookSecret: secret, isolationVerified: true, verifyAppCheck: async () => {
throw Object.assign(Error("unauthorized"), {statusCode: 401});
}});
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const url = `http://127.0.0.1:${server.address().port}`;
  const send = async (event) => {
const payload = JSON.stringify(event); return fetch(`${url}/webhook`, {method: "POST", body: payload, headers: {"stripe-signature": stripe.webhooks.generateTestHeaderString({payload, secret})}});
};
  const event = {id: "evt_live_fixture", livemode: true, type: "checkout.session.completed", data: {object: {metadata: {type: "website_roth_top_up", websiteRealm: "live"}}}};
  try {
    assert.equal((await fetch(`${url}/api/roth-live/wallet`, {method: "POST", body: "{}"})).status, 401);
    assert.equal((await fetch(`${url}/webhook`, {method: "POST", body: "{}", headers: {"stripe-signature": "forged"}})).status, 400);
    assert.equal((await send({...event, livemode: false})).status, 200); assert.equal(finalized, 0);
    const wrong = structuredClone(event); wrong.data.object.metadata.testDatabase = "roth-website-test";
    assert.equal((await send(wrong)).status, 400); assert.equal(finalized, 0);
    assert.equal((await send(event)).status, 200); assert.equal(finalized, 1);
    const health = await (await fetch(`${url}/health`)).json(); assert.equal(health.environment, "live"); assert.equal(health.publicPurchasesEnabled, false);
  } finally {
await new Promise((resolve) => server.close(resolve));
}
});

test("LIVE request throttling distinguishes ingress clients and ignores forged prefixes", () => {
  const request = (value) => ({headers: {"x-forwarded-for": value}, socket: {remoteAddress: "127.0.0.1"}});
  assert.equal(trustedClientKey(request("forged, 203.0.113.7, 10.0.0.1")), "203.0.113.7");
  assert.notEqual(trustedClientKey(request("203.0.113.7, 10.0.0.1")), trustedClientKey(request("203.0.113.8, 10.0.0.1")));
  assert.equal(trustedClientKey(request("invalid")), "127.0.0.1");
});

test("LIVE purchases cannot overwrite conflicting or non-finite legacy and canonical balances", () => {
  const snap = (value) => ({exists: true, data: () => value});
  assertWalletAccounting(snap({balance: 10, rothCredit: 10}), snap({balance: 10}));
  assert.throws(() => assertWalletAccounting(snap({balance: 10, rothCredit: 20}), snap({balance: 10})));
  assert.throws(() => assertWalletAccounting(snap({balance: 10, rothCredit: 10}), snap({balance: 20})));
  assert.throws(() => assertWalletAccounting({exists: false}, snap({balance: 20})));
  assert.throws(() => assertWalletAccounting(snap({balance: Infinity}), {exists: false}));
});
