"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {once} = require("node:events");
const fs = require("node:fs");
const {createServer, allowlistFromCredentials, errorResponse, routeName} = require("./cloud-run-qa-special-flow");
const {fixtureIdForRequest, requiredFixtureId} = require("./qa-special-flow")._test;

async function withServer(dependenciesFactory, run) {
  const server = createServer({dependenciesFactory});
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  try {
 await run(`http://127.0.0.1:${server.address().port}`);
} finally {
 server.close(); await once(server, "close");
}
}

function request(base, options = {}) {
  const headers = {
    "x-firebase-auth": "Bearer firebase-auth-token",
    "x-firebase-appcheck": "app-check-token",
    "content-type": "application/json",
    ...(options.headers || {}),
  };
  if (options.omitAuth) delete headers["x-firebase-auth"];
  if (options.omitAppCheck) delete headers["x-firebase-appcheck"];
  return fetch(`${base}/v1/callable/qaSpecialFlowFixture`, {
    method: "POST", headers,
    body: options.body === undefined ? JSON.stringify({data: {action: "prepare"}}) : options.body,
  });
}

function dependencies(handler) {
  return () => ({
    verifyIdToken: async (token) => {
      if (token === "firebase-auth-token") return {uid: "qa-sender", email: "qa@example.invalid"};
      return Promise.reject(Object.assign(new Error("bad auth"), {code: "auth/invalid-id-token"}));
    },
    verifyAppCheck: async (token) => token === "app-check-token" ? {appId: "qa-web"} : Promise.reject(Object.assign(new Error("bad app"), {code: "app-check/invalid-token"})),
    handler,
  });
}

test("allowlist is derived from the private credential envelope", () => {
  assert.deepEqual(allowlistFromCredentials(JSON.stringify({identities: {
    admin: {uid: "qa-admin"}, sender: {uid: "qa-sender"}, rider: {uid: "qa-rider"},
  }})), {operators: ["qa-admin"], senders: ["qa-sender"], riders: ["qa-rider"]});
  assert.throws(() => allowlistFromCredentials("not-json"), /configuration/);
});

test("health is lazy and declares the TEST-only transport", async () => {
  process.env.CIRCUM_SOURCE_SHA = "qa-source";
  await withServer(() => {
 throw new Error("health must not initialize dependencies");
}, async (base) => {
    const response = await fetch(`${base}/health`);
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), {status: "ok", runtime: "node22", service: "circum-qa-special-flow", source: "qa-source", stripeMode: "TEST"});
  });
});

test("route is limited to the QA callable", () => {
  assert.equal(routeName("/qaSpecialFlowFixture"), "qaSpecialFlowFixture");
  assert.equal(routeName("/v1/callable/qaSpecialFlowFixture"), "qaSpecialFlowFixture");
  assert.equal(routeName("/v1/callable/" + "createBusiness" + "InvoiceCheckout"), null);
});

test("transport has no live Stripe binding or webhook capability", () => {
  const source = fs.readFileSync(require.resolve("./cloud-run-qa-special-flow"), "utf8");
  const dockerfile = fs.readFileSync(require.resolve("./Dockerfile.qa-special-flow"), "utf8");
  assert.match(source, /CIRCUM_QA_STRIPE_SECRET_KEY/);
  assert.doesNotMatch(source, /STRIPE_SECRET_KEY["`]/);
  assert.doesNotMatch(dockerfile, /STRIPE_SECRET_KEY/);
  assert.doesNotMatch(source, /webhook/i);
});

test("fixture ownership stays with the approved Sender participant", () => {
  const source = fs.readFileSync(require.resolve("./qa-special-flow"), "utf8");
  assert.match(source, /special-v5:/);
  assert.match(source, /senderId: lists\.senders\[0\]/);
  assert.match(source, /ownerUid: lists\.senders\[0\]/);
  assert.match(source, /"verify_receiver_pin"/);
});

test("Activity certification fixture is server-owned and side-effect suppressed", () => {
  const source = fs.readFileSync(require.resolve("./qa-special-flow"), "utf8");
  assert.match(source, /activity_seed/);
  assert.match(source, /activity_insert/);
  assert.match(source, /activity_delete_reference/);
  assert.match(source, /qaActivityFixture: true/);
  assert.match(source, /excludeFromSettlement: true/);
  assert.match(source, /excludeFromPayout: true/);
  assert.match(source, /excludeFromAnalytics: true/);
  assert.match(source, /excludeFromCustomerNotifications: true/);
  assert.match(source, /activityNotificationsDeleted/);
  assert.match(source, /activity_pagination_seed/);
  assert.match(source, /wallet_notification_seed/);
  assert.match(source, /chat_retry_probe/);
  assert.match(source, /cancellation_quote_probe/);
  assert.match(source, /topLevelDeleted/);
});

test("archived QA cycles can use a new bounded request without reusing an old fixture", () => {
  const first = fixtureIdForRequest("qa-operator", "lifecycle_first");
  assert.equal(first, fixtureIdForRequest("qa-operator", "lifecycle_first"));
  assert.notEqual(first, fixtureIdForRequest("qa-operator", "lifecycle_second"));
  assert.notEqual(first, fixtureIdForRequest("other-operator", "lifecycle_first"));
  assert.equal(requiredFixtureId(first), first);
  assert.throws(() => fixtureIdForRequest("qa-operator", "../unsafe"), /bounded QA request ID/);
  assert.throws(() => requiredFixtureId("qaSpecialFlowFixtures/other"), /valid QA fixture ID/);
});

test("missing Firebase Auth or App Check never reaches QA handler", async () => {
  let calls = 0;
  await withServer(dependencies(async () => {
 calls += 1; return {ok: true};
}), async (base) => {
    assert.equal((await request(base, {omitAuth: true})).status, 401);
    assert.equal((await request(base, {omitAppCheck: true})).status, 400);
  });
  assert.equal(calls, 0);
});

test("valid QA attestation preserves callable envelope and context", async () => {
  const calls = [];
  await withServer(dependencies(async (data, context) => {
 calls.push({data, context}); return {fixture: true};
}), async (base) => {
    const response = await request(base);
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), {result: {fixture: true}});
  });
  assert.equal(calls.length, 1);
  assert.equal(calls[0].context.auth.uid, "qa-sender");
  assert.equal(calls[0].context.app.appId, "qa-web");
  assert.equal(calls[0].context.rawRequest.headers.authorization, "Bearer firebase-auth-token");
});

test("ordinary identity is denied by the canonical QA handler", async () => {
  await withServer(() => ({
    verifyIdToken: async () => ({uid: "ordinary-user"}),
    verifyAppCheck: async () => ({appId: "qa-web"}),
    handler: async () => {
 throw Object.assign(new Error("QA access is not permitted."), {code: "permission-denied"});
},
  }), async (base) => {
    const response = await request(base);
    assert.equal(response.status, 403);
    assert.equal((await response.json()).error.status, "PERMISSION_DENIED");
  });
});

test("internal errors do not expose provider or credential details", () => {
  assert.deepEqual(errorResponse(Object.assign(new Error("sk_live_secret"), {code: "internal"})), {
    status: 500, payload: {error: {status: "INTERNAL", message: "QA certification request failed."}}, code: "internal",
  });
});

test("provider-specific Auth and App Check failures remain fail-closed", () => {
  assert.deepEqual(errorResponse(Object.assign(new Error("bad app check"), {code: "app-check/invalid-token"})), {
    status: 400, payload: {error: {status: "FAILED_PRECONDITION", message: "bad app check"}}, code: "failed-precondition",
  });
  assert.deepEqual(errorResponse(Object.assign(new Error("bad auth"), {code: "auth/invalid-id-token"})), {
    status: 401, payload: {error: {status: "UNAUTHENTICATED", message: "bad auth"}}, code: "unauthenticated",
  });
});
