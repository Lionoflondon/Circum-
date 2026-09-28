"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {once} = require("node:events");
const {createServer, routeName, statusFor} = require("./cloud-run-sender-booking-quotes");

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
  const operations = {
    createSenderBookingQuote: {
      run: async (data, context) => {
        calls.push({data, context});
        return {quoteId: data.quoteId, total: 12.5, currency: "GBP"};
      },
    },
  };
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

test("routes only the Sender booking quote operation", () => {
  assert.equal(routeName("/createSenderBookingQuote"), "createSenderBookingQuote");
  assert.equal(routeName("/v1/callable/createSenderBookingQuote"), "createSenderBookingQuote");
  assert.equal(routeName("/createSenderPaymentSession"), null);
});

test("health reports the quote authority without invoking pricing", async () => {
  await withServer(() => ({}), async (base) => {
    const response = await fetch(`${base}/health`);
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), {
      status: "ok",
      runtime: "node22",
      source: "unknown",
      operations: ["createSenderBookingQuote"],
    });
  });
});

test("rejects missing or invalid Auth and App Check before invoking quote", async () => {
  const deps = dependencies({
    verifyAppCheck: async () => {
      throw Object.assign(new Error("bad app"), {code: "app-check/invalid-token"});
    },
  });
  await withServer(deps.factory, async (base) => {
    const missingAuth = await fetch(`${base}/createSenderBookingQuote`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({data: {quoteId: "q1"}}),
    });
    assert.equal(missingAuth.status, 401);

    const invalidAppCheck = await fetch(`${base}/createSenderBookingQuote`, {
      method: "POST",
      headers: {
        authorization: "Bearer auth",
        "x-firebase-appcheck": "bad-app",
        "content-type": "application/json",
      },
      body: JSON.stringify({data: {quoteId: "q1"}}),
    });
    assert.equal(invalidAppCheck.status, 401);
    assert.equal((await invalidAppCheck.json()).error.status, "UNAUTHENTICATED");
    assert.equal(deps.calls.length, 0);
  });
});

test("preserves callable envelope and verified identity", async () => {
  const deps = dependencies();
  await withServer(deps.factory, async (base) => {
    const response = await fetch(`${base}/createSenderBookingQuote`, {
      method: "POST",
      headers: {
        authorization: "Bearer auth",
        "x-firebase-appcheck": "app",
        "content-type": "application/json",
        "x-circum-correlation-id": "qa-quote-1",
      },
      body: JSON.stringify({data: {quoteId: "q1", selectedSpeed: "Standard"}}),
    });
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), {
      result: {quoteId: "q1", total: 12.5, currency: "GBP"},
    });
    assert.equal(deps.calls[0].context.auth.uid, "sender-1");
    assert.equal(deps.calls[0].context.app.appId, "circum");
  });
});

test("maps quote failure classes to safe HTTP outcomes", () => {
  assert.equal(statusFor("unauthenticated"), 401);
  assert.equal(statusFor("permission-denied"), 403);
  assert.equal(statusFor("already-exists"), 409);
  assert.equal(statusFor("resource-exhausted"), 429);
  assert.equal(statusFor("unavailable"), 503);
  assert.equal(statusFor("internal"), 500);
});
