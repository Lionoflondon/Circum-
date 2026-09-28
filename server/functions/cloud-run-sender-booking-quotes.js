/* eslint-disable max-len, require-jsdoc */
"use strict";

const crypto = require("node:crypto");
const http = require("node:http");
const {initializeApp, getApps} = require("firebase-admin/app");
const {getAuth} = require("firebase-admin/auth");
const {getAppCheck} = require("firebase-admin/app-check");
const senderBooking = require("./sender-booking");

const MAX_BODY_BYTES = 64 * 1024;
const MAX_REQUESTS_PER_WINDOW = 120;
const WINDOW_MS = 60 * 1000;
const OPERATIONS = Object.freeze({
  createSenderBookingQuote: senderBooking.createSenderBookingQuote,
});
const STATUS = {
  "invalid-argument": "INVALID_ARGUMENT",
  unauthenticated: "UNAUTHENTICATED",
  "permission-denied": "PERMISSION_DENIED",
  "failed-precondition": "FAILED_PRECONDITION",
  "resource-exhausted": "RESOURCE_EXHAUSTED",
  unavailable: "UNAVAILABLE",
  "deadline-exceeded": "DEADLINE_EXCEEDED",
  aborted: "ABORTED",
  "not-found": "NOT_FOUND",
  "already-exists": "ALREADY_EXISTS",
  internal: "INTERNAL",
};

function callableError(code, message) {
  return Object.assign(new Error(message), {code});
}

function clean(value, max = 256) {
  return String(value || "").trim().slice(0, max);
}

function bearer(request) {
  const match = /^Bearer ([^\s]+)$/.exec(String(request.headers.authorization || ""));
  return match && match[1];
}

function routeName(url) {
  const pathname = new URL(url || "/", "http://localhost").pathname;
  const match = /^(?:\/v1\/callable)?\/(createSenderBookingQuote)$/.exec(pathname);
  return match && Object.prototype.hasOwnProperty.call(OPERATIONS, match[1]) ? match[1] : null;
}

function correlationId(request, payload) {
  const supplied = clean(
      request.headers["x-circum-correlation-id"] ||
      payload && payload.data && payload.data.quoteId ||
      "quote-request",
      160,
  );
  return crypto.createHash("sha256").update(supplied).digest("hex").slice(0, 16);
}

function createRateLimiter({now = Date.now, limit = MAX_REQUESTS_PER_WINDOW} = {}) {
  const entries = new Map();
  return (key) => {
    const timestamp = now();
    const previous = entries.get(key);
    const entry = !previous || timestamp - previous.startedAt >= WINDOW_MS ?
      {startedAt: timestamp, count: 0} : previous;
    entry.count += 1;
    entries.set(key, entry);
    return entry.count <= limit;
  };
}

function productionDependencies() {
  if (!getApps().length) initializeApp();
  return {
    verifyIdToken: (token) => getAuth().verifyIdToken(token, true),
    verifyAppCheck: (token) => getAppCheck().verifyToken(token),
    operations: OPERATIONS,
  };
}

function writeJson(response, status, body) {
  response.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "cache-control": "no-store",
    "access-control-allow-origin": "*",
    "access-control-allow-headers": "Authorization, Content-Type, X-Firebase-AppCheck, X-Circum-Correlation-Id",
    "access-control-allow-methods": "POST, OPTIONS",
  });
  response.end(JSON.stringify(body));
}

function statusFor(code) {
  if (code === "unauthenticated") return 401;
  if (code === "permission-denied") return 403;
  if (code === "resource-exhausted") return 429;
  if (code === "aborted" || code === "already-exists") return 409;
  if (code === "not-found") return 404;
  if (code === "unavailable") return 503;
  if (code === "deadline-exceeded") return 504;
  if (["invalid-argument", "failed-precondition"].includes(code)) return 400;
  return 500;
}

function createServer({dependenciesFactory = productionDependencies, allowRequest = createRateLimiter(), now = Date.now} = {}) {
  let dependencies;
  return http.createServer((request, response) => {
    if (request.method === "GET" && ["/health", "/healthz"].includes(request.url)) {
      return writeJson(response, 200, {
        status: "ok",
        runtime: "node22",
        source: process.env.CIRCUM_SOURCE_SHA || "unknown",
        operations: Object.keys(OPERATIONS),
      });
    }
    if (request.method === "OPTIONS") return writeJson(response, 204, {});
    const name = routeName(request.url);
    if (!name) return writeJson(response, 404, {error: {status: "NOT_FOUND", message: "Not found."}});
    if (request.method !== "POST") return writeJson(response, 405, {error: {status: "INVALID_ARGUMENT", message: "POST required."}});
    if (!String(request.headers["content-type"] || "").toLowerCase().startsWith("application/json")) {
      return writeJson(response, 415, {error: {status: "INVALID_ARGUMENT", message: "JSON required."}});
    }
    let size = 0;
    const chunks = [];
    request.on("data", (chunk) => {
      size += chunk.length;
      if (size <= MAX_BODY_BYTES) chunks.push(chunk);
    });
    request.on("end", async () => {
      const startedAt = now();
      let payload = {};
      let requestCorrelation = "quote-request";
      try {
        if (size > MAX_BODY_BYTES) throw callableError("invalid-argument", "Quote request is too large.");
        payload = JSON.parse(Buffer.concat(chunks).toString("utf8") || "{}");
        requestCorrelation = correlationId(request, payload);
        if (!dependencies) dependencies = dependenciesFactory();
        const idToken = bearer(request);
        if (!idToken) throw callableError("unauthenticated", "Sign in to continue.");
        const appCheckToken = String(request.headers["x-firebase-appcheck"] || "").trim();
        if (!appCheckToken) throw callableError("unauthenticated", "Circum security verification is required.");
        let decoded;
        try {
          decoded = await dependencies.verifyIdToken(idToken);
        } catch (failure) {
          console.warn("sender_quote_auth_rejected", {operation: name, reason: "auth"});
          throw failure;
        }
        let app;
        try {
          app = await dependencies.verifyAppCheck(appCheckToken);
        } catch (failure) {
          const verifierCode = String(failure && failure.code || "unknown")
            .replace(/[^a-zA-Z0-9/_-]/g, "")
            .slice(0, 80);
          console.warn("sender_quote_auth_rejected", {
            operation: name,
            reason: "app-check",
            verifierCode,
          });
          throw failure;
        }
        const uid = decoded && (decoded.uid || decoded.sub);
        if (!uid) throw callableError("unauthenticated", "Invalid authentication token.");
        if (!allowRequest(`${uid}:${name}`)) throw callableError("resource-exhausted", "Quote service is busy. Try again shortly.");
        if (!payload.data || typeof payload.data !== "object" || Array.isArray(payload.data)) {
          throw callableError("invalid-argument", "Callable request must contain data.");
        }
        console.info("sender_quote_request", {operation: name, correlationId: requestCorrelation});
        const result = await dependencies.operations[name].run(payload.data, {
          auth: {uid, token: decoded},
          app,
          rawRequest: request,
        });
        console.info("sender_quote_success", {
          operation: name,
          correlationId: requestCorrelation,
          durationMs: now() - startedAt,
        });
        return writeJson(response, 200, {result});
      } catch (failure) {
        const rawCode = String(failure.code || "internal").replace(/^functions\//, "");
        const code = rawCode.startsWith("app-check/") || rawCode.startsWith("auth/") ? "unauthenticated" : rawCode;
        const status = statusFor(code);
        if (status >= 500) {
          console.error("sender_quote_failed", {
            operation: name,
            correlationId: requestCorrelation,
            code,
            durationMs: now() - startedAt,
          });
        }
        return writeJson(response, status, {
          error: {
            status: STATUS[code] || "INTERNAL",
            message: status >= 500 ? "Delivery quote could not be prepared. Please try again." : failure.message,
          },
        });
      }
    });
  });
}

if (require.main === module) createServer().listen(Number(process.env.PORT || 8080), "0.0.0.0");

module.exports = {createRateLimiter, createServer, productionDependencies, routeName, statusFor, MAX_BODY_BYTES};
