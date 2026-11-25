"use strict";

function referralEventConfig(env = process.env) {
  const mode = env.ROTH_CENTRAL_MODE || "disabled";
  if (mode === "disabled") return {sourceProject: "circum-2797c", centralStaging: false};
  if (mode !== "staging") throw new Error("Unsupported CIRCUM central ROTH mode.");
  const projectId = env.GCLOUD_PROJECT || env.GCP_PROJECT || "";
  const configured = env.ROTH_COMPANY_STAGING_PROJECT || "";
  if (!projectId || projectId !== configured || projectId === "circum-2797c" || !/(^|[-_])(stage|staging|stg|dev|test)([-_]|$)/i.test(projectId)) {
    throw new Error("CIRCUM central referral awards require an explicitly matched isolated staging project.");
  }
  return {sourceProject: projectId, centralStaging: true};
}

function referralAwardMode(env = process.env, centralClient = null) {
  const config = referralEventConfig(env);
  if (config.centralStaging) {
    if (!centralClient || typeof centralClient.issueReward !== "function") {
      throw new Error("Central ROTH client is required for CIRCUM staging referral awards; legacy issuance is disabled.");
    }
    return "central";
  }
  return "legacy";
}

module.exports = {referralEventConfig, referralAwardMode};
