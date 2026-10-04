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
      assert.equal(url, `https://${policy.owner}-j2b7cicfwq-uc.a.run.app/${policy.path !== undefined ? policy.path : operation}`);
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
      assert.equal(optional.status, policy.appCheck && !policy.sdkEnforced ? policy.sdkAuthFailure ? 401 : 400 : 200);
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
test("Gift Story landing preserves HTTP path, HTML, and guest transport without selecting other handlers", async () => {
 let calls = 0;
 await withServer("giftStoryLanding", async (url, options) => {
  calls++;
  assert.equal(url, "https://circum-gift-payments-j2b7cicfwq-uc.a.run.app/giftStoryLanding/opaque-token?view=story");
  assert.equal(options.method, "GET"); assert.equal(options.body, undefined);
  return {status: 410, headers: new Headers({"content-type": "text/html"}), arrayBuffer: async () => Buffer.from("<title>Expired</title>")};
 }, async (base) => {
  const r = await fetch(base + "/opaque-token?view=story"); assert.equal(r.status, 410); assert.equal(r.headers.get("content-type"), "text/html"); assert.equal(await r.text(), "<title>Expired</title>");
  assert.equal((await fetch(base + "/other/operation")).status, 400); assert.equal(calls, 1);
 });
});

test("Gift landing preflight permits its GET and HEAD contract while callables remain POST-only", async () => {
  for (const operation of ["giftStoryLanding", "getGiftStoryVideoDownload"]) {
    await withServer(operation, async () => {
 throw new Error("preflight must not call owner");
}, async (base) => {
      const response = await fetch(base, {method: "OPTIONS", headers: {origin: "https://circum-app-2797c.web.app", "access-control-request-method": "GET"}});
      assert.equal(response.status, 204);
      assert.equal(response.headers.get("access-control-allow-methods"), operation === "giftStoryLanding" ? "GET, HEAD, POST, OPTIONS" : "POST, OPTIONS");
    });
  }
});

test("native Wallet URLs retain the original payment SDK missing-App-Check error without invoking business logic", async () => {
 for (const operation of ["getSenderWalletTransactions", "completeSenderWalletOnboarding"]) {
  let calls = 0; const server = createServer({operation, fetchImpl: async () => {
calls++; throw new Error("business handler must not run");
}});
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  try {
   const response = await fetch(`http://127.0.0.1:${server.address().port}/`, {method: "POST", headers: {"Content-Type": "application/json", Authorization: "Bearer native-sdk-shaped-token"}, body: JSON.stringify({data: {}})});
   assert.equal(response.status, 401); assert.equal((await response.json()).error.status, "UNAUTHENTICATED"); assert.equal(calls, 0);
  } finally {
   await new Promise((resolve) => server.close(resolve));
  }
 }
});

for (const [operation, data] of [["saveSenderDraft", {draft: {fixture: "x".repeat(24 * 1024)}}], ["analyseParcelPhotoForIris", {photoBase64: "A".repeat(256 * 1024)}]]) {
  test(`${operation} compatibility forwards payloads beyond the generic account cap without truncation or a second attempt`, async () => {
    const body = JSON.stringify({data});
    let calls = 0;
    await withServer(operation, async (_url, options) => {
      calls++;
      assert.equal(options.body.toString(), body);
      return {status: 400, arrayBuffer: async () => Buffer.from(JSON.stringify({error: {status: "INVALID_ARGUMENT"}}))};
    }, async (base) => {
      const response = await fetch(base, {method: "POST", headers: {authorization: "Bearer verified-by-owner", "content-type": "application/json"}, body});
      assert.equal(response.status, 400);
      assert.deepEqual(await response.json(), {error: {status: "INVALID_ARGUMENT"}});
      assert.equal(calls, 1);
    });
  });
}
