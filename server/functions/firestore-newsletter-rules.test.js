"use strict";
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const assert = require("node:assert/strict");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const newsletter = require("./newsletter");
const {createService, sha256} = newsletter._private;
const {initializeTestEnvironment, assertFails} = require("@firebase/rules-unit-testing");
const {doc, getDoc, setDoc, updateDoc, deleteDoc, getDocs, collection} = require("firebase/firestore");

const projectId = `newsletter-rules-${process.pid}`;
let env;
let app;
let db;

test.before(async () => {
  env = await initializeTestEnvironment({projectId, firestore: {rules: fs.readFileSync(path.join(__dirname, "../../firestore.rules"), "utf8")}});
  await env.withSecurityRulesDisabled(async (context) => setDoc(doc(context.firestore(), "newsletterSubscribers/hash"), {email: "private@example.com", status: "active"}));
  app = initializeApp({projectId});
  db = getFirestore(app);
});
test.after(async () => {
  if (app) await deleteApp(app);
  if (env) await env.cleanup();
});

test("newsletter, suppression, rate-limit and analytics collections deny direct client access", async () => {
  for (const context of [env.unauthenticatedContext(), env.authenticatedContext("sender"), env.authenticatedContext("rider"), env.authenticatedContext("admin", {adminRole: "super_admin"})]) {
    const db = context.firestore();
    await assertFails(getDoc(doc(db, "newsletterSubscribers/hash")));
    await assertFails(setDoc(doc(db, "newsletterSubscribers/new"), {email: "x@example.com"}));
    await assertFails(updateDoc(doc(db, "newsletterSubscribers/hash"), {status: "active"}));
    await assertFails(deleteDoc(doc(db, "newsletterSubscribers/hash")));
    await assertFails(getDocs(collection(db, "newsletterSubscribers")));
    await assertFails(getDoc(doc(db, "newsletterSubscribers/hash/consentEvents/event")));
    await assertFails(setDoc(doc(db, "newsletterSubscribers/hash/consentEvents/event"), {type: "subscribed"}));
    await assertFails(getDoc(doc(db, "newsletterSignupRateLimits/hash")));
    await assertFails(getDoc(doc(db, "newsletterAnalyticsEvents/event")));
    await assertFails(setDoc(doc(db, "newsletterSignupRateLimits/hash"), {attempts: 0}));
    await assertFails(setDoc(doc(db, "newsletterAnalyticsEvents/event"), {event: "newsletter_signup_completed"}));
  }
});

test("real transactions deduplicate simultaneous signups and preserve one consent record", async () => {
  const handoffs = [];
  const service = createService({db, provider: {upsertAudienceMember: async (payload) => {
    handoffs.push(payload);
    return {status: "synced"};
  }}});
  const input = {email: " EMULATOR@example.com ", source: "homepage", consent: true};
  const results = await Promise.all(Array.from({length: 4}, () => service.signup(input)));
  assert.equal(results.filter((result) => result.outcome === "created").length, 1);
  assert.equal(handoffs.length, 1);
  const ref = db.collection("newsletterSubscribers").doc(sha256("emulator@example.com"));
  assert.equal((await ref.collection("consentEvents").get()).size, 1);
  assert.equal((await ref.get()).data().email, "emulator@example.com");
  const token = handoffs[0].unsubscribeToken;
  await Promise.all([service.unsubscribe({token}), service.unsubscribe({token})]);
  assert.equal((await ref.collection("consentEvents").where("type", "==", "unsubscribed").get()).size, 1);
  await assert.rejects(service.updatePreferences({token, categories: ["offers_rewards"]}), {code: "permission-denied"});
  await service.signup({...input, source: "footer"});
  await assert.rejects(service.preferences({token}), {code: "permission-denied"});
  assert.equal((await ref.get()).data().status, "active");
});

test("real preference and unsubscribe race cannot restore active state", async () => {
  let token;
  const service = createService({db, provider: {upsertAudienceMember: async (payload) => {
    token = payload.unsubscribeToken || token;
    return {status: "synced"};
  }}});
  await service.signup({email: "race-real@example.com", source: "homepage", consent: true});
  await Promise.allSettled([
    service.updatePreferences({token, categories: ["offers_rewards"]}),
    service.unsubscribe({token}),
  ]);
  const record = (await db.collection("newsletterSubscribers").doc(sha256("race-real@example.com")).get()).data();
  assert.equal(record.status, "unsubscribed");
  assert.deepEqual(record.categories, []);
});

test("actual admin callables enforce authentication and server-resolved roles", async () => {
  const appContext = {app: {appId: "test-app"}};
  const calls = [newsletter.adminNewsletterDashboard, newsletter.adminSearchNewsletterSubscribers, newsletter.adminExportNewsletterSubscribers];
  for (const callable of calls) {
    await assert.rejects(callable.run({}, appContext), {code: "unauthenticated"});
    for (const role of ["sender", "rider", "support_agent", "finance_admin"]) {
      await assert.rejects(callable.run({role: "super_admin", admin: true}, {
        ...appContext, auth: {uid: `test-${role}`, token: {role}},
      }), {code: "permission-denied"});
    }
  }
  const analytics = {...appContext, auth: {uid: "test-analytics", token: {role: "analytics_viewer"}}};
  await assert.rejects(newsletter.adminExportNewsletterSubscribers.run({}, analytics), {code: "permission-denied"});
  assert.equal((await newsletter.adminNewsletterDashboard.run({}, analytics)).ok, true);
  await db.collection("adminUsers").doc("test-operations").set({role: "operations_admin", status: "active"});
  const operations = {...appContext, auth: {uid: "test-operations", token: {}}};
  const result = await newsletter.adminSearchNewsletterSubscribers.run({query: "emulator@example.com"}, operations);
  assert.equal(result.records.length, 1);
  assert.equal(result.records[0].unsubscribeTokenHash, undefined);
  assert.equal(result.records[0].consentWording, undefined);
});

test("active audience export paginates without leaking tokens or suppressed records", async () => {
  let batch = db.batch();
  for (let index = 0; index < 501; index++) {
    const email = `export-${index}@example.com`;
    batch.set(db.collection("newsletterSubscribers").doc(sha256(email)), {
      email, status: "active", categories: ["circum_updates"], signupSource: "homepage", unsubscribeTokenHash: "never-export",
    });
    if (index === 499) {
      await batch.commit();
      batch = db.batch();
    }
  }
  await batch.commit();
  const context = {app: {appId: "test-app"}, auth: {uid: "test-export", token: {role: "operations_admin"}}};
  const first = await newsletter.adminExportNewsletterSubscribers.run({}, context);
  assert.equal(first.records.length, 500);
  assert.ok(first.nextCursor);
  const second = await newsletter.adminExportNewsletterSubscribers.run({cursor: first.nextCursor}, context);
  assert.equal(second.nextCursor, null);
  const records = [...first.records, ...second.records];
  assert.equal(new Set(records.map((record) => record.id)).size, records.length);
  assert.equal(records.filter((record) => record.email.startsWith("export-")).length, 501);
  assert.ok(records.every((record) => record.status === "active" && record.unsubscribeTokenHash === undefined));
  assert.equal(records.some((record) => record.email === "race-real@example.com"), false);
  await assert.rejects(newsletter.adminExportNewsletterSubscribers.run({cursor: "invalid"}, context), {code: "invalid-argument"});
});
