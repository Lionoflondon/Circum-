"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {createProxy, ENDPOINTS} = require("./native-callable-cloud-run-compat");
const request = (data = {}) => ({data, auth: {uid: "qa-user"}, app: {appId: "qa-app"}, rawRequest: {headers: {authorization: "Bearer qa-token", "x-firebase-appcheck": "qa-app-check"}}});
for (const name of Object.keys(ENDPOINTS)) {
  test(`${name} requires Auth and App Check before forwarding`, async () => {
    let calls = 0;
    const proxy = createProxy(name, async () => {
 calls++;
});
    await assert.rejects(proxy({...request(), auth: null}), {code: "unauthenticated"});
    await assert.rejects(proxy({...request(), app: null}), {code: "failed-precondition"});
    await assert.rejects(proxy({...request(), rawRequest: {headers: {}}}), {code: "unauthenticated"});
    assert.equal(calls, 0);
  });
  test(`${name} preserves the canonical owner, payload, credentials and result`, async () => {
    const data = {idempotencyKey: "qa-order", scope: "read"};
    const proxy = createProxy(name, async (url, options) => {
      assert.equal(url, ENDPOINTS[name]);
      assert.deepEqual(JSON.parse(options.body), {data});
      assert.equal(options.headers.authorization, "Bearer qa-token");
      assert.equal(options.headers["x-firebase-appcheck"], "qa-app-check");
      return {ok: true, json: async () => ({result: {ok: true, replay: true}})};
    });
    assert.deepEqual(await proxy(request(data)), {ok: true, replay: true});
  });
}
test("compatibility edge never retries an uncertain mutation", async () => {
  let calls = 0;
  const proxy = createProxy("createBusinessGiftOrder", async () => {
 calls++; throw new Error("network");
});
  await assert.rejects(proxy(request()), {code: "unavailable"});
  assert.equal(calls, 1);
});
test("compatibility edge preserves canonical callable error status", async () => {
  const proxy = createProxy("createBusinessGiftOrder", async () => ({ok: false, json: async () => ({error: {status: "PERMISSION_DENIED"}})}));
  await assert.rejects(proxy(request()), {code: "permission-denied"});
});
