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

const server = http.createServer(async (req, res) => {
  const path = new URL(req.url, "http://localhost").pathname;
  if (req.method === "GET" && path === "/healthz") {
    res.writeHead(200, {"content-type": "application/json"});
    res.end(JSON.stringify({ok: true, service: "payment-schedulers"}));
    return;
  }
  const name = path.slice(1);
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

module.exports = {handlers, server};
