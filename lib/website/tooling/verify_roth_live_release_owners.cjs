#!/usr/bin/env node
"use strict";

const fs = require("node:fs");

const EXPECTED_STRIPE_SOURCE = "f0c24ebc763552f832c26838f14f4c679aa654d7";
const EXPECTED_EMAIL_SOURCE = "b4b21042498793b3d2515adf7b22444ff1b1c60d";
const EXPECTED_EMAIL_RECOVERY = "8b4a31365fe090b52e099dd2ed869e87db384699";

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, "utf8"));
}

function ready(resource) {
  return (resource.status?.conditions || []).some((condition) => condition.type === "Ready" && condition.status === "True");
}

function activeRevisionName(service, serviceName) {
  if (!ready(service)) throw new Error(`${serviceName} is not Ready.`);
  const active = (service.status?.traffic || []).filter((entry) => entry.percent === 100 && !entry.tag && entry.revisionName);
  if (active.length !== 1) throw new Error(`${serviceName} must have one untagged 100% revision.`);
  return active[0].revisionName;
}

function validateRevision(revision, serviceName, certifiedSha) {
  if (!ready(revision)) throw new Error(`${serviceName} active revision is not Ready.`);
  if (!String(revision.spec?.containers?.[0]?.image || "").includes("@sha256:")) {
    throw new Error(`${serviceName} active revision must use an immutable image digest.`);
  }
  const env = Object.fromEntries((revision.spec?.containers?.[0]?.env || []).map((entry) => [entry.name, entry.value]));
  if (env.CIRCUM_ROTH_GUARD_SHA !== certifiedSha) throw new Error(`${serviceName} ROTH guard does not match the certified runtime.`);
  if (serviceName === "circum-stripe-webhook-live") {
    if (env.STRIPE_MODE !== "live" || env.CIRCUM_SOURCE_SHA !== EXPECTED_STRIPE_SOURCE) {
      throw new Error("The certified LIVE Stripe webhook owner has drifted.");
    }
  } else if (serviceName === "circum-transactional-email") {
    if (env.CIRCUM_SOURCE_SHA !== EXPECTED_EMAIL_SOURCE || env.CIRCUM_RECOVERY_BASE_SHA !== EXPECTED_EMAIL_SOURCE || env.CIRCUM_PASSWORD_RECOVERY_SHA !== EXPECTED_EMAIL_RECOVERY) {
      throw new Error("The certified transactional email owner has drifted.");
    }
  } else {
    throw new Error(`Unexpected ROTH release owner: ${serviceName}`);
  }
  return true;
}

function run(args) {
  if (args[0] === "service" && args.length === 4) {
    const [, serviceName, certifiedSha, file] = args;
    if (!/^[a-f0-9]{40}$/.test(certifiedSha)) throw new Error("A certified runtime SHA is required.");
    process.stdout.write(`${activeRevisionName(readJson(file), serviceName)}\n`);
    return;
  }
  if (args[0] === "revisions" && args.length === 4) {
    const [, certifiedSha, stripeFile, emailFile] = args;
    if (!/^[a-f0-9]{40}$/.test(certifiedSha)) throw new Error("A certified runtime SHA is required.");
    validateRevision(readJson(stripeFile), "circum-stripe-webhook-live", certifiedSha);
    validateRevision(readJson(emailFile), "circum-transactional-email", certifiedSha);
    process.stdout.write("Certified LIVE ROTH webhook and receipt owners verified.\n");
    return;
  }
  throw new Error("Usage: verify_roth_live_release_owners.cjs service <service-name> <sha> <service.json> | revisions <sha> <stripe-revision.json> <email-revision.json>");
}

if (require.main === module) {
  try {
    run(process.argv.slice(2));
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}

module.exports = {activeRevisionName, validateRevision};
