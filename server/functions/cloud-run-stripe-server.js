/* eslint-disable max-len */
"use strict";

const http = require("node:http");
const crypto = require("node:crypto");
const {initializeApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const {getMessaging} = require("firebase-admin/messaging");
const {resolveStripeRuntimeConfig, assertStripeEventMode} = require("./stripe-config");
const {createStripeWebhookProcessor} = require("./stripe-webhook-core");

const MAX_BODY_BYTES = 1024 * 1024;

function createProductionProcessor() {
  initializeApp();
  const db = getFirestore();
  db.settings({ignoreUndefinedProperties: true});
  const runtimeConfig = resolveStripeRuntimeConfig({requireWebhookSecret: true});
  const stripe = require("stripe")(runtimeConfig.secretKey);
  return createStripeWebhookProcessor({
    stripe,
    resolveRuntimeConfig: () => runtimeConfig,
    assertEventMode: assertStripeEventMode,
    db,
    messaging: getMessaging(),
    giftsPayment: require("./gifts-payment"),
    ratingsTipping: require("./ratings-tipping"),
    stripeRefunds: require("./stripe-refunds"),
    senderBooking: require("./sender-booking"),
    businessPayments: require("./business-payments"),
    healthPlus: require("./health-plus"),
    healthMembershipLifecycle: require("./health-membership-lifecycle"),
    rothLedger: require("./roth-ledger"),
    routeCheckoutSessionCompleted: require("./checkout-session-router").routeCheckoutSessionCompleted,
    logger: console,
  });
}

function json(response, status, body) {
  response.writeHead(status, {"content-type": "application/json; charset=utf-8", "cache-control": "no-store"});
  response.end(JSON.stringify(body));
}

function createServer(options = {}) {
  const processorFactory = options.processorFactory || createProductionProcessor;
  let processor;
  return http.createServer((request, response) => {
    if (request.method === "GET" && request.url === "/health") return json(response, 200, {status: "ok", runtime: "node22", version: process.env.CIRCUM_SOURCE_SHA || "unknown"});
    if (request.url !== "/stripe/webhook") return json(response, 404, {error: "Not found"});
    if (request.method !== "POST") return json(response, 405, {error: "Method not allowed"});
    if (!String(request.headers["content-type"] || "").toLowerCase().startsWith("application/json")) return json(response, 415, {error: "Unsupported media type"});
    let size = 0;
    let tooLarge = false;
    const chunks = [];
    request.on("data", (chunk) => {
      size += chunk.length;
      if (size > MAX_BODY_BYTES) tooLarge = true;
      else if (!tooLarge) chunks.push(chunk);
    });
    request.on("error", (error) => {
      if (!response.headersSent) json(response, error.message === "request_too_large" ? 413 : 400, {error: "Invalid request"});
    });
    request.on("end", async () => {
      if (response.headersSent) return;
      if (tooLarge) return json(response, 413, {error: "Request too large"});
      try {
        if (!processor) processor = processorFactory();
        const result = await processor({
          rawBody: Buffer.concat(chunks),
          signature: request.headers["stripe-signature"],
          requestId: request.headers["x-cloud-trace-context"] || crypto.randomUUID(),
        });
        json(response, result.status, result.body);
      } catch (error) {
        console.error("stripe_webhook_processing_failed", {reason: error.message || "internal_error"});
        json(response, 500, {error: "Webhook processing failed"});
      }
    });
  });
}

if (require.main === module) createServer().listen(Number(process.env.PORT || 8080), "0.0.0.0");

module.exports = {createServer, createProductionProcessor, MAX_BODY_BYTES};
