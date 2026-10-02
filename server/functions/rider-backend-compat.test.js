/* eslint-disable max-len */
"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {createCompat, OWNERS} = require("./rider-backend-compat");
const context = {auth: {uid: "fixture"}, app: {appId: "fixture"}, rawRequest: {headers: {authorization: "Bearer fixture-token", "x-firebase-appcheck": "fixture-attestation"}}};
test("Rider compatibility preserves every request identity and verified security header in one dispatch", async () => {
  for (const [name, owner] of Object.entries(OWNERS)) {
    const calls = [];
    const handler = createCompat(name, {fetchImpl: async (url, request) => {
      calls.push({url, request}); return {ok: true, json: async () => ({result: {requestId: "same-id"}})};
    }});
    const data = {requestId: "same-id", amount: 0};
    assert.deepEqual(await handler.run(data, context), {requestId: "same-id"});
    assert.equal(calls.length, 1);
    assert.equal(calls[0].url, `https://${owner}-j2b7cicfwq-uc.a.run.app/${name}`);
    assert.deepEqual(JSON.parse(calls[0].request.body), {data});
    assert.equal(calls[0].request.headers.authorization, context.rawRequest.headers.authorization);
    assert.equal(calls[0].request.headers["x-firebase-appcheck"], "fixture-attestation");
  }
});
test("compatibility rejects missing verified auth and attestation without dispatch", async () => {
  const handler = createCompat("requestRiderWithdrawal", {fetchImpl: async () => {
throw new Error("must not dispatch");
}});
  await assert.rejects(handler.run({}, {}), {code: "unauthenticated"});
  await assert.rejects(handler.run({}, {...context, app: null}), {code: "failed-precondition"});
});
test("uncertain financial transport never retries and retains owner error semantics", async () => {
  let calls = 0;
  const unavailable = createCompat("createRiderTransferOrPayout", {fetchImpl: async () => {
calls++; throw new Error("timeout");
}});
  await assert.rejects(unavailable.run({requestId: "stable"}, context), {code: "unavailable"});
  assert.equal(calls, 1);
  const duplicate = createCompat("requestRiderWithdrawal", {fetchImpl: async () => ({ok: false, json: async () => ({error: {status: "ALREADY_EXISTS", message: "Pending withdrawal"}})})});
  await assert.rejects(duplicate.run({}, context), {code: "already-exists"});
});
test("standalone Rider owners construct real handlers without loading compatibility exports", () => {
  const {createHandlers} = require("./cloud-run-rider-finance-handlers");
  const {FAMILY_ROUTES} = require("./cloud-run-payment-family");
  for (const family of ["rider_payouts", "rider_connect_accounts"]) {
    const handlers = createHandlers(family);
    assert.deepEqual(Object.keys(handlers), FAMILY_ROUTES[family]);
    for (const handler of Object.values(handlers)) assert.equal(typeof handler.run, "function");
  }
  assert.throws(() => createHandlers("gifts"), /Unsupported/);
});
