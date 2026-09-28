"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {once} = require("node:events");
const {createServer, routeName} = require("./cloud-run-account-bootstrap");

async function withServer(dependenciesFactory, run) {
  const server = createServer({dependenciesFactory});
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  try {
    await run(`http://127.0.0.1:${server.address().port}`);
  } finally {
    server.close();
    await once(server, "close");
  }
}

function dependencies(overrides = {}) {
  const calls = [];
  const handler = (name) => ({
    appCheckRequired: name !== "ensureSenderAccount",
    handler: {run: async (data, context) => {
      calls.push({name, data, context});
      return {ok: true, name};
    }},
  });
  return {
    calls,
    factory: () => ({
      verifyIdToken: async () => ({uid: "user-1", email: "safe@example.invalid"}),
      verifyAppCheck: async () => ({appId: "circum"}),
      operations: {
        ensureSenderAccount: handler("ensureSenderAccount"),
        updateSenderProfile: handler("updateSenderProfile"),
        updateSenderProfilePhoto: handler("updateSenderProfilePhoto"),
        updateSenderPreferences: handler("updateSenderPreferences"),
        revokeSenderSessions: handler("revokeSenderSessions"),
        getSenderAccountActivity: handler("getSenderAccountActivity"),
        exportSenderData: handler("exportSenderData"),
        requestSenderEmailChange: handler("requestSenderEmailChange"),
        closeCircumAccount: handler("closeCircumAccount"),
        verifyRiderAccountAccess: handler("verifyRiderAccountAccess"),
        advanceRiderOnboarding: handler("advanceRiderOnboarding"),
        updateRiderProfile: handler("updateRiderProfile"),
        submitRiderApplication: handler("submitRiderApplication"),
      },
      ...overrides,
    }),
  };
}

test("routes only the supported account operations", () => {
  assert.equal(routeName("/ensureSenderAccount"), "ensureSenderAccount");
  assert.equal(routeName("/v1/callable/updateRiderProfile"), "updateRiderProfile");
  assert.equal(routeName("/advanceRiderOnboarding"), "advanceRiderOnboarding");
  assert.equal(routeName("/submitRiderApplication"), "submitRiderApplication");
  assert.equal(routeName("/updateSenderPreferences"), "updateSenderPreferences");
  assert.equal(routeName("/closeCircumAccount"), "closeCircumAccount");
  assert.equal(routeName("/searchFreeUkAddresses"), null);
});

test("rejects unauthenticated callers", async () => {
  const deps = dependencies();
  await withServer(deps.factory, async (base) => {
    const response = await fetch(`${base}/ensureSenderAccount`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({data: {}}),
    });
    assert.equal(response.status, 401);
    assert.equal((await response.json()).error.status, "UNAUTHENTICATED");
  });
});

test("preserves callable envelope and auth context", async () => {
  const deps = dependencies();
  await withServer(deps.factory, async (base) => {
    const response = await fetch(`${base}/ensureSenderAccount`, {
      method: "POST",
      headers: {authorization: "Bearer auth", "content-type": "application/json"},
      body: JSON.stringify({data: {}}),
    });
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), {result: {ok: true, name: "ensureSenderAccount"}});
    assert.equal(deps.calls[0].context.auth.uid, "user-1");
  });
});

test("Rider operations require App Check", async () => {
  const deps = dependencies();
  await withServer(deps.factory, async (base) => {
    const response = await fetch(`${base}/verifyRiderAccountAccess`, {
      method: "POST",
      headers: {authorization: "Bearer auth", "content-type": "application/json"},
      body: JSON.stringify({data: {}}),
    });
    assert.equal(response.status, 400);
    assert.equal((await response.json()).error.status, "FAILED_PRECONDITION");
  });
});

test("Sender profile operations require App Check", async () => {
  const deps = dependencies();
  await withServer(deps.factory, async (base) => {
    const response = await fetch(`${base}/updateSenderPreferences`, {
      method: "POST",
      headers: {authorization: "Bearer auth", "content-type": "application/json"},
      body: JSON.stringify({data: {language: "en"}}),
    });
    assert.equal(response.status, 400);
    assert.equal((await response.json()).error.status, "FAILED_PRECONDITION");
    assert.equal(deps.calls.length, 0);
  });
});

test("Sender profile operations preserve verified Auth and App Check", async () => {
  const deps = dependencies();
  await withServer(deps.factory, async (base) => {
    const response = await fetch(`${base}/updateSenderPreferences`, {
      method: "POST",
      headers: {authorization: "Bearer auth", "x-firebase-appcheck": "app", "content-type": "application/json"},
      body: JSON.stringify({data: {language: "en"}}),
    });
    assert.equal(response.status, 200);
    assert.equal(deps.calls[0].name, "updateSenderPreferences");
    assert.equal(deps.calls[0].context.auth.uid, "user-1");
    assert.equal(deps.calls[0].context.app.appId, "circum");
  });
});

test("Rider operation accepts verified Auth and App Check", async () => {
  const deps = dependencies();
  await withServer(deps.factory, async (base) => {
    const response = await fetch(`${base}/updateRiderProfile`, {
      method: "POST",
      headers: {authorization: "Bearer auth", "x-firebase-appcheck": "app", "content-type": "application/json"},
      body: JSON.stringify({data: {section: "personal_details"}}),
    });
    assert.equal(response.status, 200);
    assert.equal(deps.calls[0].context.app.appId, "circum");
  });
});

test("Rider onboarding invokes the canonical callable with verified identity", async () => {
  const deps = dependencies();
  await withServer(deps.factory, async (base) => {
    const response = await fetch(`${base}/advanceRiderOnboarding`, {
      method: "POST",
      headers: {authorization: "Bearer auth", "x-firebase-appcheck": "app", "content-type": "application/json"},
      body: JSON.stringify({data: {stage: "profile_started", name: "Rider"}}),
    });
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), {result: {ok: true, name: "advanceRiderOnboarding"}});
    assert.equal(deps.calls[0].context.auth.uid, "user-1");
    assert.equal(deps.calls[0].context.app.appId, "circum");
  });
});

test("Rider application submission invokes the canonical callable with verified identity", async () => {
  const deps = dependencies();
  await withServer(deps.factory, async (base) => {
    const response = await fetch(`${base}/submitRiderApplication`, {
      method: "POST",
      headers: {authorization: "Bearer auth", "x-firebase-appcheck": "app", "content-type": "application/json"},
      body: JSON.stringify({data: {idempotencyKey: "rider-application-test"}}),
    });
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), {result: {ok: true, name: "submitRiderApplication"}});
    assert.equal(deps.calls[0].name, "submitRiderApplication");
    assert.equal(deps.calls[0].context.auth.uid, "user-1");
    assert.equal(deps.calls[0].context.app.appId, "circum");
  });
});

test("Rider application submission rejects unauthenticated callers", async () => {
  const deps = dependencies();
  await withServer(deps.factory, async (base) => {
    const response = await fetch(`${base}/submitRiderApplication`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({data: {idempotencyKey: "rider-application-test"}}),
    });
    assert.equal(response.status, 401);
    assert.equal((await response.json()).error.status, "UNAUTHENTICATED");
    assert.equal(deps.calls.length, 0);
  });
});

test("Rider application submission rejects invalid App Check before invoking the callable", async () => {
  const deps = dependencies({
    verifyAppCheck: async () => {
      throw Object.assign(new Error("bad app"), {code: "app-check/invalid-token"});
    },
  });
  await withServer(deps.factory, async (base) => {
    const response = await fetch(`${base}/submitRiderApplication`, {
      method: "POST",
      headers: {authorization: "Bearer auth", "x-firebase-appcheck": "bad-app", "content-type": "application/json"},
      body: JSON.stringify({data: {idempotencyKey: "rider-application-test"}}),
    });
    assert.equal(response.status, 401);
    assert.equal((await response.json()).error.status, "UNAUTHENTICATED");
    assert.equal(deps.calls.length, 0);
  });
});
