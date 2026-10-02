"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {once} = require("node:events");
const fs = require("node:fs");
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
        ...Object.fromEntries(["createSenderSetupIntent", "detachSenderPaymentMethod", "setDefaultSenderPaymentMethod", "saveSenderCheckoutPreference", "requestSenderWalletDebit", "redeemGiftCard"].map((name) => [name, handler(name)])),
        getSenderAccountActivity: {...handler("getSenderAccountActivity"), appCheckRequired: false},
        exportSenderData: {...handler("exportSenderData"), appCheckRequired: false},
        updateSenderPreferences: {...handler("updateSenderPreferences"), appCheckRequired: false},
        revokeSenderSessions: {...handler("revokeSenderSessions"), appCheckRequired: false},
        ensureSenderAccount: handler("ensureSenderAccount"),
        updateSenderNotificationState: handler("updateSenderNotificationState"),
        getSenderWallet: handler("getSenderWallet"),
        getSenderWalletTransactions: handler("getSenderWalletTransactions"),
        listSenderPaymentMethods: handler("listSenderPaymentMethods"),
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
  assert.equal(routeName("/v1/callable/updateSenderNotificationState"), "updateSenderNotificationState");
  assert.equal(routeName("/getSenderWallet"), "getSenderWallet");
  assert.equal(routeName("/getSenderWalletTransactions"), "getSenderWalletTransactions");
  assert.equal(routeName("/v1/callable/listSenderPaymentMethods"), "listSenderPaymentMethods");
  assert.equal(routeName("/v1/callable/updateRiderProfile"), "updateRiderProfile");
  assert.equal(routeName("/advanceRiderOnboarding"), "advanceRiderOnboarding");
  assert.equal(routeName("/submitRiderApplication"), "submitRiderApplication");
  assert.equal(routeName("/searchFreeUkAddresses"), null);
});

for (const name of ["createSenderSetupIntent", "detachSenderPaymentMethod", "setDefaultSenderPaymentMethod", "saveSenderCheckoutPreference", "requestSenderWalletDebit", "redeemGiftCard"]) {
  test(`${name} preserves Auth and App Check before delegating financial logic`, async () => {
    const deps = dependencies();
    await withServer(deps.factory, async (base) => {
      for (const headers of [{}, {authorization: "Bearer auth"}]) {
        const response = await fetch(`${base}/v1/callable/${name}`, {method: "POST", headers: {"content-type": "application/json", ...headers}, body: JSON.stringify({data: {fixture: true}})});
        assert.equal(response.status, headers.authorization ? 400 : 401);
        assert.equal(deps.calls.length, 0);
      }
      const response = await fetch(`${base}/v1/callable/${name}`, {method: "POST", headers: {"content-type": "application/json", authorization: "Bearer auth", "x-firebase-appcheck": "valid"}, body: JSON.stringify({data: {fixture: true}})});
      assert.equal(response.status, 200);
      assert.equal(deps.calls.length, 1);
      assert.equal(deps.calls[0].name, name);
      assert.equal(deps.calls[0].context.auth.uid, "user-1");
    });
  });
}

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

test("maps invalid Auth and App Check to safe messages", async () => {
  const authDeps = dependencies({
    verifyIdToken: async () => {
      throw Object.assign(new Error("raw token decoder detail"), {code: "auth/invalid-id-token"});
    },
  });
  await withServer(authDeps.factory, async (base) => {
    const response = await fetch(`${base}/updateSenderNotificationState`, {
      method: "POST",
      headers: {authorization: "Bearer invalid", "x-firebase-appcheck": "app", "content-type": "application/json"},
      body: JSON.stringify({data: {notificationId: "notification-1", action: "mark_read"}}),
    });
    assert.equal(response.status, 401);
    assert.deepEqual((await response.json()).error, {status: "UNAUTHENTICATED", message: "Sign in to continue."});
  });

  const appCheckDeps = dependencies({
    verifyAppCheck: async () => {
      throw Object.assign(new Error("raw App Check detail"), {code: "app-check/invalid-token"});
    },
  });
  await withServer(appCheckDeps.factory, async (base) => {
    const response = await fetch(`${base}/updateSenderNotificationState`, {
      method: "POST",
      headers: {authorization: "Bearer auth", "x-firebase-appcheck": "invalid", "content-type": "application/json"},
      body: JSON.stringify({data: {notificationId: "notification-1", action: "mark_read"}}),
    });
    assert.equal(response.status, 401);
    assert.deepEqual((await response.json()).error, {status: "UNAUTHENTICATED", message: "Sign in to continue."});
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

test("Sender notification state requires App Check and preserves the callable envelope", async () => {
  const deps = dependencies();
  await withServer(deps.factory, async (base) => {
    const missing = await fetch(`${base}/updateSenderNotificationState`, {
      method: "POST",
      headers: {authorization: "Bearer auth", "content-type": "application/json"},
      body: JSON.stringify({data: {notificationId: "notification-1", action: "mark_read"}}),
    });
    assert.equal(missing.status, 400);
    assert.equal((await missing.json()).error.status, "FAILED_PRECONDITION");

    const response = await fetch(`${base}/updateSenderNotificationState`, {
      method: "POST",
      headers: {authorization: "Bearer auth", "x-firebase-appcheck": "app", "content-type": "application/json"},
      body: JSON.stringify({data: {notificationId: "notification-1", action: "mark_read"}}),
    });
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), {result: {ok: true, name: "updateSenderNotificationState"}});
    assert.equal(deps.calls.at(-1).context.app.appId, "circum");
  });
});

test("Sender notification state maps not-found to a safe 404", async () => {
  const deps = dependencies({
    operations: {
      ...dependencies().factory().operations,
      updateSenderNotificationState: {
        appCheckRequired: true,
        handler: {
          run: async () => {
            throw Object.assign(new Error("hidden detail"), {code: "not-found"});
          },
        },
      },
    },
  });
  await withServer(deps.factory, async (base) => {
    const response = await fetch(`${base}/updateSenderNotificationState`, {
      method: "POST",
      headers: {authorization: "Bearer auth", "x-firebase-appcheck": "app", "content-type": "application/json"},
      body: JSON.stringify({data: {notificationId: "missing", action: "mark_read"}}),
    });
    assert.equal(response.status, 404);
    assert.equal((await response.json()).error.status, "NOT_FOUND");
  });
});

test("Sender wallet transactions require App Check and preserve the callable envelope", async () => {
  const deps = dependencies();
  await withServer(deps.factory, async (base) => {
    const missing = await fetch(`${base}/getSenderWalletTransactions`, {
      method: "POST",
      headers: {authorization: "Bearer auth", "content-type": "application/json"},
      body: JSON.stringify({data: {pageSize: 20, pageToken: null}}),
    });
    assert.equal(missing.status, 400);
    assert.equal((await missing.json()).error.status, "FAILED_PRECONDITION");

    const response = await fetch(`${base}/v1/callable/getSenderWalletTransactions`, {
      method: "POST",
      headers: {authorization: "Bearer auth", "x-firebase-appcheck": "app", "content-type": "application/json"},
      body: JSON.stringify({data: {pageSize: 20, pageToken: null}}),
    });
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), {result: {ok: true, name: "getSenderWalletTransactions"}});
    assert.equal(deps.calls.at(-1).context.auth.uid, "user-1");
    assert.equal(deps.calls.at(-1).context.app.appId, "circum");
  });
});

test("Sender Wallet balance and payment-method routes require App Check", async () => {
  const deps = dependencies();
  await withServer(deps.factory, async (base) => {
    for (const route of ["getSenderWallet", "listSenderPaymentMethods"]) {
      const missing = await fetch(`${base}/${route}`, {
        method: "POST",
        headers: {authorization: "Bearer auth", "content-type": "application/json"},
        body: JSON.stringify({data: {}}),
      });
      assert.equal(missing.status, 400);
      assert.equal((await missing.json()).error.status, "FAILED_PRECONDITION");

      const response = await fetch(`${base}/${route}`, {
        method: "POST",
        headers: {authorization: "Bearer auth", "x-firebase-appcheck": "app", "content-type": "application/json"},
        body: JSON.stringify({data: {}}),
      });
      assert.equal(response.status, 200);
      assert.deepEqual(await response.json(), {result: {ok: true, name: route}});
    }
  });
});

test("Sender Wallet balance adapter passes callable context to the reader", () => {
  const source = fs.readFileSync(require.resolve("./cloud-run-account-bootstrap"), "utf8");
  assert.match(source, /getSenderWallet: \{handler: \{run: \(_data, context\) => rothLedger\.readSenderWallet\(context\)\}/);
});

test("account routes map conflicts to a safe 409", async () => {
  const base = dependencies();
  const deps = dependencies({
    operations: {
      ...base.factory().operations,
      updateSenderNotificationState: {
        appCheckRequired: true,
        handler: {
          run: async () => {
            throw Object.assign(new Error("hidden detail"), {code: "already-exists"});
          },
        },
      },
    },
  });
  await withServer(deps.factory, async (serverBase) => {
    const response = await fetch(`${serverBase}/updateSenderNotificationState`, {
      method: "POST",
      headers: {authorization: "Bearer auth", "x-firebase-appcheck": "app", "content-type": "application/json"},
      body: JSON.stringify({data: {notificationId: "notification-1", action: "mark_read"}}),
    });
    assert.equal(response.status, 409);
    assert.equal((await response.json()).error.status, "ALREADY_EXISTS");
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

for (const name of ["getSenderAccountActivity", "exportSenderData", "updateSenderPreferences", "revokeSenderSessions"]) {
  test(`${name} preserves the installed Sender callable envelope and auth policy`, async () => {
    const deps = dependencies();
    await withServer(deps.factory, async (base) => {
      const payload = {scope: "all_other_devices", preferences: {language: "en"}};
      const denied = await fetch(`${base}/${name}`, {
        method: "POST", headers: {"content-type": "application/json"}, body: JSON.stringify({data: payload}),
      });
      assert.equal(denied.status, 401);
      assert.equal(deps.calls.length, 0);
      const response = await fetch(`${base}/v1/callable/${name}`, {
        method: "POST", headers: {authorization: "Bearer valid", "content-type": "application/json"}, body: JSON.stringify({data: payload}),
      });
      assert.equal(response.status, 200);
      assert.deepEqual(await response.json(), {result: {ok: true, name}});
      assert.deepEqual(deps.calls[0].data, payload);
      assert.equal(deps.calls[0].context.auth.uid, "user-1");
    });
  });
}

for (const name of ["getSenderAccountActivity", "exportSenderData", "verifyRiderAccountAccess"]) {
  test(`${name} accepts the installed SDK's no-argument data:null envelope`, async () => {
    const deps = dependencies();
    await withServer(deps.factory, async (base) => {
      const headers = {authorization: "Bearer valid", "content-type": "application/json", "x-firebase-appcheck": "app"};
      const response = await fetch(`${base}/${name}`, {method: "POST", headers, body: JSON.stringify({data: null})});
      assert.equal(response.status, 200);
      assert.deepEqual(await response.json(), {result: {ok: true, name}});
      assert.deepEqual(deps.calls[0].data, {});
      assert.equal(deps.calls[0].context.auth.uid, "user-1");
      const missing = await fetch(`${base}/${name}`, {method: "POST", headers, body: "{}"});
      assert.equal(missing.status, 400);
      const unauthenticated = await fetch(`${base}/${name}`, {method: "POST", headers: {"content-type": "application/json"}, body: JSON.stringify({data: null})});
      assert.equal(unauthenticated.status, 401);
      assert.equal(deps.calls.length, 1);
    });
  });
}

test("no-argument read compatibility does not change mutation envelope validation", async () => {
  const deps = dependencies();
  await withServer(deps.factory, async (base) => {
    for (const name of ["updateSenderPreferences", "revokeSenderSessions"]) {
      const response = await fetch(`${base}/${name}`, {
        method: "POST", headers: {authorization: "Bearer valid", "content-type": "application/json"}, body: JSON.stringify({data: null}),
      });
      assert.equal(response.status, 400);
    }
    assert.equal(deps.calls.length, 0);
  });
});
