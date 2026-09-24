"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {once} = require("node:events");
const adminAuthority = require("./admin-operations-authority");
const {createServer, errorResponse, routeName} = require("./cloud-run-admin-access");

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

function request(base, options = {}) {
  const headers = {
    authorization: "Bearer auth-token",
    "x-firebase-appcheck": "app-check-token",
    "content-type": "application/json",
    ...(options.headers || {}),
  };
  if (options.omitAuth) delete headers.authorization;
  if (options.omitAppCheck) delete headers["x-firebase-appcheck"];
  return fetch(`${base}/adminResolveAccess`, {
    method: "POST",
    headers,
    body: options.body === undefined ? JSON.stringify({data: {}}) : options.body,
  });
}

function dependencies(handler, overrides = {}) {
  return () => ({
    verifyIdToken: async (token) => {
      if (token !== "auth-token") throw Object.assign(new Error("bad auth"), {code: "auth/invalid-id-token"});
      return {uid: "admin-uid", email: "admin@example.invalid", super_admin: true};
    },
    verifyAppCheck: async (token) => {
      if (token !== "app-check-token") throw Object.assign(new Error("bad app check"), {code: "app-check/invalid-token"});
      return {appId: "circum-admin"};
    },
    handler,
    ...overrides,
  });
}

test("Admin route accepts both direct and callable-compatible paths", () => {
  assert.equal(routeName("/adminResolveAccess"), "adminResolveAccess");
  assert.equal(routeName("/v1/callable/adminResolveAccess"), "adminResolveAccess");
  assert.equal(routeName("/admin-query-page"), null);
});

test("health is lazy, reports Node 22 and source SHA", async () => {
  const previous = process.env.CIRCUM_SOURCE_SHA;
  process.env.CIRCUM_SOURCE_SHA = "test-admin-sha";
  await withServer(() => {
    throw new Error("health must not initialize Firebase");
  }, async (base) => {
    const response = await fetch(`${base}/health`);
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), {
      status: "ok",
      runtime: "node22",
      service: "circum-admin-access",
      source: "test-admin-sha",
    });
  });
  if (previous === undefined) delete process.env.CIRCUM_SOURCE_SHA;
  else process.env.CIRCUM_SOURCE_SHA = previous;
});

test("unauthenticated and missing App Check requests never reach the handler", async () => {
  let calls = 0;
  await withServer(dependencies(async () => {
    calls += 1;
    return {accessGranted: true};
  }), async (base) => {
    let response = await request(base, {omitAuth: true});
    assert.equal(response.status, 401);
    assert.equal((await response.json()).error.status, "UNAUTHENTICATED");
    response = await request(base, {omitAppCheck: true});
    assert.equal(response.status, 400);
    assert.equal((await response.json()).error.status, "FAILED_PRECONDITION");
  });
  assert.equal(calls, 0);
});

test("malformed callable envelope is rejected before authority execution", async () => {
  let calls = 0;
  await withServer(dependencies(async () => {
    calls += 1;
    return {accessGranted: true};
  }), async (base) => {
    const response = await request(base, {body: JSON.stringify({})});
    assert.equal(response.status, 400);
    assert.equal((await response.json()).error.status, "INVALID_ARGUMENT");
  });
  assert.equal(calls, 0);
});

test("authorized super_admin preserves the callable result envelope and context", async () => {
  const calls = [];
  await withServer(dependencies(async (data, context) => {
    calls.push({data, context});
    return {roles: ["super_admin"], permissions: ["*"], accessGranted: true};
  }), async (base) => {
    const response = await request(base);
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), {
      result: {roles: ["super_admin"], permissions: ["*"], accessGranted: true},
    });
  });
  assert.equal(calls.length, 1);
  assert.deepEqual(calls[0].data, {});
  assert.equal(calls[0].context.auth.uid, "admin-uid");
  assert.equal(calls[0].context.app.appId, "circum-admin");
});

test("missing or inactive roles do not synthesize privilege or write records", async () => {
  const writes = [];
  const db = {
    collection: () => ({
      doc: () => ({
        get: async () => ({exists: true, data: () => ({status: "inactive", role: "super_admin"})}),
        set: async (data) => writes.push(data),
      }),
    }),
  };
  const result = await adminAuthority._private.resolveAdminAccess({}, {
    auth: {uid: "inactive-uid", token: {email: "inactive@example.invalid"}},
  }, {db});
  assert.deepEqual(result, {roles: [], permissions: [], accessGranted: false});
  assert.equal(writes.length, 0);
});

test("canonical authority resolves an existing super_admin without changing role data", async () => {
  const writes = [];
  const db = {
    collection: () => ({
      doc: (id) => ({
        get: async () => ({exists: id === "admin-uid", data: () => ({status: "active", role: "super_admin"})}),
        set: async (data, options) => writes.push({id, data, options}),
      }),
    }),
  };
  const result = await adminAuthority._private.resolveAdminAccess({}, {
    auth: {uid: "admin-uid", token: {email: "admin@example.invalid", super_admin: true}},
  }, {db});
  assert.deepEqual(result, {roles: ["super_admin"], permissions: ["*"], accessGranted: true});
  assert.equal(writes.length, 2);
  assert.deepEqual(writes.map((write) => write.id), ["admin-uid", "admin@example.invalid"]);
  assert.ok(writes.every((write) => Object.keys(write.data).length === 1 && write.data.lastLoginAt));
  assert.deepEqual(writes.map((write) => write.options), [{merge: true}, {merge: true}]);
});

test("permission and service failures remain safe status classes", async () => {
  assert.deepEqual(errorResponse(Object.assign(new Error("private"), {code: "permission-denied"})), {
    status: 403,
    payload: {error: {status: "PERMISSION_DENIED", message: "private"}},
    code: "permission-denied",
  });
  const failure = errorResponse(Object.assign(new Error("database details"), {code: "internal"}));
  assert.equal(failure.status, 500);
  assert.deepEqual(failure.payload, {error: {status: "INTERNAL", message: "Admin access request failed."}});
  assert.notEqual(failure.payload.error.message, "database details");
});
