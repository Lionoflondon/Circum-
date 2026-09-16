/* eslint-disable max-len */
"use strict";

const http = require("node:http");
const {getApp, getApps, initializeApp} = require("firebase-admin/app");
const {resolveFirebaseProjectId, resolveStripeRuntimeConfig} = require("./stripe-config");
const {handleStripeConnectWebhook} = require("./rider-connect");

const MAX_BODY_BYTES = 1024 * 1024;

function json(response, status, body) {
  response.writeHead(status, {"content-type": "application/json; charset=utf-8", "cache-control": "no-store"});
  response.end(JSON.stringify(body));
}

function createProductionHandler() {
  const firebaseApp = getApps().length ? getApp() : initializeApp();
  const firebaseProject = resolveFirebaseProjectId({firebaseApp});
  const runtimeConfig = resolveStripeRuntimeConfig({
    firebaseProject,
    webhookSecret: process.env.STRIPE_CONNECT_WEBHOOK_SECRET,
    requireWebhookSecret: true,
  });
  const stripe = require("stripe")(runtimeConfig.secretKey);
  stripe._circumStripeMode = runtimeConfig.mode;
  return handleStripeConnectWebhook(stripe);
}

function firebaseResponse(response) {
  return {
    status(code) {
      response.statusCode = code;
      return this;
    },
    send(body) {
      if (!response.headersSent) response.setHeader("content-type", "text/plain; charset=utf-8");
      response.end(typeof body === "string" ? body : JSON.stringify(body));
    },
    json(body) {
      if (!response.headersSent) response.setHeader("content-type", "application/json; charset=utf-8");
      response.end(JSON.stringify(body));
    },
  };
}

function createServer(options = {}) {
  const handlerFactory = options.handlerFactory || createProductionHandler;
  let handlerPromise;
  const getHandler = () => {
    if (!handlerPromise) handlerPromise = Promise.resolve().then(handlerFactory);
    return handlerPromise;
  };
  return http.createServer((request, response) => {
    if (request.method === "GET" && request.url === "/health") {
      return json(response, 200, {
        status: "ok",
        service: "stripe-connect-webhook",
        runtime: "node22",
        mode: String(process.env.STRIPE_MODE || "").toLowerCase(),
        source: process.env.CIRCUM_SOURCE_SHA || "unknown",
      });
    }
    if (request.url !== "/stripe/connect-webhook") return json(response, 404, {error: "not_found"});
    if (request.method !== "POST") return json(response, 405, {error: "method_not_allowed"});
    if (!String(request.headers["content-type"] || "").toLowerCase().startsWith("application/json")) {
      return json(response, 415, {error: "unsupported_media_type"});
    }
    let size = 0;
    let tooLarge = false;
    const chunks = [];
    request.on("data", (chunk) => {
      size += chunk.length;
      if (size > MAX_BODY_BYTES) tooLarge = true;
      else if (!tooLarge) chunks.push(chunk);
    });
    request.on("error", () => {
      if (!response.headersSent) json(response, 400, {error: "invalid_request"});
    });
    request.on("end", async () => {
      if (response.headersSent) return;
      if (tooLarge) return json(response, 413, {error: "request_too_large"});
      request.rawBody = Buffer.concat(chunks);
      try {
        const handler = await getHandler();
        await handler(request, firebaseResponse(response));
      } catch (error) {
        console.error("stripe_connect_webhook_failed", {reason: error && error.message ? error.message : "internal_error"});
        if (!response.headersSent) json(response, 500, {error: "webhook_processing_failed"});
      }
    });
  });
}

if (require.main === module) createServer().listen(Number(process.env.PORT || 8080), "0.0.0.0");

module.exports = {createServer, createProductionHandler, MAX_BODY_BYTES};
