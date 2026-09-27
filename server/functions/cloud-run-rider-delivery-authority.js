/* eslint-disable max-len, require-jsdoc */
"use strict";

const http = require("node:http");
const {initializeApp, getApps} = require("firebase-admin/app");
const {getAppCheck} = require("firebase-admin/app-check");
const {getAuth} = require("firebase-admin/auth");
const {getFirestore} = require("firebase-admin/firestore");
const {completeDeliveryHandler} = require("./delivery-completion-reconciled")._private;
const deliveryTracking = require("./delivery-tracking");
const {getOffers} = require("./rider-offers");
const qaPublic = require("./qa-public-delivery");
const riderPresence = require("./rider-presence");

const MAX_BODY_BYTES = 32 * 1024;
const ROUTES = new Set([
  "completeDelivery",
  "acceptRideRequests",
  "recordRiderArrival",
  "updateDeliveryTrackingStatus",
  "updateDeliveryLiveLocation",
  "getAvailableRequests",
  "getAvaliableRequests",
  "getNearbyRequests",
  "goOnline",
  "goOffline",
  "updateRiderPresence",
]);
const DEFAULT_ALLOWED_ORIGINS = Object.freeze(new Set([
  "https://circum-rider-2797c.web.app",
  "https://circum-rider-2797c.firebaseapp.com",
]));
const STATUS = {
  "invalid-argument": "INVALID_ARGUMENT",
  unauthenticated: "UNAUTHENTICATED",
  "permission-denied": "PERMISSION_DENIED",
  "not-found": "NOT_FOUND",
  "failed-precondition": "FAILED_PRECONDITION",
  "resource-exhausted": "RESOURCE_EXHAUSTED",
  unavailable: "UNAVAILABLE",
  "deadline-exceeded": "DEADLINE_EXCEEDED",
  internal: "INTERNAL",
};

function callableError(code, message) {
  return Object.assign(new Error(message), {code});
}

function clean(value, max = 4096) {
  return String(value || "").trim().slice(0, max);
}

function createHandlers(options = {}) {
  const db = options.db || getFirestore();
  const qaOnly = (operation) => async (data, context) => {
    const result = await operation(data, context);
    if (!result) throw callableError("permission-denied", "QA delivery access is not permitted.");
    return result;
  };
  return {
    completeDelivery: (data, context) => completeDeliveryHandler(data, context, db),
    acceptRideRequests: qaOnly((data, context) => qaPublic.accept({
      db,
      context,
      deliveryId: data && (data.requestId || data.deliveryId),
    })),
    recordRiderArrival: qaOnly((data, context) => qaPublic.arrive({
      db,
      context,
      deliveryId: data && data.deliveryId,
      phase: data && data.phase,
    })),
    updateDeliveryTrackingStatus: (data, context) => deliveryTracking.updateDeliveryTrackingStatus.run(data, context),
    updateDeliveryLiveLocation: (data, context) => deliveryTracking.updateDeliveryLiveLocation.run(data, context),
    getAvailableRequests: (data, context) => getOffers(data, context, db),
    getAvaliableRequests: (data, context) => getOffers(data, context, db),
    getNearbyRequests: (data, context) => getOffers(data, context, db),
    goOnline: (data, context) => riderPresence.goOnline.run(data, context),
    goOffline: (data, context) => riderPresence.goOffline.run(data, context),
    updateRiderPresence: (data, context) => riderPresence.updateRiderPresence.run(data, context),
  };
}

function productionDependencies() {
  if (!getApps().length) initializeApp();
  return {
    verifyIdToken: (token) => getAuth().verifyIdToken(token, true),
    verifyAppCheck: (token) => getAppCheck().verifyToken(token),
    handlers: createHandlers(),
  };
}

function configuredAllowedOrigins(options = {}) {
  if (options.allowedOrigins instanceof Set) return options.allowedOrigins;
  const configured = String(process.env.CIRCUM_ALLOWED_RIDER_ORIGINS || "")
      .split(",")
      .map((origin) => origin.trim())
      .filter(Boolean);
  return new Set(configured.length ? configured : DEFAULT_ALLOWED_ORIGINS);
}

function writeJson(response, status, body, {origin = "", allowedOrigins = DEFAULT_ALLOWED_ORIGINS} = {}) {
  const headers = {
    "content-type": "application/json; charset=utf-8",
    "cache-control": "no-store",
  };
  if (origin && allowedOrigins.has(origin)) {
    headers["access-control-allow-origin"] = origin;
    headers["access-control-allow-headers"] = "Authorization, Content-Type, X-Firebase-AppCheck";
    headers["access-control-allow-methods"] = "POST, OPTIONS";
    headers.vary = "Origin";
  }
  response.writeHead(status, headers);
  response.end(JSON.stringify(body));
}

function bearer(request) {
  const match = /^Bearer ([^\s]+)$/.exec(String(request.headers.authorization || ""));
  return match && match[1];
}

function routeName(url) {
  const pathname = new URL(url || "/", "http://localhost").pathname;
  const match = /^(?:\/v1\/callable)?\/(completeDelivery|acceptRideRequests|recordRiderArrival|updateDeliveryTrackingStatus|updateDeliveryLiveLocation|getAvailableRequests|getAvaliableRequests|getNearbyRequests|goOnline|goOffline|updateRiderPresence)$/.exec(pathname);
  return match && ROUTES.has(match[1]) ? match[1] : null;
}

function statusCode(code) {
  if (code === "unauthenticated") return 401;
  if (code === "permission-denied") return 403;
  if (code === "not-found") return 404;
  if (["invalid-argument", "failed-precondition"].includes(code)) return 400;
  if (code === "resource-exhausted") return 429;
  if (code === "unavailable") return 503;
  if (code === "deadline-exceeded") return 504;
  return 500;
}

function createServer(options = {}) {
  const dependenciesFactory = options.dependenciesFactory || productionDependencies;
  const allowedOrigins = configuredAllowedOrigins(options);
  let dependencies;
  return http.createServer((request, response) => {
    const origin = String(request.headers.origin || "");
    if (origin && !allowedOrigins.has(origin)) {
      return writeJson(response, 403, {error: {status: "PERMISSION_DENIED", message: "This Rider Web origin is not permitted."}}, {origin, allowedOrigins});
    }
    if (request.method === "GET" && ["/health", "/healthz"].includes(request.url)) {
      return writeJson(response, 200, {status: "ok", runtime: "node22", source: process.env.CIRCUM_SOURCE_SHA || "unknown"}, {origin, allowedOrigins});
    }
    if (request.method === "OPTIONS") return writeJson(response, 204, {}, {origin, allowedOrigins});
    const name = routeName(request.url);
    if (!name) return writeJson(response, 404, {error: {status: "NOT_FOUND", message: "Not found."}}, {origin, allowedOrigins});
    if (request.method !== "POST") return writeJson(response, 405, {error: {status: "INVALID_ARGUMENT", message: "POST required."}}, {origin, allowedOrigins});
    if (!String(request.headers["content-type"] || "").toLowerCase().startsWith("application/json")) {
      return writeJson(response, 415, {error: {status: "INVALID_ARGUMENT", message: "JSON required."}}, {origin, allowedOrigins});
    }
    let size = 0;
    const chunks = [];
    request.on("data", (chunk) => {
      size += chunk.length;
      if (size <= MAX_BODY_BYTES) chunks.push(chunk);
    });
    request.on("end", async () => {
      if (size > MAX_BODY_BYTES) return writeJson(response, 413, {error: {status: "INVALID_ARGUMENT", message: "Request too large."}}, {origin, allowedOrigins});
      try {
        const idToken = bearer(request);
        if (!idToken) throw callableError("unauthenticated", "Sign in to continue.");
        const appCheckToken = clean(request.headers["x-firebase-appcheck"]);
        if (!appCheckToken) throw callableError("failed-precondition", "Circum Rider security verification is required.");
        if (!dependencies) dependencies = dependenciesFactory();
        const [decoded, decodedAppCheck] = await Promise.all([
          dependencies.verifyIdToken(idToken),
          dependencies.verifyAppCheck(appCheckToken),
        ]);
        if (!decoded || !(decoded.uid || decoded.sub)) throw callableError("unauthenticated", "Invalid authentication token.");
        const payload = JSON.parse(Buffer.concat(chunks).toString("utf8") || "{}");
        if (!payload.data || typeof payload.data !== "object" || Array.isArray(payload.data)) {
          throw callableError("invalid-argument", "Callable request must contain object data.");
        }
        const context = {
          auth: {uid: decoded.uid || decoded.sub, token: decoded},
          app: decodedAppCheck,
        };
        const result = await dependencies.handlers[name](payload.data, context);
        return writeJson(response, 200, {result}, {origin, allowedOrigins});
      } catch (error) {
        const rawCode = String(error.code || "internal").replace(/^functions\//, "");
        const code = rawCode.startsWith("app-check/") || rawCode.startsWith("auth/") ? "unauthenticated" : rawCode;
        const status = statusCode(code);
        if (status === 500) console.error("rider_delivery_authority_failed", {callable: name, reason: code});
        return writeJson(response, status, {error: {status: STATUS[code] || "INTERNAL", message: status === 500 ? "Rider delivery request failed." : error.message}}, {origin, allowedOrigins});
      }
    });
  });
}

if (require.main === module) createServer().listen(Number(process.env.PORT || 8080), "0.0.0.0");

module.exports = {createServer, createHandlers, productionDependencies, routeName, MAX_BODY_BYTES, DEFAULT_ALLOWED_ORIGINS};
