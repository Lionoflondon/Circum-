/* eslint-disable max-len */
const test = require("node:test");
const assert = require("node:assert/strict");

const {
  assertStripeEventMode,
  keyMode,
  resolveStripeRuntimeConfig,
} = require("./stripe-config");

test("test mode accepts only test secret keys", () => {
  const config = resolveStripeRuntimeConfig({
    config: {mode: "test", testkey: "sk_test_example"},
    env: {},
    firebaseProject: "circum-2797c",
  });
  assert.equal(config.mode, "test");
  assert.equal(config.keyMode, "test");
  assert.throws(
      () => resolveStripeRuntimeConfig({
        config: {mode: "test", livekey: "sk_live_example"},
        env: {},
        firebaseProject: "circum-2797c",
      }),
      /requires an sk_test_ secret key/,
  );
});

test("missing Stripe mode fails closed", () => {
  assert.throws(
      () => resolveStripeRuntimeConfig({
        config: {testkey: "sk_test_example"},
        env: {},
        firebaseProject: "circum-2797c",
      }),
      /mode must be explicitly test or live/,
  );
});

test("live mode fails closed without explicit enablement and project allow-list", () => {
  assert.throws(
      () => resolveStripeRuntimeConfig({
        config: {mode: "live", livekey: "sk_live_example"},
        env: {},
        firebaseProject: "circum-2797c",
      }),
      /live mode is not explicitly enabled/,
  );
  assert.throws(
      () => resolveStripeRuntimeConfig({
        config: {mode: "live", livekey: "sk_live_example", liveModeEnabled: true, liveFirebaseProject: "other-project"},
        env: {},
        firebaseProject: "circum-2797c",
      }),
      /Firebase project is not explicitly allowed/,
  );
  const config = resolveStripeRuntimeConfig({
    config: {mode: "live", livekey: "sk_live_example", liveModeEnabled: true, liveFirebaseProject: "circum-2797c"},
    env: {},
    firebaseProject: "circum-2797c",
  });
  assert.equal(config.mode, "live");
});

test("webhook secret and livemode must match runtime mode", () => {
  assert.throws(
      () => resolveStripeRuntimeConfig({
        config: {mode: "test", testkey: "sk_test_example"},
        env: {},
        requireWebhookSecret: true,
      }),
      /webhook secret is not configured/,
  );
  const config = resolveStripeRuntimeConfig({
    config: {mode: "test", testkey: "sk_test_example", webhooksecret: "whsec_test"},
    env: {},
    requireWebhookSecret: true,
  });
  assert.equal(config.webhookSecret, "whsec_test");
  assert.equal(assertStripeEventMode({livemode: false}, config), true);
  assert.throws(
      () => assertStripeEventMode({livemode: true}, config),
      /livemode mismatch/,
  );
});

test("key mode helper does not expose or require secret values", () => {
  assert.equal(keyMode("sk_test_123"), "test");
  assert.equal(keyMode("sk_live_123"), "live");
  assert.equal(keyMode("pk_test_123"), "test");
  assert.equal(keyMode("not-a-key"), "unknown");
});
