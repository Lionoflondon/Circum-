/* eslint-disable max-len, require-jsdoc */
"use strict";
const {test} = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const {config, authorize, assertFixture, assertProvider} = require("./qa-lifecycle")._test;
const lists = {operators: ["operator"], senders: ["sender"], riders: ["rider"]};
const env = {GCLOUD_PROJECT: "circum-2797c", STRIPE_MODE: "TEST", QA_LIFECYCLE_ENABLED: "true", QA_LIFECYCLE_ALLOWLIST: JSON.stringify(lists)};
test("QA policy configuration and all callable actors fail closed", () => {
  assert.deepEqual(config(env), lists);
  for (const patch of [{QA_LIFECYCLE_ENABLED: "false"}, {QA_LIFECYCLE_ALLOWLIST: "bad"}, {STRIPE_MODE: "LIVE"}, {GCLOUD_PROJECT: "other"}, {QA_LIFECYCLE_ALLOWLIST: JSON.stringify({...lists, riders: ["sender"]})}]) assert.throws(() => config({...env, ...patch}));
  for (const context of [{}, {auth: {uid: "sender"}}, {auth: {uid: "unknown"}, app: {}}]) assert.throws(() => authorize(context, lists));
  assert.equal(authorize({auth: {uid: "rider"}, app: {appId: "valid"}}, lists), "rider");
});
test("fixture identity, expiration, actor and TEST payment provenance validated", () => {
  const fixture = {id: "fixture", isSyntheticQa: true, senderId: "sender", riderId: "rider", qaCreatedBy: "operator", expiresAt: {toMillis: () => 100}};
  assertFixture(fixture, lists, "sender", 99);
  for (const patch of [{isSyntheticQa: false}, {senderId: "real"}, {riderId: "real"}, {qaCreatedBy: "real"}, {archived: true}]) assert.throws(() => assertFixture({...fixture, ...patch}, lists, "sender", 99));
  assert.throws(() => assertFixture(fixture, lists, "outsider", 99));
  assert.throws(() => assertFixture(fixture, lists, "sender", 101));
  const intent = {livemode: false, status: "succeeded", amount: 300, amount_received: 300, currency: "gbp", metadata: {qaFixtureId: "fixture", deliveryId: "delivery"}};
  assertProvider(intent, fixture, "delivery", 300);
  for (const patch of [{livemode: true}, {currency: "usd"}, {amount: 301}, {amount_received: 299}, {status: "processing"}, {metadata: {qaFixtureId: "other"}}]) assert.throws(() => assertProvider({...intent, ...patch}, fixture, "delivery", 300));
});
test("QA fixture has no provider, notification, dispatch or reward network capability", () => {
  const source = fs.readFileSync(require.resolve("./qa-lifecycle"), "utf8");
  assert.doesNotMatch(source, /require\(["'](?:stripe|\.\/communication-engine|\.\/roth-ledger|\.\/referrals)["']\)|getMessaging\(|getStorage\(|https\.request\(|fetch\(|transfers\.create|payouts\.create/);
  assert.match(source, /enforceAppCheck: true/);
  assert.match(source, /providerSimulation: true/);
});
