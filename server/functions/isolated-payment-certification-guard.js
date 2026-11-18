/* eslint-disable max-len, require-jsdoc */
"use strict";
const ACCOUNT = "acct_1UQoXbHlkrYohn3c";
function validate(env) {
  if (env.CIRCUM_CERTIFICATION_ONLY !== "true") throw new Error("Certification opt-in required");
  if (env.GCLOUD_PROJECT !== "demo-pay-cert-20261016") throw new Error("Demo project required");
  if (env.FIRESTORE_EMULATOR_HOST !== "127.0.0.1:8081") throw new Error("Loopback emulator required");
  if (!/^sk_test_[A-Za-z0-9]+$/.test(env.STRIPE_SECRET_KEY || "")) throw new Error("TEST key required");
  if (env.STRIPE_MODE !== "test") throw new Error("TEST mode required");
  if (env.CIRCUM_CERT_ACCOUNT !== ACCOUNT) throw new Error("Approved sandbox required");
  if (!/^[a-f0-9]{64}$/.test(env.CIRCUM_CERT_TOKEN || "")) throw new Error("Strong control token required");
  return {account: ACCOUNT};
}
module.exports = {validate};
