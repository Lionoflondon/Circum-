/* eslint-disable max-len, require-jsdoc */
"use strict";

function text(value) {
  return `${value || ""}`.trim();
}

function keyMode(value) {
  const key = text(value);
  if (key.startsWith("sk_test_")) return "test";
  if (key.startsWith("sk_live_")) return "live";
  if (key.startsWith("pk_test_")) return "test";
  if (key.startsWith("pk_live_")) return "live";
  return "unknown";
}

function secretMode(value) {
  const secret = text(value);
  if (secret.startsWith("whsec_")) return "configured";
  return "missing";
}

function explicitLiveEnabled(config = {}, env = process.env) {
  return env.STRIPE_LIVE_MODE_ENABLED === "true" ||
    config.live_mode_enabled === true ||
    config.liveModeEnabled === true;
}

function resolveStripeRuntimeConfig({
  config = {},
  env = process.env,
  firebaseProject = process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT || "",
  webhookSecret = "",
  requireWebhookSecret = false,
} = {}) {
  const mode = text(env.STRIPE_MODE || config.mode || config.environment || "test").toLowerCase();
  if (!["test", "live"].includes(mode)) {
    throw new Error("Stripe mode must be explicitly test or live.");
  }
  const secretKey = text(
      env.STRIPE_SECRET_KEY ||
      config.secret_key ||
      config.secretKey ||
      (mode === "live" ? config.livekey : config.testkey) ||
      config.livekey ||
      config.testkey,
  );
  const resolvedKeyMode = keyMode(secretKey);
  if (resolvedKeyMode !== mode) {
    throw new Error(`Stripe ${mode} mode requires an sk_${mode}_ secret key.`);
  }
  if (mode === "live") {
    if (!explicitLiveEnabled(config, env)) {
      throw new Error("Stripe live mode is not explicitly enabled.");
    }
    const allowedProject = text(env.STRIPE_LIVE_FIREBASE_PROJECT || config.live_firebase_project || config.liveFirebaseProject);
    if (!allowedProject || allowedProject !== firebaseProject) {
      throw new Error("Stripe live mode Firebase project is not explicitly allowed.");
    }
  }
  const resolvedWebhookSecret = text(webhookSecret || env.STRIPE_WEBHOOK_SECRET || config.webhook_secret || config.webhooksecret);
  if (requireWebhookSecret && secretMode(resolvedWebhookSecret) !== "configured") {
    throw new Error("Stripe webhook secret is not configured.");
  }
  return {
    mode,
    secretKey,
    keyMode: resolvedKeyMode,
    webhookSecret: resolvedWebhookSecret,
    firebaseProject,
    source: env.STRIPE_SECRET_KEY ? "env" : "functions_config",
  };
}

function assertStripeEventMode(event, runtimeConfig) {
  const eventLiveMode = event && event.livemode === true ? "live" : "test";
  if (eventLiveMode !== runtimeConfig.mode) {
    throw new Error(`Stripe webhook livemode mismatch: event=${eventLiveMode}, config=${runtimeConfig.mode}`);
  }
  return true;
}

module.exports = {
  assertStripeEventMode,
  keyMode,
  resolveStripeRuntimeConfig,
};
