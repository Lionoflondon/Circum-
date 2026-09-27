"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const source = fs.readFileSync(path.join(__dirname, "qa-business-gifts-certification.js"), "utf8");

test("Business Gifts certification runner is test-only and isolated", () => {
  assert.match(source, /sk_test_/);
  assert.match(source, /STRIPE_WEBHOOK_TEST_SECRET/);
  assert.match(source, /qaSpecialFlowFixtures/);
  assert.match(source, /isSyntheticQa/);
  assert.match(source, /stripeMode: "TEST"/);
  assert.match(source, /checkoutEventSynthetic: true/);
  assert.match(source, /paymentIntents\.create/);
  assert.match(source, /payment_method_types: \["card"\]/);
  assert.match(source, /generateTestHeaderString\(\{payload: rawBody/);
  assert.doesNotMatch(source, /process\.env\.STRIPE_SECRET_KEY/);
  assert.doesNotMatch(source, /STRIPE_LIVE_MODE_ENABLED/);
});

test("certification cleanup is bounded to test objects", () => {
  assert.match(source, /intent\.livemode/);
  assert.match(source, /stripe\.refunds\.create/);
  assert.match(source, /stripe\.subscriptions\.cancel/);
  assert.match(source, /archived: true/);
});

test("headless TEST confirmations provide a QA return URL", () => {
  assert.equal((source.match(/return_url: "https:\/\/example\.invalid\/qa"/g) || []).length, 2);
});
