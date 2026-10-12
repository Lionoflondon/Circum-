"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {once} = require("node:events");
const {createServer} = require("./cloud-run-account-bootstrap");
const {EVENT, REQUESTS, createPasswordRecoveryHandler, brandedRecoveryLink, preparePasswordRecovery} = require("./password-recovery");
const {processEmailQueueRecord} = require("./cloud-run-transactional-email");
const {passwordReset} = require("./transactional-email-templates");

function fakeDb() {
  const records = new Map();
  let pending = Promise.resolve();
  const ref = (collection, id) => ({
    key: `${collection}/${id}`,
    async get() {
 const data = records.get(this.key); return {exists: !!data, data: () => data};
},
    async set(data, options) {
 records.set(this.key, options && options.merge ? {...records.get(this.key), ...data} : data);
},
  });
  return {
    records,
    collection: (collection) => ({doc: (id) => ref(collection, id)}),
    runTransaction(run) {
      const next = pending.then(() => run({get: (r) => r.get(), set: (r, data, options) => r.set(data, options)}));
      pending = next.catch(() => {}); return next;
    },
  };
}
const context = {app: {appId: "first-party-app"}};
const link = "https://circum-2797c.firebaseapp.com/__/auth/action?mode=resetPassword&apiKey=public-config&oobCode=example-code-12345678901234567890";
const requestData = {email: "known@example.com", client: "sender"};
const auth = {getUserByEmail: async (email) => ({uid: "uid", email}), generatePasswordResetLink: async () => link};
async function fixture() {
  const db = fakeDb();
  await createPasswordRecoveryHandler({db, now: () => 100000, randomId: () => "one"})(requestData, context);
  return {db, record: db.records.get("emailQueue/password_reset_one"), source: db.records.get(`${REQUESTS}/password_reset_one`)};
}

test("known and unknown requests perform the same work with no Auth lookup or account detail", async () => {
  for (const email of ["known@example.com", "unknown@example.com"]) {
    const db = fakeDb();
    const response = await createPasswordRecoveryHandler({db, now: () => 100000})({email, client: "sender"}, context);
    assert.deepEqual(response, {ok: true});
    assert.equal(db.records.size, 4);
    assert.equal([...db.records.values()].filter((v) => v.eventType === EVENT).length, 1);
  }
});

test("signed-out recovery requires App Check and rejects malformed or extra inputs before writes", async () => {
  const db = fakeDb(); const handler = createPasswordRecoveryHandler({db});
  await assert.rejects(handler(requestData, {}), {code: "failed-precondition"});
  for (const data of [{...requestData, email: "not-email"}, {...requestData, client: "https://evil.test"}, {...requestData, redirect: "https://evil.test"}]) {
    await assert.rejects(handler(data, context), {code: "invalid-argument"});
  }
  assert.equal(db.records.size, 0);
});

test("concurrent duplicate requests produce one queued message and normalise address case", async () => {
  const db = fakeDb(); const handler = createPasswordRecoveryHandler({db, now: () => 100000});
  const responses = await Promise.all(Array.from({length: 20}, () => handler({...requestData, email: " KNOWN@example.com "}, context)));
  assert.ok(responses.every((v) => v.ok === true));
  assert.equal([...db.records.values()].filter((v) => v.eventType === EVENT).length, 1);
});

test("durable limits enforce three per address and 100 globally per rolling hour", async () => {
  const db = fakeDb(); let now = 100000;
  const handler = createPasswordRecoveryHandler({db, now: () => now});
  for (let i = 0; i < 4; i++) {
 await handler(requestData, context); now += 61000;
}
  assert.equal([...db.records.values()].filter((v) => v.eventType === EVENT).length, 3);
  for (let i = 0; i < 97; i++) await handler({...requestData, email: `request${i}@example.com`}, context);
  await assert.rejects(handler({...requestData, email: "limit@example.com"}, context), {code: "resource-exhausted"});
  now += 3600000;
  assert.deepEqual(await handler(requestData, context), {ok: true});
});

test("only reset mode from the expected Firebase project can become a branded fragment", () => {
  for (const client of ["sender", "rider"]) {
    const branded = brandedRecoveryLink(link, client);
    assert.equal(new URL(branded).origin, "https://circumuk.com");
    assert.equal(new URL(branded).search, "");
    const email = passwordReset({link: branded});
    for (const text of [email.html, email.text]) {
      assert.doesNotMatch(text, /firebaseapp|apiKey|public-config|—/i);
      assert.match(text, /Reset your CIRCUM password/);
      assert.match(text, /support@circumuk.com/);
    }
    assert.match(email.html, /#0a84ff/);
    assert.match(email.text, /https:\/\/circumuk.com\/reset-password\/#/);
  }
  for (const changed of [link.replace("circum-2797c", "evil"), link.replace("resetPassword", "verifyEmail"), `${link}&oobCode=second`, link.replace("https:", "http:"), link.replace("firebaseapp.com", "firebaseapp.com.evil.test"), `${link}#evil`]) assert.throws(() => brandedRecoveryLink(changed, "sender"));
  assert.throws(() => passwordReset({link: "https://evil.test/reset-password/"}));
});

test("unknown and disabled recipients are suppressed privately without generating mail", async () => {
  const {record, source} = await fixture();
  for (const getUserByEmail of [async () => {
 throw Object.assign(new Error("private detail"), {code: "auth/user-not-found"});
}, async () => ({disabled: true, email: source.email})]) {
    const result = await preparePasswordRecovery({record, source, auth: {getUserByEmail, generatePasswordResetLink: () => assert.fail()}, nowMs: 100000});
    assert.equal(result.status, "suppressed");
    assert.equal(result.reason, "recovery_recipient_unavailable");
  }
});

test("expired, tampered and changed-recipient jobs do not generate an action link", async () => {
  const {record, source} = await fixture();
  const noAuth = {getUserByEmail: () => assert.fail("Unexpected Auth lookup")};
  for (const changed of [{...source, email: "other@example.com"}, {...source, requestedAtMs: -3600000}, {...source, client: "evil"}, {...source, notificationId: "wrong"}]) {
    assert.equal((await preparePasswordRecovery({record, source: changed, auth: noAuth, nowMs: 100000})).status, "suppressed");
  }
});

test("provider failure retries one persisted action with stable idempotency and sanitized errors", async () => {
  const {db} = await fixture(); let generated = 0; const payloads = []; const keys = [];
  const recoveryAuth = {...auth, generatePasswordResetLink: async () => {
 generated++; return link;
}};
  const fetchImpl = async (_url, options) => {
    payloads.push(options.body); keys.push(options.headers["Idempotency-Key"]);
    return payloads.length === 1 ? {ok: false, status: 503, json: async () => ({message: "private-token-do-not-log", name: "private-token-do-not-log"})} : {ok: true, json: async () => ({id: "resend-test"})};
  };
  const input = {db, emailId: "password_reset_one", eventId: "event", recoveryAuth, fetchImpl, apiKey: "test-key"};
  await assert.rejects(processEmailQueueRecord({...input, nowMs: 100000}), /password_recovery_delivery_failed/);
  assert.equal(db.records.get("emailQueue/password_reset_one").failureReason, "password_recovery_delivery_failed");
  assert.equal((await processEmailQueueRecord({...input, nowMs: 131000})).status, "sent");
  assert.equal((await processEmailQueueRecord({...input, nowMs: 132000})).status, "duplicate");
  assert.equal(generated, 1); assert.equal(payloads.length, 2); assert.equal(payloads[0], payloads[1]); assert.equal(keys[0], keys[1]);
});

test("Rider and Sender generate the correct fixed return target", async () => {
  const {record, source} = await fixture();
  for (const client of ["sender", "rider"]) {
    const result = await preparePasswordRecovery({record, source: {...source, client}, auth, nowMs: 100000});
    assert.equal(result.status, "valid"); assert.match(result.message.text, new RegExp(`app=${client}`));
  }
});

test("HTTP recovery accepts signed-out attested clients and keeps existing routes authenticated", async () => {
  const calls = [];
  const server = createServer({dependenciesFactory: () => ({verifyIdToken: async () => assert.fail("Unexpected ID token lookup"), verifyAppCheck: async (token) => {
    if (token !== "valid") throw Error("bad"); return {appId: "first-party-app"};
  }, operations: {
    requestCircumPasswordReset: {handler: {run: async (data, ctx) => {
 calls.push({data, ctx}); return {ok: true};
}}, appCheckRequired: true},
    sendCircumVerificationEmail: {handler: {run: () => assert.fail()}, appCheckRequired: true},
  }})});
  server.listen(0, "127.0.0.1"); await once(server, "listening");
  try {
    const base = `http://127.0.0.1:${server.address().port}`;
    for (const token of ["", "bad", "valid"]) {
      const response = await fetch(`${base}/requestCircumPasswordReset`, {method: "POST", headers: {"content-type": "application/json", "x-firebase-appcheck": token}, body: JSON.stringify({data: requestData})});
      assert.equal(response.status, token === "valid" ? 200 : token ? 401 : 400);
    }
    assert.equal(calls.length, 1); assert.equal(calls[0].ctx.auth, null);
    const response = await fetch(`${base}/sendCircumVerificationEmail`, {method: "POST", headers: {"content-type": "application/json", "x-firebase-appcheck": "valid"}, body: "{\"data\":{}}"});
    assert.equal(response.status, 401);
  } finally {
 server.close(); await once(server, "close");
}
});
