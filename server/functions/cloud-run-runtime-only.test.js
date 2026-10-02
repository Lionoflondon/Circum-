/* eslint-disable max-len */
"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {cloudRunOnly} = require("./cloud-run-runtime-only");
const {extractStack} = require("./node_modules/firebase-functions/lib/runtime/loader.js");
test("runtime-only handler preserves context, results and failures without deployment metadata", async () => {
  const context = {auth: {uid: "approved-test"}};
  const failure = new Error("original handler failure");
  const original = {__endpoint: {callableTrigger: {enforceAppCheck: true}}, run: async (data, received) => {
    assert.equal(received, context);
    if (data.fail) throw failure;
    return {same: data};
  }};
  const wrapped = cloudRunOnly(original, "existing-owner", true);
  const data = {readOnly: true};
  assert.deepEqual(await wrapped.run(data, context), {same: data});
  await assert.rejects(wrapped.run({fail: true}, context), (error) => error === failure);
  assert.equal(wrapped.__endpoint, undefined);
  assert.equal(wrapped.__trigger, undefined);
  assert.deepEqual(wrapped._cloudRunOnly, {owner: "existing-owner", triggerType: "callable", appCheckRequired: true});
  assert.ok(Object.isFrozen(wrapped));
  assert.throws(() => cloudRunOnly({}, "existing-owner"), TypeError);
});
test("Firebase SDK discovery excludes migrated exports and retains healthy managed functions", () => {
  process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || "circum-registry-audit";
  const exported = require("./index");
  const endpoints = {};
  extractStack(exported, endpoints, [], {});
  for (const name of ["getSenderAccountActivity", "exportSenderData", "updateSenderPreferences", "revokeSenderSessions", "createBusinessGiftOrder", "escalateUnclaimedDeliveries", "markStaleRiderPresenceOffline", "getSenderPaymentMode", "getSenderRothBalance", "getRiderEarningsSummary", "getGiftStoryVideoDownload"]) {
    assert.equal(endpoints[name], undefined, `${name} must never recreate a managed authority`);
    assert.equal(typeof exported[name].run, "function", `${name} remains usable by its existing Cloud Run owner`);
    assert.ok(exported[name]._cloudRunOnly.owner.startsWith("circum-"));
  }
  assert.equal(exported.createBusinessGiftOrder._cloudRunOnly.appCheckRequired, true);
  assert.equal(exported.getSenderAccountActivity._cloudRunOnly.appCheckRequired, false);
  assert.ok(endpoints.ensureSenderAccount, "healthy managed deployments remain discoverable");
});

test("runtime-only exports preserve the original HTTP callable wrapper", async () => {
 const req = {headers: {authorization: "Bearer test", "x-firebase-appcheck": "test-app"}}; const res = {};
 const original = (received, response) => {
assert.equal(received, req); assert.equal(response, res); return "original-http";
}; original.run = async () => "original-run"; original.__endpoint = {callableTrigger: {enforceAppCheck: true}};
 const wrapped = cloudRunOnly(original, "existing-owner", true); assert.equal(typeof wrapped, "function"); assert.equal(wrapped(req, res), "original-http"); assert.equal(await wrapped.run(), "original-run"); assert.equal(wrapped.__endpoint, undefined);
});
test("runtime-only HTTP delegation retains mandatory Firebase App Check before business logic", async () => {
  const {senderPaymentCallable} = require("./sender-app-check");
  const {createSenderDeliveryPaymentsServer, ROUTES} = require("./cloud-run-sender-delivery-payments");
  let invoked = 0;
  const guarded = cloudRunOnly(senderPaymentCallable(async () => {
invoked++; return {ok: true};
}), "existing-owner", true);
  const handlers = Object.fromEntries(Object.values(ROUTES).map((name) => [name, guarded]));
  const server = createSenderDeliveryPaymentsServer(handlers);
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  try {
    const response = await fetch(`http://127.0.0.1:${server.address().port}/getSenderPaymentMode`, {method: "POST", headers: {"content-type": "application/json"}, body: "{\"data\":null}"});
    assert.equal(response.status, 401); assert.equal((await response.json()).error.status, "UNAUTHENTICATED"); assert.equal(invoked, 0);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});
