"use strict";

const http = require("node:http");
const {initializeApp, getApps} = require("firebase-admin/app");
const {resolveStripeRuntimeConfig} = require("./stripe-config");
const businessPayments = require("./business-payments");
const riderConnect = require("./rider-connect");
const deliveryTracking = require("./delivery-tracking");
const healthPlusOperations = require("./health-plus-operations");

if (!getApps().length) initializeApp();

let stripe;
function stripeClient() {
  if (!stripe) {
    const config = resolveStripeRuntimeConfig();
    stripe = require("stripe")(config.secretKey);
    stripe._circumStripeMode = config.mode;
  }
  return stripe;
}

const handlers = Object.freeze({
  reconcileBusinessInvoiceCheckouts: () =>
    businessPayments.reconcileBusinessInvoiceCheckoutsCore(stripeClient()),
  scheduledRiderStripeStatusSync: () =>
    riderConnect.scheduledRiderStripeStatusSyncCore(stripeClient()),
  scheduledRiderPayoutRecovery: () =>
    riderConnect.recoverRiderPayoutsCore(stripeClient()),
  reconcilePendingDeliverySettlements: () =>
    deliveryTracking._private.reconcilePendingDeliverySettlementsCore(),
  processHealthPlusReminders: () =>
    healthPlusOperations._private.processHealthPlusRemindersCore(),
});

const TOPIC_HANDLER_BY_NAME = Object.freeze({
  "firebase-schedule-reconcilePendingDeliverySettlements-us-central1": "reconcilePendingDeliverySettlements",
  "firebase-schedule-processHealthPlusReminders-us-central1": "processHealthPlusReminders",
});

function topicHandlerName(requestUrl = "") {
  const rawUrl = String(requestUrl || "");
  const mode = new URL(rawUrl || "/", "http://localhost").searchParams.get("__GCP_CloudEventsMode") || "";
  const match = /^CUSTOM_PUBSUB_projects\/[^/]+\/topics\/([^/?]+)$/.exec(mode);
  if (match && TOPIC_HANDLER_BY_NAME[match[1]]) return TOPIC_HANDLER_BY_NAME[match[1]];
  for (const [topic, handler] of Object.entries(TOPIC_HANDLER_BY_NAME)) {
    if (rawUrl.includes(topic) || rawUrl.includes(encodeURIComponent(topic))) return handler;
  }
  return "";
}

function eventHandlerName(body, requestUrl = "") {
  const topicHandler = topicHandlerName(requestUrl);
  if (topicHandler) return topicHandler;
  const envelope = body && body.message ? body : body && body.data && body.data.message ? body.data : null;
  const encoded = envelope && envelope.message && envelope.message.data;
  if (!encoded) return "";
  try {
    const decoded = JSON.parse(Buffer.from(encoded, "base64").toString("utf8"));
    const explicitHandler = decoded && decoded.handler;
    return (explicitHandler === "health" || handlers[explicitHandler]) ?
      explicitHandler : "";
  } catch (_) {
    return "";
  }
}

async function readJson(req) {
  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  return JSON.parse(Buffer.concat(chunks).toString("utf8") || "{}");
}

const server = http.createServer(async (req, res) => {
  const path = new URL(req.url, "http://localhost").pathname;
  if (req.method === "GET" && path === "/healthz") {
    res.writeHead(200, {"content-type": "application/json"});
    res.end(JSON.stringify({ok: true, service: "payment-schedulers"}));
    return;
  }
  let name = path.slice(1);
  if (req.method === "POST" && (path === "/" || path === "/events")) {
    name = eventHandlerName(await readJson(req), req.url);
    if (name === "health") {
      console.log("payment_scheduler_health_event");
      res.writeHead(204).end();
      return;
    }
  }
  if (req.method !== "POST" || !handlers[name]) {
    res.writeHead(404).end();
    return;
  }
  try {
    const result = await handlers[name]();
    res.writeHead(200, {"content-type": "application/json"});
    res.end(JSON.stringify({ok: true, result: result || null}));
  } catch (error) {
    console.error("payment_scheduler_failed", {name, message: error && error.message});
    res.writeHead(500, {"content-type": "application/json"});
    res.end(JSON.stringify({ok: false}));
  }
});

if (require.main === module) {
  server.listen(Number(process.env.PORT || 8080), "0.0.0.0");
}

module.exports = {eventHandlerName, topicHandlerName, handlers, server};
