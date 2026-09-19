"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {normalizeEmail, normalizeCategories, sha256, CATEGORIES, createService, limitPublicRequest} = require("./newsletter")._private;

class FakeDb {
  constructor() {
 this.records = new Map(); this.sequence = 0; this.queue = Promise.resolve();
}
  collection(name) {
 return new FakeCollection(this, name);
}
  runTransaction(work) {
    const next = this.queue.then(() => work(new FakeTransaction(this)));
    this.queue = next.catch(() => {});
    return next;
  }
  snapshot(pathname) {
    const value = this.records.get(pathname);
    return {exists: value != null, data: () => value && structuredClone(value)};
  }
  write(pathname, value, options = {}) {
    const current = this.records.get(pathname) || {};
    this.records.set(pathname, options.merge ? {...current, ...structuredClone(value)} : structuredClone(value));
  }
}

class FakeCollection {
  constructor(db, name) {
 this.db = db; this.name = name;
}
  doc(id = `auto-${++this.db.sequence}`) {
 return new FakeRef(this.db, `${this.name}/${id}`);
}
  where(field, operator, value) {
 return {limit: () => ({get: async () => this.query(field, operator, value)})};
}
  async add(value) {
 const ref = this.doc(); await ref.set(value); return ref;
}
  async query(field, operator, value) {
    const prefix = `${this.name}/`;
    const docs = [...this.db.records.entries()].filter(([key, item]) => key.startsWith(prefix) && !key.slice(prefix.length).includes("/") && operator === "==" && item[field] === value)
        .map(([key, item]) => ({ref: new FakeRef(this.db, key), data: () => structuredClone(item)}));
    return {empty: docs.length === 0, docs};
  }
}

class FakeRef {
  constructor(db, pathname) {
 this.db = db; this.path = pathname; this.id = pathname.split("/").at(-1);
}
  collection(name) {
 return new FakeCollection(this.db, `${this.path}/${name}`);
}
  async get() {
 return this.db.snapshot(this.path);
}
  async set(value, options) {
 this.db.write(this.path, value, options);
}
}

class FakeTransaction {
  constructor(db) {
 this.db = db;
}
  async get(ref) {
 return this.db.snapshot(ref.path);
}
  set(ref, value, options) {
 this.db.write(ref.path, value, options);
}
}

function fixture({provider = {upsertAudienceMember: async () => ({status: "synced"})}} = {}) {
  const db = new FakeDb();
  let tokenNumber = 0;
  const service = createService({db, provider, now: () => 1700000000000, tokenFactory: () => `token-${++tokenNumber}`.padEnd(40, "x")});
  const signup = service.signup;
  service.signup = (data) => signup({consent: true, ...data});
  return {db, provider, service};
}

test("newsletter normalizes email and creates deterministic identifiers", () => {
  assert.equal(normalizeEmail("  HELLO@Example.COM "), "hello@example.com");
  assert.equal(sha256("hello@example.com"), sha256("hello@example.com"));
});

test("newsletter rejects malformed email and optional categories are never implicit", () => {
  assert.throws(() => normalizeEmail("not-an-email"));
  assert.deepEqual(normalizeCategories(null), ["circum_updates"]);
  assert.deepEqual(normalizeCategories([CATEGORIES[1]]), [CATEGORIES[1]]);
  assert.throws(() => normalizeCategories(["unknown"]));
});

test("newsletter module is callable-only with no Firestore trigger export", () => {
  const module = require("./newsletter");
  for (const key of ["submitNewsletterSignup", "getNewsletterPreferences", "updateNewsletterPreferences", "unsubscribeNewsletter"]) {
    assert.ok(module[key], `${key} is exported`);
  }
  assert.equal(Object.keys(module).some((key) => key.startsWith("onNewsletter")), false);
});

test("concurrent normalized duplicate signups create one active subscriber", async () => {
  const {db, service} = fixture();
  const results = await Promise.all([service.signup({email: " A@Example.com ", source: "homepage"}), service.signup({email: "a@example.COM", source: "footer"})]);
  assert.deepEqual(results.map((result) => result.outcome).sort(), ["already_active", "created"]);
  assert.equal([...db.records.keys()].filter((key) => key.startsWith("newsletterSubscribers/") && !key.includes("/consentEvents/")).length, 1);
});

test("unsubscribe suppresses, is idempotent, and resubscription creates a fresh active consent", async () => {
  const {db, provider, service} = fixture();
  const email = "unsubscribe@example.com";
  await service.signup({email, source: "homepage"});
  const id = sha256(email);
  const firstToken = "token-1".padEnd(40, "x");
  assert.equal((await service.unsubscribe({token: firstToken})).status, "unsubscribed");
  assert.equal((await service.unsubscribe({token: firstToken})).status, "unsubscribed");
  assert.equal((await service.preferences({token: firstToken})).status, "unsubscribed");
  await assert.rejects(service.updatePreferences({token: firstToken, categories: ["offers_rewards"]}));
  const resubscription = await service.signup({email, source: "footer"});
  assert.equal(resubscription.outcome, "resubscribed");
  assert.equal(db.records.get(`newsletterSubscribers/${id}`).status, "active");
  assert.equal(provider.upsertAudienceMember instanceof Function, true);
  await assert.rejects(service.preferences({token: firstToken}));
});

test("invalid and tampered tokens never reveal or modify subscriber data", async () => {
  const {service} = fixture();
  await service.signup({email: "token@example.com", source: "homepage"});
  for (const token of ["short", "x".repeat(40), `${"token-1".padEnd(39, "x")}z`]) {
    await assert.rejects(service.unsubscribe({token}));
  }
});

test("rate limit and honeypot bot rejection apply before subscription writes", async () => {
  const {service} = fixture();
  await assert.rejects(service.signup({email: "bot@example.com", source: "homepage", website: "trap"}));
  for (let attempt = 0; attempt < 5; attempt++) await service.signup({email: "limit@example.com", source: "homepage"});
  await assert.rejects(service.signup({email: "limit@example.com", source: "homepage"}));
});

test("provider failure is explicit retry work and does not pretend email delivery succeeded", async () => {
  const {db, service} = fixture({provider: {upsertAudienceMember: async () => {
 throw new Error("provider down");
}}});
  await service.signup({email: "provider@example.com", source: "homepage"});
  assert.equal(db.records.get(`newsletterSubscribers/${sha256("provider@example.com")}`).providerSyncStatus, "retry_required");
});

test("analytics persists only event metadata, never email or token PII", async () => {
  const {db, service} = fixture();
  await service.recordEvent({event: "newsletter_signup_completed", source: "homepage", email: "private@example.com", token: "secret", ip: "127.0.0.1"});
  const event = [...db.records.entries()].find(([key]) => key.startsWith("newsletterAnalyticsEvents/"))[1];
  assert.deepEqual(Object.keys(event).sort(), ["createdAt", "event", "source"]);
});

test("public callable App Check, suppression provider handoff, and no trigger recursion are source-enforced", () => {
  const source = fs.readFileSync(path.join(__dirname, "newsletter.js"), "utf8");
  assert.match(source, /enforceAppCheck: true, maxInstances: 3, timeoutSeconds: 30/);
  assert.match(source, /status: "unsubscribed"/);
  assert.doesNotMatch(source, /firestore\.document|\.onWrite\(|\.onCreate\(|\.onUpdate\(/);
  assert.doesNotMatch(source, /sendMarketing|sendMail|sendEmail/);
});

test("duplicate signup cannot change preferences or rotate a working unsubscribe token", async () => {
  const {db, service} = fixture();
  const input = {email: "duplicate@example.com", source: "homepage"};
  await service.signup(input);
  const before = db.records.get(`newsletterSubscribers/${sha256(input.email)}`);
  await service.signup({...input, categories: ["offers_rewards"]});
  assert.deepEqual(db.records.get(`newsletterSubscribers/${sha256(input.email)}`), before);
  await service.unsubscribe({token: "token-1".padEnd(40, "x")});
});

test("signup requires explicit consent and does not truncate overlong email addresses", async () => {
  const {db, service} = fixture();
  for (const consent of [false, undefined, "true"]) {
    await assert.rejects(service.signup({email: "consent@example.com", source: "homepage", consent}));
  }
  for (const email of [123, {}, "a".repeat(250) + "@example.com"]) assert.throws(() => normalizeEmail(email));
  assert.throws(() => normalizeCategories([]));
  assert.equal(db.records.size, 0);
});

test("concurrent unsubscribe records one withdrawal and keeps suppression", async () => {
  const {db, service} = fixture();
  await service.signup({email: "race@example.com", source: "homepage"});
  const token = "token-1".padEnd(40, "x");
  await Promise.all([service.unsubscribe({token}), service.unsubscribe({token})]);
  const events = [...db.records.values()].filter((item) => item.type === "unsubscribed");
  assert.equal(events.length, 1);
  assert.equal((await service.preferences({token})).status, "unsubscribed");
});

test("late provider completion cannot overwrite a newer unsubscribe failure", async () => {
  let finish;
  let started;
  const providerStarted = new Promise((resolve) => {
 started = resolve;
});
  const provider = {upsertAudienceMember: async ({status}) => {
    if (status === "active") {
      started();
      await new Promise((resolve) => {
 finish = resolve;
});
      return {status: "synced"};
    }
    throw new Error("offline");
  }};
  const {db, service} = fixture({provider});
  const signup = service.signup({email: "delayed@example.com", source: "homepage"});
  await providerStarted;
  await service.unsubscribe({token: "token-1".padEnd(40, "x")});
  finish();
  await signup;
  const record = db.records.get(`newsletterSubscribers/${sha256("delayed@example.com")}`);
  assert.equal(record.status, "unsubscribed");
  assert.equal(record.providerSyncStatus, "retry_required");
});

test("explicit repeated withdrawal retries failed suppression without duplicating consent history", async () => {
  let attempts = 0;
  const provider = {upsertAudienceMember: async ({status}) => {
    if (status === "unsubscribed" && ++attempts === 1) throw new Error("offline");
    return {status: "synced"};
  }};
  const {db, service} = fixture({provider});
  await service.signup({email: "retry@example.com", source: "homepage"});
  const token = "token-1".padEnd(40, "x");
  await service.unsubscribe({token});
  await service.unsubscribe({token});
  assert.equal(attempts, 2);
  assert.equal([...db.records.values()].filter((item) => item.type === "unsubscribed").length, 1);
});

test("all newsletter callables reject missing App Check before database access", async () => {
  for (const [name, callable] of Object.entries(require("./newsletter"))) {
    if (name === "_private") continue;
    await assert.rejects(callable.run({}, {}), {code: "failed-precondition"});
  }
});

test("signup remains dormant without approved policy and explicit activation", async () => {
  await assert.rejects(require("./newsletter").submitNewsletterSignup.run({}, {app: {appId: "test"}}), {code: "failed-precondition"});
});

test("server-derived origin quota bounds rotating-email requests and stores no raw IP", async () => {
  const db = new FakeDb();
  const context = {rawRequest: {ip: "192.0.2.10"}};
  for (let index = 0; index < 60; index++) await limitPublicRequest(db, context, "signup", 1700000000000);
  await assert.rejects(limitPublicRequest(db, context, "signup", 1700000000000), {code: "resource-exhausted"});
  assert.equal(JSON.stringify([...db.records]).includes(context.rawRequest.ip), false);
  await limitPublicRequest(db, context, "signup", 1700001000000);
});

test("global quota bounds traffic that rotates network origins", async () => {
  const db = new FakeDb();
  const now = 1700000000000;
  db.records.set("newsletterSignupRateLimits/global-signup", {bucket: Math.floor(now / 900000), attempts: 1000});
  await assert.rejects(limitPublicRequest(db, {rawRequest: {ip: "192.0.2.11"}}, "signup", now), {code: "resource-exhausted"});
});

test("marketing withdrawal cannot mutate transactional account or delivery records", async () => {
  const {db, service} = fixture();
  db.records.set("users/customer", {transactionalEmail: true});
  db.records.set("deliveries/example", {status: "active"});
  await service.signup({email: "separate@example.com", source: "homepage"});
  await service.unsubscribe({token: "token-1".padEnd(40, "x")});
  assert.deepEqual(db.records.get("users/customer"), {transactionalEmail: true});
  assert.deepEqual(db.records.get("deliveries/example"), {status: "active"});
});
