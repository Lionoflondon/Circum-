"use strict";

const http = require("node:http");

const MAX_BODY_BYTES = 1024 * 1024;
const ROUTES = Object.freeze({
  "/getSenderPaymentMode": "getSenderPaymentMode",
  "/createSenderPaymentSession": "createSenderPaymentSession",
  "/createSenderPaidDelivery": "createSenderPaidDelivery",
  "/finalizeSenderWebCheckout": "finalizeSenderWebCheckout",
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

function createSenderDeliveryPaymentsServer(handlers) {
  for (const name of Object.values(ROUTES)) {
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
        service: "sender-delivery-payments",
        mode: String(process.env.STRIPE_MODE || "").toLowerCase(),
      });
    }
    const handlerName = ROUTES[path];
    if (!handlerName) return res.status(404).send({error: "not_found"});
    if (req.method !== "POST") return res.status(405).send({error: "method_not_allowed"});

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
  const functions = require("./index");
  const port = Number(process.env.PORT || 8080);
  createSenderDeliveryPaymentsServer({
    getSenderPaymentMode: functions.getSenderPaymentMode,
    createSenderPaymentSession: functions.createSenderPaymentSession,
    createSenderPaidDelivery: functions.createSenderPaidDelivery,
    finalizeSenderWebCheckout: functions.finalizeSenderWebCheckout,
  }).listen(port, "0.0.0.0");
}

module.exports = {createSenderDeliveryPaymentsServer, ROUTES};
