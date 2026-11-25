"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {createHash, createHmac} = require("node:crypto");
const {STAGING_ORIGIN, createRothCentralClient, createConfiguredRothCentralClient} = require("./roth-central-client");

test("CIRCUM ROTH client signs versioned staging requests and carries deterministic idempotency", async () => {
  const secret = "synthetic-staging-secret";
  let captured;
  const client = createRothCentralClient({
    baseUrl: STAGING_ORIGIN, keyId: "circum-key", secret,
    clock: () => new Date("2026-11-20T10:00:00.000Z"), nonceFactory: () => "synthetic-nonce",
    fetchImpl: async (url, init) => {
      captured = {url: String(url), init};
      return {ok: true, status: 200, json: async () => ({journalId: "synthetic-journal"})};
    },
  });
  const result = await client.issueReward({externalId: "circum-user-1", rewardId: "referral-123", amountPence: 1000, reason: "eligible referral"});
  assert.deepEqual(result, {journalId: "synthetic-journal"});
  const body = JSON.stringify({externalId: "circum-user-1", rewardId: "referral-123", amountPence: 1000, campaignId: undefined, reason: "eligible referral"});
  const canonical = ["POST", "/v1/integration/reward", "2026-11-20T10:00:00.000Z", "synthetic-nonce", createHash("sha256").update(body).digest("hex")].join("\n");
  const expected = createHmac("sha256", secret).update(canonical).digest("hex");
  assert.equal(captured.url, `${STAGING_ORIGIN}/v1/integration/reward`);
  assert.equal(captured.init.headers["X-ROTH-Signature"], expected);
  assert.equal(captured.init.headers["X-ROTH-Key-Id"], "circum-key");
  assert.equal(captured.init.headers["Idempotency-Key"], "circum_reward_referral-123");
  assert.equal(captured.init.redirect, "error");
});

test("central CIRCUM mode refuses production or unconfigured project identities", () => {
  assert.throws(() => createConfiguredRothCentralClient({
    GCLOUD_PROJECT: "circum-2797c", ROTH_COMPANY_STAGING_PROJECT: "circum-2797c", ROTH_CENTRAL_MODE: "staging",
    ROTH_CIRCUM_MERCHANT_KEY_ID: "key", ROTH_CIRCUM_MERCHANT_SECRET: "secret",
  }), /only in an explicitly configured CIRCUM staging project/);
  assert.throws(() => createConfiguredRothCentralClient({GCLOUD_PROJECT: "circum-qa", ROTH_CENTRAL_MODE: "staging"}), /only in an explicitly configured CIRCUM staging project/);
});

test("CIRCUM client rejects unapproved API origins and missing scoped credentials", () => {
  assert.throws(() => createRothCentralClient({baseUrl: "https://api.example.com", keyId: "key", secret: "secret"}), /approved ROTH staging API origin/);
  assert.throws(() => createRothCentralClient({baseUrl: STAGING_ORIGIN, keyId: "key", secret: ""}), /credentials are unavailable/);
});
