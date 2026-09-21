"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {createHandlers, createServer} = require("./cloud-run-token-callables");

async function listen(server, run) {
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  try {
    await run(`http://127.0.0.1:${server.address().port}`);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}

function fakeDb() {
  const writes = [];
  return {
    writes,
    collection: (collection) => ({doc: () => ({set: async (data) => writes.push({collection, data})})}),
  };
}

function senderAccountDb({user = null, riderExists = false, adminExists = false} = {}) {
  const writes = [];
  const snapshots = new Map([
    ["users/sender-1", {exists: user !== null, data: () => user || {}}],
    ["riderProfiles/sender-1", {exists: riderExists, data: () => ({})}],
    ["adminUsers/sender-1", {exists: adminExists, data: () => ({})}],
  ]);
  const db = {
    writes,
    collection: (collection) => ({
      doc: (id = "generated") => ({
        path: `${collection}/${id}`,
        set: async (data, options) => writes.push({path: `${collection}/${id}`, data, options}),
      }),
    }),
    runTransaction: async (run) => run({
      get: async (ref) => snapshots.get(ref.path) || {exists: false, data: () => ({})},
      set: (ref, data, options) => writes.push({path: ref.path, data, options}),
    }),
  };
  return db;
}

test("ensureSenderAccount preserves bootstrap semantics without trusting client identity", async () => {
  const db = senderAccountDb();
  const grants = [];
  const handlers = createHandlers({
    db,
    serverTimestamp: () => "server-time",
    grantSenderWelcomeRoth: async (entry) => {
      grants.push(entry);
      return {amount: 5, transactionId: "welcome-1"};
    },
  });
  const result = await handlers.ensureSenderAccount(
      {uid: "attacker-controlled"},
      {auth: {uid: "sender-1", token: {email: "sender@example.invalid"}}},
  );
  assert.deepEqual(result, {
    ok: true,
    allowed: true,
    roles: ["sender"],
    action: "created_sender_profile",
    profile: {phone: "", displayName: ""},
    starterRothGranted: true,
    starterRothAmount: 5,
    starterRothTransactionId: "welcome-1",
  });
  assert.equal(db.writes[0].path, "users/sender-1");
  assert.equal(db.writes[0].data.email, "sender@example.invalid");
  assert.equal(db.writes[1].path, "senderProfileEvents/generated");
  assert.deepEqual(grants, [{uid: "sender-1", email: "sender@example.invalid", source: "ensureSenderAccount"}]);
});

test("ensureSenderAccount rejects a conflicting Rider identity without writes", async () => {
  const db = senderAccountDb({riderExists: true});
  const handlers = createHandlers({db, serverTimestamp: () => "server-time"});
  const result = await handlers.ensureSenderAccount({}, {auth: {uid: "sender-1", token: {}}});
  assert.deepEqual(result, {
    ok: true,
    allowed: false,
    roles: [],
    action: "blocked_conflicting_role",
  });
  assert.deepEqual(db.writes, []);
});

test("handlers register canonical sender and rider ownership and write audits", async () => {
  const db = fakeDb();
  const registrations = [];
  const handlers = createHandlers({
    db,
    registerProfileToken: async (entry) => registrations.push(entry),
    serverTimestamp: () => "server-time",
  });
  assert.deepEqual(await handlers.updateSenderPushToken({fcmToken: " sender-token "}, {auth: {uid: "sender-1", token: {email: "sender@example.invalid"}}}), {ok: true});
  assert.deepEqual(await handlers.updateRiderPushToken({fcmToken: " rider-token "}, {auth: {uid: "rider-1", token: {email: "rider@example.invalid"}}}), {ok: true});
  assert.deepEqual(registrations.map(({uid, role, token}) => ({uid, role, token})), [
    {uid: "sender-1", role: "sender", token: "sender-token"},
    {uid: "rider-1", role: "rider", token: "rider-token"},
  ]);
  assert.equal(registrations[0].db, db);
  assert.deepEqual(db.writes.map(({collection}) => collection), ["senderProfileEvents", "riderOnboardingEvents"]);
  assert.equal(db.writes[0].data.uid, "sender-1");
  assert.equal(db.writes[1].data.riderId, "rider-1");
});

test("callable transport rejects missing auth and requires Rider App Check", async () => {
  const calls = [];
  const server = createServer({dependenciesFactory: () => ({
    verifyIdToken: async (token) => token === "valid-id" ? {uid: "verified-uid", email: "verified@example.invalid"} : Promise.reject(Object.assign(new Error("Bad ID token."), {code: "auth/invalid-id-token"})),
    verifyAppCheck: async (token) => token === "valid-app" ? {appId: "app-1"} : Promise.reject(Object.assign(new Error("Bad App Check token."), {code: "app-check/invalid-argument"})),
    handlers: {
      ensureSenderAccount: async (_data, context) => (calls.push(["ensure", context.auth.uid]), {ok: true, allowed: true}),
      updateSenderPushToken: async (_data, context) => (calls.push(["sender", context.auth.uid]), {ok: true}),
      updateRiderPushToken: async (_data, context) => (calls.push(["rider", context.auth.uid]), {ok: true}),
      sendRiderUpdate: async () => {
        throw Object.assign(new Error("Legacy direct-token Rider notifications are disabled. Use an authorised server-owned notification path."), {code: "failed-precondition"});
      },
    },
  })});
  await listen(server, async (url) => {
    let response = await fetch(`${url}/updateSenderPushToken`, {method: "POST", headers: {"content-type": "application/json"}, body: JSON.stringify({data: {fcmToken: "token"}})});
    assert.equal(response.status, 401);
    response = await fetch(`${url}/ensureSenderAccount`, {method: "POST", headers: {authorization: "Bearer valid-id", "content-type": "application/json"}, body: JSON.stringify({data: {uid: "ignored"}})});
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), {result: {ok: true, allowed: true}});
    response = await fetch(`${url}/updateRiderPushToken`, {method: "POST", headers: {authorization: "Bearer valid-id", "content-type": "application/json"}, body: JSON.stringify({data: {fcmToken: "token"}})});
    assert.equal(response.status, 400);
    assert.equal((await response.json()).error.status, "FAILED_PRECONDITION");
    response = await fetch(`${url}/updateRiderPushToken`, {method: "POST", headers: {authorization: "Bearer valid-id", "x-firebase-appcheck": "valid-app", "content-type": "application/json"}, body: JSON.stringify({data: {fcmToken: "token"}})});
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), {result: {ok: true}});
    assert.deepEqual(calls, [["ensure", "verified-uid"], ["rider", "verified-uid"]]);
  });
});

test("sendRiderUpdate remains authenticated and permanently disabled", async () => {
  const handlers = createHandlers({db: fakeDb()});
  const server = createServer({dependenciesFactory: () => ({
    verifyIdToken: async () => ({uid: "verified-uid"}),
    verifyAppCheck: async () => ({appId: "unused"}),
    handlers,
  })});
  await listen(server, async (url) => {
    let response = await fetch(`${url}/sendRiderUpdate`, {method: "POST", headers: {"content-type": "application/json"}, body: JSON.stringify({data: {token: "must-never-send"}})});
    assert.equal(response.status, 401);
    response = await fetch(`${url}/sendRiderUpdate`, {method: "POST", headers: {authorization: "Bearer valid-id", "content-type": "application/json"}, body: JSON.stringify({data: {token: "must-never-send"}})});
    assert.equal(response.status, 400);
    assert.deepEqual(await response.json(), {error: {status: "FAILED_PRECONDITION", message: "Legacy direct-token Rider notifications are disabled. Use an authorised server-owned notification path."}});
  });
});

test("health starts without Firebase access and reports source SHA", async () => {
  const previous = process.env.CIRCUM_SOURCE_SHA;
  process.env.CIRCUM_SOURCE_SHA = "test-sha";
  const server = createServer({dependenciesFactory: () => {
    throw new Error("health must stay lazy");
  }});
  await listen(server, async (url) => {
    const response = await fetch(`${url}/health`);
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), {status: "ok", runtime: "node22", source: "test-sha"});
  });
  if (previous === undefined) delete process.env.CIRCUM_SOURCE_SHA;
  else process.env.CIRCUM_SOURCE_SHA = previous;
});
