"use strict";

const http = require("node:http");

const MAX_BODY_BYTES = 1024 * 1024;
const FAMILY_ROUTES = Object.freeze({
  health_plus: [
    "createHealthPlusBillingPortalSession",
    "createHealthPlusCheckoutSession",
  ],
  business_invoices: [
    "createBusinessInvoiceCheckout",
    "cancelBusinessInvoiceCheckout",
  ],
  gifts: ["createGiftPayment", "finalizeGiftPayment", "cancelGiftPayment"],
  tips: ["submitDeliveryTip", "refundDeliveryTip"],
  delivery_adjustments: [
    "createDeliveryAdjustmentPayment",
    "finalizeDeliveryAdjustmentPayment",
  ],
  sender_cancellation: ["requestSenderCancellation", "cancelDelivery"],
  rider_connect_accounts: [
    "createStripeConnectAccountForRider",
    "createStripeOnboardingLink",
    "refreshStripeOnboardingLink",
    "syncStripeConnectStatus",
    "createStripeAccountManagementLink",
  ],
  rider_payouts: [
    "riderPayoutReadiness",
    "createRiderTransferOrPayout",
    "requestRiderWithdrawal",
    "cancelRiderWithdrawal",
    "adminReviewRiderWithdrawal",
  ],
});

function addExpressCompatibility(req, res) {
  req.header = (name) => req.headers[String(name).toLowerCase()];
  req.get = req.header;
  res.status = (code) => {
    res.statusCode = code;
    return res;
  };
  res.send = (body) => {
    if (body !== undefined && typeof body === "object" && !Buffer.isBuffer(body)) {
      res.setHeader("content-type", "application/json; charset=utf-8");
      res.end(JSON.stringify(body));
    } else {
      res.end(body);
    }
    return res;
  };
  res.json = res.send;
  res.set = (name, value) => {
    res.setHeader(name, value);
    return res;
  };
}

function createPaymentFamilyServer({family, handlers}) {
  const routeNames = FAMILY_ROUTES[family];
  if (!routeNames) throw new TypeError(`Unsupported payment family: ${family}`);
  for (const name of routeNames) {
    if (typeof handlers?.[name] !== "function") {
      throw new TypeError(`${name} handler is required`);
    }
  }
  return http.createServer((req, res) => {
    addExpressCompatibility(req, res);
    const path = new URL(req.url || "/", "http://localhost").pathname;
    if (path === "/healthz") {
      return res.status(200).send({
        status: "ok",
        family,
        mode: String(process.env.STRIPE_MODE || "").toLowerCase(),
      });
    }
    const handlerName = path.slice(1);
    if (!routeNames.includes(handlerName)) {
      return res.status(404).send({error: "not_found"});
    }
    if (req.method !== "POST" && req.method !== "OPTIONS") {
      return res.status(405).send({error: "method_not_allowed"});
    }
    const chunks = [];
    let size = 0;
    req.on("data", (chunk) => {
      size += chunk.length;
      if (size > MAX_BODY_BYTES) req.destroy(new Error("request_too_large"));
      else chunks.push(chunk);
    });
    req.on("end", async () => {
      try {
        req.rawBody = Buffer.concat(chunks);
        req.body = req.rawBody.length ? JSON.parse(req.rawBody.toString("utf8")) : {};
        await handlers[handlerName](req, res);
      } catch (_error) {
        if (!res.headersSent) res.status(400).send({error: "invalid_request"});
        else if (!res.writableEnded) res.end();
      }
    });
  });
}

if (require.main === module) {
  const family = String(process.env.PAYMENT_FAMILY || "").trim();
  const functions = require("./index");
  const routeNames = FAMILY_ROUTES[family] || [];
  const handlers = Object.fromEntries(routeNames.map((name) => [name, functions[name]]));
  const port = Number(process.env.PORT || 8080);
  createPaymentFamilyServer({family, handlers}).listen(port, "0.0.0.0");
}

module.exports = {createPaymentFamilyServer, FAMILY_ROUTES};
