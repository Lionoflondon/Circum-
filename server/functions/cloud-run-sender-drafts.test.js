"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {once} = require("node:events");
const {createServer, routeName} = require("./cloud-run-sender-drafts");

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
  const operations = Object.fromEntries(["saveSenderDraft", "loadSenderDraft", "deleteSenderDraft"].map((name) => [name, {
    run: async (data, context) => {
      calls.push({name, data, context});
      return {ok: true, name};
    },
  }]));
  return {
    calls,
    factory: () => ({
      verifyIdToken: async () => ({uid: "sender-1", email: "sender@example.invalid"}),
      verifyAppCheck: async () => ({appId: "circum"}),
      operations,
      ...overrides,
    }),
  };
}

test("routes only Sender draft operations", () => {
  assert.equal(routeName("/saveSenderDraft"), "saveSenderDraft");
  assert.equal(routeName("/v1/callable/loadSenderDraft"), "loadSenderDraft");
  assert.equal(routeName("/deleteSenderDraft"), "deleteSenderDraft");
  assert.equal(routeName("/ensureSenderAccount"), null);
});

test("health reports the service contract without invoking a draft", async () => {
  await withServer(() => ({}), async (base) => {
    const response = await fetch(`${base}/health`);
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), {
      status: "ok",
      runtime: "node22",
      source: "unknown",
      operations: ["saveSenderDraft", "loadSenderDraft", "deleteSenderDraft"],
    });
  });
});

test("rejects missing Auth and App Check", async () => {
  const deps = dependencies();
  await withServer(deps.factory, async (base) => {
    const unauthenticated = await fetch(`${base}/saveSenderDraft`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({data: {}}),
    });
    assert.equal(unauthenticated.status, 401);
    assert.equal((await unauthenticated.json()).error.status, "UNAUTHENTICATED");

    const missingAppCheck = await fetch(`${base}/saveSenderDraft`, {
      method: "POST",
      headers: {authorization: "Bearer auth", "content-type": "application/json"},
      body: JSON.stringify({data: {}}),
    });
    assert.equal(missingAppCheck.status, 400);
    assert.equal((await missingAppCheck.json()).error.status, "FAILED_PRECONDITION");
    assert.equal(deps.calls.length, 0);
  });
});

test("preserves the callable envelope and verified identity", async () => {
  const deps = dependencies();
  await withServer(deps.factory, async (base) => {
    const response = await fetch(`${base}/saveSenderDraft`, {
      method: "POST",
      headers: {
        authorization: "Bearer auth",
        "x-firebase-appcheck": "app",
        "content-type": "application/json",
      },
      body: JSON.stringify({data: {schemaVersion: 1, draft: {step: "pickup"}}}),
    });
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), {result: {ok: true, name: "saveSenderDraft"}});
    assert.equal(deps.calls[0].context.auth.uid, "sender-1");
    assert.equal(deps.calls[0].context.app.appId, "circum");
  });
});

test("maps invalid App Check and stale draft conflicts safely", async () => {
  const deps = dependencies({
    verifyAppCheck: async () => {
      throw Object.assign(new Error("bad app"), {code: "app-check/invalid-token"});
    },
  });
  await withServer(deps.factory, async (base) => {
    const invalidAppCheck = await fetch(`${base}/saveSenderDraft`, {
      method: "POST",
      headers: {
        authorization: "Bearer auth",
        "x-firebase-appcheck": "bad-app",
        "content-type": "application/json",
      },
      body: JSON.stringify({data: {}}),
    });
    assert.equal(invalidAppCheck.status, 401);
    assert.equal((await invalidAppCheck.json()).error.status, "UNAUTHENTICATED");
  });

  const conflictDeps = dependencies({
    operations: {
      saveSenderDraft: {
        run: async () => {
          throw Object.assign(new Error("Your draft was updated on another device."), {code: "aborted"});
        },
      },
      loadSenderDraft: {run: async () => ({exists: false})},
      deleteSenderDraft: {run: async () => ({ok: true})},
    },
  });
  await withServer(conflictDeps.factory, async (base) => {
    const response = await fetch(`${base}/saveSenderDraft`, {
      method: "POST",
      headers: {
        authorization: "Bearer auth",
        "x-firebase-appcheck": "app",
        "content-type": "application/json",
      },
      body: JSON.stringify({data: {baseRevision: 0}}),
    });
    assert.equal(response.status, 409);
    assert.equal((await response.json()).error.status, "ABORTED");
  });
});

for (const operation of ["saveSenderDraft", "loadSenderDraft", "deleteSenderDraft"]) {
  test(`${operation} legacy SDK route verifies Auth and uses the same canonical draft core while primary App Check remains required`, async () => {
    const deps = dependencies();
    await withServer(deps.factory, async (base) => {
      const invoke = (name, auth, data) => fetch(`${base}/${name}`, {method: "POST", headers: {"content-type": "application/json", ...(auth ? {authorization: "Bearer valid"} : {})}, body: JSON.stringify({data})});
      assert.equal((await invoke(operation + "Legacy", false, {})).status, 401);
      assert.equal(deps.calls.length, 0);
      assert.equal((await invoke(operation, true, {})).status, 400);
      assert.equal(deps.calls.length, 0);
      const allowed = await invoke(operation + "Legacy", true, operation === "saveSenderDraft" ? {draft: {}} : null);
      assert.equal(allowed.status, 200);
      assert.equal(deps.calls[0].name, operation);
      assert.equal(deps.calls[0].context.auth.uid, "sender-1");
      assert.equal(deps.calls[0].context.app, null);
      assert.equal((await invoke("saveSenderDraftLegacy", true, null)).status, 400);
      assert.equal(deps.calls.length, 1);
    });
  });
}
