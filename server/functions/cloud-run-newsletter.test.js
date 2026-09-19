"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {createServer, PUBLIC, ADMIN, routeName} = require("./cloud-run-newsletter");

async function listen(server, run) {
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  try {
    await run(`http://127.0.0.1:${server.address().port}`);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}

function fixture() {
  const calls = [];
  const handlers = Object.fromEntries([...PUBLIC, ...ADMIN].map((name) => [name, {run: async (data, context) => {
    calls.push({name, data, context});
    return {ok: true, name};
  }}]));
  const server = createServer({dependenciesFactory: () => ({
    verifyAppCheck: async (token) => token === "valid-app" ? {appId: "web-app"} : Promise.reject(Object.assign(new Error("bad app"), {code: "failed-precondition"})),
    verifyIdToken: async (token) => token === "valid-user" ? {uid: "admin-1", email: "admin@example.invalid"} : Promise.reject(Object.assign(new Error("bad auth"), {code: "unauthenticated"})),
    handlers,
  })});
  return {server, calls};
}

function request(url, name, {appCheck, auth, data = {}} = {}) {
  return fetch(`${url}/newsletter-api/v1/callable/${name}`, {
    method: "POST", headers: {"content-type": "application/json", ...(appCheck ? {"x-firebase-appcheck": appCheck} : {}), ...(auth ? {authorization: `Bearer ${auth}`} : {})},
    body: JSON.stringify({data}),
  });
}

test("health is lazy and reports dormant activation", async () => {
  const server = createServer({dependenciesFactory: () => {
    throw new Error("health must not initialize Firebase");
  }});
  await listen(server, async (url) => {
    const response = await fetch(`${url}/health`);
    assert.equal(response.status, 200);
    assert.equal((await response.json()).signupEnabled, false);
  });
});

test("routes exactly eight newsletter handlers", () => {
  assert.equal(PUBLIC.size, 5);
  assert.equal(ADMIN.size, 3);
  assert.equal(routeName("/v1/callable/submitNewsletterSignup"), "submitNewsletterSignup");
  assert.equal(routeName("/newsletter-api/v1/callable/adminNewsletterDashboard"), "adminNewsletterDashboard");
  assert.equal(routeName("/v1/callable/createGiftPayment"), null);
});

test("public routes require valid App Check and preserve caller IP", async () => {
  const {server, calls} = fixture();
  await listen(server, async (url) => {
    assert.equal((await request(url, "submitNewsletterSignup")).status, 400);
    assert.equal((await request(url, "submitNewsletterSignup", {appCheck: "bad"})).status, 400);
    const response = await fetch(`${url}/newsletter-api/v1/callable/submitNewsletterSignup`, {method: "POST", headers: {"content-type": "application/json", "x-firebase-appcheck": "valid-app", "x-forwarded-for": "203.0.113.7, 10.0.0.1"}, body: JSON.stringify({data: {consent: true}})});
    assert.equal(response.status, 200);
    assert.equal(calls[0].context.app.appId, "web-app");
    assert.equal(calls[0].context.rawRequest.ip, "203.0.113.7");
  });
});

test("admin routes require both App Check and Firebase authentication", async () => {
  const {server, calls} = fixture();
  await listen(server, async (url) => {
    assert.equal((await request(url, "adminNewsletterDashboard", {appCheck: "valid-app"})).status, 401);
    assert.equal((await request(url, "adminNewsletterDashboard", {appCheck: "valid-app", auth: "bad"})).status, 401);
    const response = await request(url, "adminNewsletterDashboard", {appCheck: "valid-app", auth: "valid-user"});
    assert.equal(response.status, 200);
    assert.equal(calls[0].context.auth.uid, "admin-1");
  });
});

test("oversized, malformed and unrelated requests are bounded", async () => {
  const {server} = fixture();
  await listen(server, async (url) => {
    assert.equal((await request(url, "createGiftPayment", {appCheck: "valid-app"})).status, 404);
    const response = await fetch(`${url}/v1/callable/submitNewsletterSignup`, {method: "POST", headers: {"content-type": "application/json", "x-firebase-appcheck": "valid-app"}, body: JSON.stringify({data: {padding: "x".repeat(33000)}})});
    assert.equal(response.status, 413);
  });
});
