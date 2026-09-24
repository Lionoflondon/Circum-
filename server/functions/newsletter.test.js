"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {normalizeEmail, normalizeCategories, sha256, CATEGORIES, createService, limitPublicRequest, resendNewsletterProvider, syncMailchimpAudienceEvent, reconcileMailchimpAudience} = require("./newsletter")._private;

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

test("Resend newsletter adapter upserts contacts without sending campaign email", async () => {
  const calls = [];
  const provider = resendNewsletterProvider({
    apiKey: "test-newsletter-key",
    fetchImpl: async (url, options) => {
      calls.push({url, options});
      return {ok: options.method === "POST", status: options.method === "POST" ? 201 : 404};
    },
  });
  const {db, service} = fixture({provider});
  await service.signup({email: "resend@example.com", source: "homepage", categories: ["circum_updates"]});
  assert.equal(calls.length, 1);
  assert.equal(calls[0].options.method, "POST");
  assert.equal(calls[0].url, "https://api.resend.com/contacts");
  assert.equal(calls[0].options.headers.Authorization, "Bearer test-newsletter-key");
  assert.deepEqual(JSON.parse(calls[0].options.body), {email: "resend@example.com"});
  assert.equal(db.records.get(`newsletterSubscribers/${sha256("resend@example.com")}`).providerSyncStatus, "synced");
});

test("Resend newsletter adapter applies local unsubscribe suppression", async () => {
  const calls = [];
  const provider = resendNewsletterProvider({
    apiKey: "test-newsletter-key",
    fetchImpl: async (url, options) => {
      calls.push({url, options});
      return {ok: true, status: options.method === "PATCH" ? 200 : 201};
    },
  });
  const {service} = fixture({provider});
  await service.signup({email: "suppressed@example.com", source: "homepage"});
  await service.unsubscribe({token: "token-1".padEnd(40, "x")});
  assert.equal(calls.at(-1).options.method, "PATCH");
  assert.deepEqual(JSON.parse(calls.at(-1).options.body), {email: "suppressed@example.com", unsubscribed: true});
});

test("Mailchimp subscription sync never clears an existing Circum unsubscribe", async () => {
  const db = new FakeDb();
  const email = "withdrawn@example.com";
  db.records.set(`newsletterSubscribers/${sha256(email)}`, {email, status: "unsubscribed", revision: 3});
  const calls = [];
  const result = await syncMailchimpAudienceEvent({type: "subscribe", email}, {db, provider: {upsertAudienceMember: async (payload) => {
    calls.push(payload);
    return {status: "synced"};
  }}});
  assert.equal(result.status, "suppressed_local_unsubscribe");
  assert.equal(calls.length, 0);
  assert.equal(db.records.get(`newsletterSubscribers/${sha256(email)}`).status, "unsubscribed");
});

test("Mailchimp subscribe preserves an already-active Firebase signup", async () => {
  const db = new FakeDb();
  const email = "firebase-signup@example.com";
  const id = sha256(email);
  const original = {
    email, status: "active", revision: 7, categories: ["offers_rewards"], source: "homepage",
    signupSource: "homepage", consentVersion: "newsletter-consent-v1", consentWording: "By joining, you agree.",
  };
  db.records.set(`newsletterSubscribers/${id}`, original);
  const result = await syncMailchimpAudienceEvent({type: "subscribe", email, eventId: "member-firebase", firedAt: "2026-09-24 10:00:00"}, {db, provider: {upsertAudienceMember: async () => ({status: "synced"})}});
  assert.equal(result.status, "synced");
  const updated = db.records.get(`newsletterSubscribers/${id}`);
  assert.deepEqual(updated.categories, original.categories);
  assert.equal(updated.source, original.source);
  assert.equal(updated.consentVersion, original.consentVersion);
  assert.equal([...db.records.keys()].filter((key) => key.includes("/consentEvents/")).length, 0);
});

test("Mailchimp subscribe adds without resubscribing and unsubscribe suppresses in Resend", async () => {
  const calls = [];
  const provider = resendNewsletterProvider({apiKey: "test-newsletter-key", fetchImpl: async (url, options) => {
    calls.push({url, options});
    return {ok: true, status: 200};
  }});
  await provider.upsertAudienceMember({email: "new@example.com", status: "active", allowResubscribe: false});
  assert.equal(calls[0].options.method, "POST");
  assert.deepEqual(JSON.parse(calls[0].options.body), {email: "new@example.com"});
  await provider.upsertAudienceMember({email: "old@example.com", status: "unsubscribed"});
  assert.equal(calls[1].options.method, "PATCH");
  assert.deepEqual(JSON.parse(calls[1].options.body), {email: "old@example.com", unsubscribed: true});
});

test("Mailchimp duplicate replay is idempotent", async () => {
  const db = new FakeDb();
  let calls = 0;
  const event = {type: "subscribe", email: "replay@example.com", eventId: "member-replay", firedAt: "2026-09-24 10:00:00"};
  const provider = {upsertAudienceMember: async () => {
    calls++;
    return {status: "synced"};
  }};
  assert.equal((await syncMailchimpAudienceEvent(event, {db, provider})).status, "synced");
  const replay = await syncMailchimpAudienceEvent(event, {db, provider});
  assert.equal(replay.status, "synced");
  assert.equal(replay.duplicate, true);
  assert.equal(calls, 1);
  assert.equal([...db.records.keys()].filter((key) => key.includes("/consentEvents/")).length, 1);
});

test("Mailchimp stale event cannot overwrite a newer state", async () => {
  const db = new FakeDb();
  const calls = [];
  const provider = {upsertAudienceMember: async (payload) => {
    calls.push(payload.status);
    return {status: "synced"};
  }};
  await syncMailchimpAudienceEvent({type: "subscribe", email: "ordered@example.com", eventId: "member-ordered", firedAt: "2026-09-24 10:02:00"}, {db, provider});
  const stale = await syncMailchimpAudienceEvent({type: "unsubscribe", email: "ordered@example.com", eventId: "member-ordered", firedAt: "2026-09-24 10:01:00"}, {db, provider});
  assert.equal(stale.status, "stale_ignored");
  assert.equal(db.records.get(`newsletterSubscribers/${sha256("ordered@example.com")}`).status, "active");
  assert.deepEqual(calls, ["active"]);
});

test("Mailchimp provider failure is retryable and the same event can be retried", async () => {
  const db = new FakeDb();
  let attempts = 0;
  const provider = {upsertAudienceMember: async () => {
    attempts++;
    if (attempts === 1) throw new Error("timeout");
    return {status: "synced"};
  }};
  const event = {type: "subscribe", email: "retry-mailchimp@example.com", eventId: "member-retry", firedAt: "2026-09-24 10:00:00"};
  assert.equal((await syncMailchimpAudienceEvent(event, {db, provider})).status, "retry_required");
  assert.equal((await syncMailchimpAudienceEvent(event, {db, provider})).status, "synced");
  assert.equal(attempts, 2);
});

test("audience backfill is consent-preserving and idempotent", async () => {
  const db = new FakeDb();
  const providerCalls = [];
  const provider = {upsertAudienceMember: async (payload) => {
    providerCalls.push({...payload});
    return {status: "synced"};
  }};
  db.records.set(`newsletterSubscribers/${sha256("conflict@example.com")}`, {email: "conflict@example.com", status: "unsubscribed", revision: 4});
  const members = [
    {id: "member-active", email_address: "import@example.com", status: "subscribed", last_changed: "2026-09-24 09:00:00"},
    {id: "member-unsub", email_address: "unsub@example.com", status: "unsubscribed", last_changed: "2026-09-24 09:01:00"},
    {id: "member-clean", email_address: "clean@example.com", status: "cleaned", last_changed: "2026-09-24 09:02:00"},
    {id: "member-pending", email_address: "pending@example.com", status: "pending", last_changed: "2026-09-24 09:03:00"},
    {id: "member-conflict", email_address: "conflict@example.com", status: "subscribed", last_changed: "2026-09-24 09:04:00"},
  ];
  const first = await reconcileMailchimpAudience({members, db, provider});
  const second = await reconcileMailchimpAudience({members, db, provider});
  assert.deepEqual(first, {subscribedImported: 1, suppressedUnsubscribed: 1, cleaned: 1, skipped: 1, conflicted: 1, errors: 0});
  assert.deepEqual(second, {subscribedImported: 0, suppressedUnsubscribed: 0, cleaned: 0, skipped: 1, conflicted: 1, errors: 0});
  assert.equal(db.records.get(`newsletterSubscribers/${sha256("import@example.com")}`).status, "active");
  assert.equal(db.records.get(`newsletterSubscribers/${sha256("unsub@example.com")}`).status, "unsubscribed");
  assert.equal(db.records.get(`newsletterSubscribers/${sha256("clean@example.com")}`).status, "unsubscribed");
  assert.equal(db.records.get(`newsletterSubscribers/${sha256("conflict@example.com")}`).status, "unsubscribed");
  assert.equal(providerCalls.length, 3);
});

test("unsubscribe wins when it races an in-flight backfill", async () => {
  const db = new FakeDb();
  let releaseActive;
  let activeStarted;
  const activeReady = new Promise((resolve) => {
    activeStarted = resolve;
  });
  const provider = {upsertAudienceMember: async ({status}) => {
    if (status === "active") {
      activeStarted();
      await new Promise((resolve) => {
        releaseActive = resolve;
      });
    }
    return {status: "synced"};
  }};
  const backfill = syncMailchimpAudienceEvent({type: "subscribe", email: "race-backfill@example.com", eventId: "member-race", firedAt: "2026-09-24 10:00:00", eventKey: "backfill-race"}, {db, provider});
  await activeReady;
  const unsubscribe = syncMailchimpAudienceEvent({type: "unsubscribe", email: "race-backfill@example.com", eventId: "member-race", firedAt: "2026-09-24 10:01:00"}, {db, provider});
  await unsubscribe;
  releaseActive();
  await backfill;
  assert.equal(db.records.get(`newsletterSubscribers/${sha256("race-backfill@example.com")}`).status, "unsubscribed");
});

test("missing Resend newsletter credentials preserve dormant provider configuration", async () => {
  const {db, service} = fixture({provider: resendNewsletterProvider({apiKey: ""})});
  await service.signup({email: "pending@example.com", source: "homepage"});
  assert.equal(db.records.get(`newsletterSubscribers/${sha256("pending@example.com")}`).providerSyncStatus, "pending_configuration");
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
