/* eslint-disable max-len, require-jsdoc */
"use strict";
const {test} = require("node:test");
const assert = require("node:assert/strict");
const {validate} = require("./isolated-payment-certification-guard");
const env = {CIRCUM_CERTIFICATION_ONLY: "true", GCLOUD_PROJECT: "demo-pay-cert-20261016", FIRESTORE_EMULATOR_HOST: "127.0.0.1:8081", STRIPE_SECRET_KEY: "sk_test_fixture", STRIPE_MODE: "test", CIRCUM_CERT_ACCOUNT: "acct_1UQoXbHlkrYohn3c", CIRCUM_CERT_TOKEN: "a".repeat(64)};
test("isolated runtime accepts only its exact approved environment", () => {
  assert.equal(validate(env).account, env.CIRCUM_CERT_ACCOUNT);
  for (const [key, value] of Object.entries({CIRCUM_CERTIFICATION_ONLY: "false", GCLOUD_PROJECT: "circum-2797c", FIRESTORE_EMULATOR_HOST: "firestore.googleapis.com:443", STRIPE_SECRET_KEY: "sk_live_fixture", STRIPE_MODE: "live", CIRCUM_CERT_ACCOUNT: "acct_other", CIRCUM_CERT_TOKEN: "weak"})) {
    assert.throws(() => validate({...env, [key]: value}));
  }
});
