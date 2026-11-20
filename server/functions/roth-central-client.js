"use strict";

const {createHash, createHmac, randomUUID} = require("node:crypto");

const STAGING_ORIGIN = "https://roth-stage-api-77403622757.europe-west2.run.app";

class RothCentralApiError extends Error {
  constructor(status, payload) {
    super(payload && (payload.title || payload.code) || `ROTH returned ${status}`);
    this.name = "RothCentralApiError";
    this.status = status;
    this.code = payload && payload.code || "unknown_error";
  }
}

function createRothCentralClient({baseUrl, keyId, secret, fetchImpl = fetch, clock = () => new Date(), nonceFactory = randomUUID}) {
  const origin = new URL(baseUrl);
  if (origin.protocol !== "https:" || origin.origin !== STAGING_ORIGIN || origin.pathname !== "/" || origin.search || origin.hash || origin.username || origin.password) {
    throw new Error("CIRCUM staging may use only the approved ROTH staging API origin.");
  }
  if (!keyId || !secret) throw new Error("ROTH staging merchant credentials are unavailable.");

  async function request(action, body, idempotencyKey, method = "POST") {
    if (!/^(startLink|handle|balance|reward|rewardByHandle|reserve|confirm|cancel|refund|receipt|settlements)$/.test(action)) throw new Error("Unsupported ROTH integration action.");
    const path = action === "settlements" ? "/v1/settlements" : `/v1/integration/${action}`;
    const raw = method === "GET" ? "" : JSON.stringify(body || {});
    const timestamp = clock().toISOString();
    const nonce = nonceFactory();
    const canonical = [method, path, timestamp, nonce, createHash("sha256").update(raw).digest("hex")].join("\n");
    const signature = createHmac("sha256", secret).update(canonical).digest("hex");
    const headers = {
      "Content-Type": "application/json",
      "X-ROTH-Key-Id": keyId,
      "X-ROTH-Timestamp": timestamp,
      "X-ROTH-Nonce": nonce,
      "X-ROTH-Signature": signature,
    };
    if (idempotencyKey) headers["Idempotency-Key"] = idempotencyKey;
    const response = await fetchImpl(new URL(path, origin), {method, headers, ...(method === "GET" ? {} : {body: raw}), redirect: "error"});
    const payload = await response.json();
    if (!response.ok) throw new RothCentralApiError(response.status, payload);
    return payload;
  }

  return {
    startLink(externalId) { return request("startLink", {externalId}); },
    balance(externalId) { return request("balance", {externalId}); },
    issueReward({externalId, rewardId, amountPence, campaignId, reason}) {
      return request("reward", {externalId, rewardId, amountPence, campaignId, reason}, `circum_reward_${rewardId}`);
    },
    issueRewardByHandle({handle, rewardId, amountPence, campaignId, reason}) {
      return request("rewardByHandle", {handle, rewardId, amountPence, campaignId, reason}, `circum_reward_${rewardId}`);
    },
    reserve({externalId, orderId, amountPence}) { return request("reserve", {externalId, orderId, amountPence}, `circum_order_${orderId}`); },
    confirm({orderId, reservationId}) { return request("confirm", {orderId, reservationId}, `circum_confirm_${orderId}`); },
    cancel({orderId, reservationId}) { return request("cancel", {orderId, reservationId}, `circum_cancel_${orderId}`); },
    refund({refundId, journalId, amountPence, reason}) { return request("refund", {refundId, journalId, amountPence, reason}, `circum_refund_${refundId}`); },
    receipt(journalId) { return request("receipt", {journalId}); },
    settlements() { return request("settlements", null, null, "GET"); },
  };
}

function createConfiguredRothCentralClient(env = process.env, options = {}) {
  const projectId = env.GCLOUD_PROJECT || env.GCP_PROJECT || "";
  const configuredStageProject = env.ROTH_COMPANY_STAGING_PROJECT || "";
  if (env.ROTH_CENTRAL_MODE !== "staging" || !configuredStageProject || projectId !== configuredStageProject || !/(^|[-_])(stage|staging|stg|dev|test)([-_]|$)/i.test(projectId) || projectId === "circum-2797c") {
    throw new Error("Central ROTH integration is available only in an explicitly configured CIRCUM staging project.");
  }
  return createRothCentralClient({
    baseUrl: env.ROTH_CENTRAL_API_ORIGIN || STAGING_ORIGIN,
    keyId: env.ROTH_CIRCUM_MERCHANT_KEY_ID,
    secret: env.ROTH_CIRCUM_MERCHANT_SECRET,
    ...options,
  });
}

module.exports = {STAGING_ORIGIN, RothCentralApiError, createRothCentralClient, createConfiguredRothCentralClient};
