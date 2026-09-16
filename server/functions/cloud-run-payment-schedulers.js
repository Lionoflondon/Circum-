"use strict";

const http = require("node:http");
const {initializeApp, getApps} = require("firebase-admin/app");
const {resolveStripeRuntimeConfig} = require("./stripe-config");
const businessPayments = require("./business-payments");
const riderConnect = require("./rider-connect");

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
});

function eventHandlerName(body) {
  const envelope = body && body.message ? body : body && body.data && body.data.message ? body.data : null;
  const encoded = envelope && envelope.message && envelope.message.data;
  if (!encoded) return "";
  try {
    const decoded = JSON.parse(Buffer.from(encoded, "base64").toString("utf8"));
    return typeof decoded.handler === "string" ? decoded.handler : "";
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
    name = eventHandlerName(await readJson(req));
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

module.exports = {eventHandlerName, handlers, server};
