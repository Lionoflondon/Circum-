/* eslint-disable max-len */
"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {once} = require("node:events");
const {createServer, OPERATIONS} = require("./cloud-run-native-callable-proxy");
async function withServer(operation, fetchImpl, run) {
  const server = createServer({operation, fetchImpl});
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  try {
    await run(`http://127.0.0.1:${server.address().port}`);
  } finally {
    server.close();
    await once(server, "close");
  }
}
for (const [operation, policy] of Object.entries(OPERATIONS)) {
  test(`${operation} preserves native envelopes and forwards to its single existing owner`, async () => {
    const requestBody = JSON.stringify({data: {idempotencyKey: "qa-replay", scope: "all_other_devices"}});
    const reply = JSON.stringify({result: {ok: true, idempotent: true}});
    const fakeFetch = async (url, options) => {
      assert.equal(url, `https://${policy.owner}-j2b7cicfwq-uc.a.run.app/${operation}`);
      assert.equal(options.body.toString(), requestBody);
      assert.equal(options.headers.authorization, "Bearer qa-token");
      assert.equal(options.headers["x-firebase-appcheck"], "qa-app-check");
      assert.equal(options.redirect, "error");
      return {status: 200, arrayBuffer: async () => Buffer.from(reply)};
    };
    await withServer(operation, fakeFetch, async (base) => {
      const response = await fetch(base, {method: "POST", headers: {authorization: "Bearer qa-token", "x-firebase-appcheck": "qa-app-check", "content-type": "application/json"}, body: requestBody});
      assert.equal(response.status, 200);
      assert.equal(await response.text(), reply);
      assert.equal(response.headers.get("access-control-allow-origin"), "*");
    });
  });
  test(`${operation} retains its native Auth and App Check policy`, async () => {
    let calls = 0;
    await withServer(operation, async () => {
      calls++;
      return {status: 200, arrayBuffer: async () => Buffer.from("{\"result\":{}}")};
    }, async (base) => {
      const denied = await fetch(base, {method: "POST", headers: {"content-type": "application/json"}, body: "{\"data\":{}}"});
      assert.equal(denied.status, policy.allowGuest ? 200 : 401);
      assert.equal(calls, policy.allowGuest ? 1 : 0);
      const optional = await fetch(base, {method: "POST", headers: {authorization: "Bearer qa-token", "content-type": "application/json"}, body: "{\"data\":{}}"});
      assert.equal(optional.status, policy.appCheck && !policy.sdkEnforced ? 400 : 200);
      assert.equal(calls, (policy.allowGuest ? 1 : 0) + (policy.appCheck && !policy.sdkEnforced ? 0 : 1));
    });
  });
}
test("uncertain mutations are never automatically retried", async () => {
  let calls = 0;
  await withServer("createBusinessGiftOrder", async () => {
    calls++;
    throw new Error("uncertain timeout");
  }, async (base) => {
    const response = await fetch(base, {method: "POST", headers: {authorization: "Bearer qa-token", "x-firebase-appcheck": "qa-app-check", "content-type": "application/json"}, body: "{\"data\":{}}"});
    assert.equal(response.status, 503);
    assert.equal((await response.json()).error.status, "UNAVAILABLE");
    assert.equal(calls, 1);
  });
});
test("upstream callable errors retain status and details without a second envelope", async () => {
  const reply = "{\"error\":{\"status\":\"PERMISSION_DENIED\",\"message\":\"Denied\",\"details\":{\"reason\":\"role\"}}}";
  await withServer("verifyRiderAccountAccess", async () => ({status: 403, arrayBuffer: async () => Buffer.from(reply)}), async (base) => {
    const response = await fetch(base, {method: "POST", headers: {authorization: "Bearer qa-token", "x-firebase-appcheck": "qa-app-check", "content-type": "application/json"}, body: "{\"data\":{}}"});
    assert.equal(response.status, 403);
    assert.equal(await response.text(), reply);
  });
});

test("Gift Story guest tokens remain opaque and cannot select a payment operation", async () => {
 const data = JSON.stringify({data: {giftRequestId: "test-gift", token: "opaque-test-token", operation: "cancelGiftPayment"}});
 await withServer("getGiftStoryVideoDownload", async (url, options) => {
  assert.equal(url, "https://circum-gift-payments-j2b7cicfwq-uc.a.run.app/getGiftStoryVideoDownload"); assert.equal(options.body.toString(), data); assert.equal(options.headers.authorization, undefined);
  return {status: 403, arrayBuffer: async () => Buffer.from("{\"error\":{\"status\":\"PERMISSION_DENIED\"}}")};
 }, async (base) => {
  const response = await fetch(base, {method: "POST", headers: {"content-type": "application/json"}, body: data}); assert.equal(response.status, 403); assert.equal((await response.json()).error.status, "PERMISSION_DENIED");
 });
});
