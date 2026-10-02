"use strict";

const http = require("node:http");
const {initializeApp, getApps} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const {resolveStripeRuntimeConfig} = require("./stripe-config");
const businessPayments = require("./business-payments");
const riderEarnings = require("./rider-earnings-summary");
const riderConnect = require("./rider-connect");
const deliveryTracking = require("./delivery-tracking");
const healthPlusOperations = require("./health-plus-operations");
const ratingsTipping = require("./ratings-tipping");
const giftRecurring = require("./gift-recurring");
const healthMembershipLifecycle = require("./health-membership-lifecycle");

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
  scheduledRiderEarningsReconciliation: () =>
    riderEarnings.scheduledRiderEarningsReconciliationCore(),
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
  reconcileDeliveryTips: () =>
    ratingsTipping.reconcileDeliveryTipsCore(stripeClient()),
  reconcileDeliveryTipsDryRun: () =>
    ratingsTipping.reconcileDeliveryTipsCore(stripeClient(), {dryRun: true}),
  reconcileGiftRecurringRenewals: () =>
    giftRecurring.reconcileGiftRecurringRenewalsCore({stripe: stripeClient()}),
  reconcileHealthMembershipEvents: () =>
    healthMembershipLifecycle.reconcileHealthMembershipEventsCore({db: getFirestore(), stripe: stripeClient()}),
});

const TOPIC_HANDLER_BY_NAME = Object.freeze({
  "firebase-schedule-scheduledRiderEarningsReconciliation-us-central1": "scheduledRiderEarningsReconciliation",
  "firebase-schedule-reconcilePendingDeliverySettlements-us-central1": "reconcilePendingDeliverySettlements",
  "firebase-schedule-processHealthPlusReminders-us-central1": "processHealthPlusReminders",
  "firebase-schedule-reconcileDeliveryTips-us-central1": "reconcileDeliveryTips",
  "firebase-schedule-reconcileGiftRecurringRenewals-us-central1": "reconcileGiftRecurringRenewals",
  "firebase-schedule-reconcileHealthMembershipEvents-us-central1": "reconcileHealthMembershipEvents",
});

function topicHandlerName(requestUrl = "", headers = {}) {
  const rawUrl = String(requestUrl || "");
  const mode = new URL(rawUrl || "/", "http://localhost").searchParams.get("__GCP_CloudEventsMode") || "";
  const match = /^CUSTOM_PUBSUB_projects\/[^/]+\/topics\/([^/?]+)$/.exec(mode);
  if (match && TOPIC_HANDLER_BY_NAME[match[1]]) return TOPIC_HANDLER_BY_NAME[match[1]];
  for (const [topic, handler] of Object.entries(TOPIC_HANDLER_BY_NAME)) {
    if (rawUrl.includes(topic) || rawUrl.includes(encodeURIComponent(topic))) return handler;
  }
  const source = String(headers["ce-source"] || headers["x-goog-cloud-event-source"] || "");
  const sourceMatch = /\/topics\/([^/?]+)$/.exec(source);
  return sourceMatch ? TOPIC_HANDLER_BY_NAME[sourceMatch[1]] || "" : "";
}

function eventHandlerName(body, requestUrl = "", headers = {}) {
  const topicHandler = topicHandlerName(requestUrl, headers);
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
  if (require("./private-qa-cleanup-certifier").handle(req, res)) return;
  if (require("./legacy-recovery-http").handleRecovery(req, res, {
    workers: Object.keys(require("./legacy-scheduled-recovery").CONFIG).filter((name) => !name.startsWith("expireQa")),
    stripe: stripeClient,
    bucket: () => require("firebase-admin/storage").getStorage().bucket("circum-2797c.appspot.com"),
    fixtureStripe: () => ({paymentIntents: {retrieve: async () => {
throw new Error("fixture_provider_read_not_configured");
}}}),
    fixtureBucket: (db) => ({file: (path) => ({delete: async () => db.collection("fixtureStorageOperations").doc(require("node:crypto").createHash("sha256").update(path).digest("hex")).set({path, deleted: true})})}),
  })) return;
  const path = new URL(req.url, "http://localhost").pathname;
  if (req.method === "GET" && ["/health", "/healthz"].includes(path)) {
    res.writeHead(200, {"content-type": "application/json"});
    res.end(JSON.stringify({ok: true, service: "payment-schedulers", sourceSha: process.env.CIRCUM_SOURCE_SHA || process.env.SOURCE_SHA || "unknown"}));
    return;
  }
  let name = path.slice(1);
  if (req.method === "POST" && (path === "/" || path === "/events")) {
    name = eventHandlerName(await readJson(req), req.url, req.headers);
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
