"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {createServer, PUBLIC, ADMIN, routeName, MAILCHIMP_WEBHOOK_PATH, parseMailchimpWebhookBody, verifyMailchimpSignature} = require("./cloud-run-newsletter");
const crypto = require("node:crypto");

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

test("parses only a single Mailchimp email audience event", () => {
  assert.deepEqual(parseMailchimpWebhookBody("type=subscribe&fired_at=2026-09-24%2012%3A00%3A00&data%5Bid%5D=member-1&data%5Bemail%5D=hello%40example.com"), {type: "subscribe", email: "hello@example.com", eventId: "member-1", firedAt: "2026-09-24 12:00:00"});
  assert.throws(() => parseMailchimpWebhookBody("type=subscribe&type=unsubscribe&data%5Bemail%5D=hello%40example.com"));
  assert.throws(() => parseMailchimpWebhookBody("type=campaign&data%5Bemail%5D=hello%40example.com"));
});

test("verifies Mailchimp HMAC signature and rejects stale or altered payloads", () => {
  const signingSecret = "test-signing-secret";
  const timestamp = 1800000000;
  const rawBody = "type=subscribe&data%5Bemail%5D=hello%40example.com";
  const signature = crypto.createHmac("sha256", signingSecret).update(`${timestamp}.${rawBody}`).digest("hex");
  const signatureHeader = `t=${timestamp},v1=${signature}`;
  assert.equal(verifyMailchimpSignature({signatureHeader, rawBody, signingSecret, now: timestamp * 1000}), true);
  assert.equal(verifyMailchimpSignature({signatureHeader, rawBody: `${rawBody}&extra=1`, signingSecret, now: timestamp * 1000}), false);
  assert.equal(verifyMailchimpSignature({signatureHeader, rawBody, signingSecret, now: (timestamp + 301) * 1000}), false);
});

test("Mailchimp webhook requires secret and valid content type and passes no contact data to response", async () => {
  const original = process.env.MAILCHIMP_AUDIENCE_WEBHOOK_SECRET;
  process.env.MAILCHIMP_AUDIENCE_WEBHOOK_SECRET = "unit-test-webhook-secret";
  const received = [];
  const server = createServer({dependenciesFactory: () => ({
    syncMailchimpAudienceEvent: async (event) => {
      received.push(event);
      return {status: "synced"};
    },
  })});
  try {
    await listen(server, async (url) => {
      const body = "type=subscribe&data%5Bemail%5D=hello%40example.com";
      const timestamp = Math.floor(Date.now() / 1000);
      const signature = crypto.createHmac("sha256", process.env.MAILCHIMP_AUDIENCE_WEBHOOK_SECRET).update(`${timestamp}.${body}`).digest("hex");
      const signedHeaders = {"content-type": "application/x-www-form-urlencoded", "x-mailchimp-signature": `t=${timestamp},v1=${signature}`};
      assert.equal((await fetch(`${url}${MAILCHIMP_WEBHOOK_PATH}`, {method: "POST", headers: {"content-type": "application/x-www-form-urlencoded"}, body})).status, 401);
      assert.equal((await fetch(`${url}${MAILCHIMP_WEBHOOK_PATH}`, {method: "POST", headers: {...signedHeaders, "content-type": "application/json"}, body})).status, 415);
      const response = await fetch(`${url}${MAILCHIMP_WEBHOOK_PATH}`, {method: "POST", headers: signedHeaders, body});
      assert.equal(response.status, 200);
      assert.deepEqual(await response.json(), {ok: true, status: "synced"});
      assert.deepEqual(received, [{type: "subscribe", email: "hello@example.com", eventId: null, firedAt: null}]);
      const unavailable = createServer({dependenciesFactory: () => ({syncMailchimpAudienceEvent: async () => ({status: "retry_required"})})});
      await listen(unavailable, async (unavailableUrl) => {
        const retryable = await fetch(`${unavailableUrl}${MAILCHIMP_WEBHOOK_PATH}`, {method: "POST", headers: signedHeaders, body});
        assert.equal(retryable.status, 503);
      });
    });
  } finally {
    if (original === undefined) delete process.env.MAILCHIMP_AUDIENCE_WEBHOOK_SECRET;
    else process.env.MAILCHIMP_AUDIENCE_WEBHOOK_SECRET = original;
  }
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
