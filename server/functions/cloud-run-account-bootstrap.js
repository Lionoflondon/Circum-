/* eslint-disable max-len, require-jsdoc */
"use strict";

const http = require("node:http");
const {initializeApp, getApps} = require("firebase-admin/app");
const {getAppCheck} = require("firebase-admin/app-check");
const {getAuth} = require("firebase-admin/auth");
const senderAccount = require("./sender-account");
const senderNotificationState = require("./sender-notification-state");
const riderAccount = require("./rider-account");
const rothLedger = require("./roth-ledger");

const MAX_BODY_BYTES = 16 * 1024;
const WINDOW_MS = 60 * 1000;
const MAX_REQUESTS_PER_WINDOW = 30;
const OPERATIONS = Object.freeze({
  ensureSenderAccount: {handler: senderAccount.ensureSenderAccount, appCheckRequired: false},
  updateSenderNotificationState: {handler: {run: senderNotificationState.updateSenderNotificationState}, appCheckRequired: true},
  getSenderWalletTransactions: {handler: {run: rothLedger.readSenderWalletTransactions}, appCheckRequired: true},
  verifyRiderAccountAccess: {handler: riderAccount.verifyRiderAccountAccess, appCheckRequired: true},
  advanceRiderOnboarding: {handler: riderAccount.advanceRiderOnboarding, appCheckRequired: true},
  updateRiderProfile: {handler: riderAccount.updateRiderProfile, appCheckRequired: true},
  submitRiderApplication: {handler: riderAccount.submitRiderApplication, appCheckRequired: true},
});
const STATUS = {
  "already-exists": "ALREADY_EXISTS",
  "invalid-argument": "INVALID_ARGUMENT",
  unauthenticated: "UNAUTHENTICATED",
  "permission-denied": "PERMISSION_DENIED",
  "failed-precondition": "FAILED_PRECONDITION",
  "resource-exhausted": "RESOURCE_EXHAUSTED",
  unavailable: "UNAVAILABLE",
  "not-found": "NOT_FOUND",
  internal: "INTERNAL",
};

function callableError(code, message) {
  return Object.assign(new Error(message), {code});
}

function clean(value, max = 4096) {
  return String(value || "").trim().slice(0, max);
}

function bearer(request) {
  const match = /^Bearer ([^\s]+)$/.exec(String(request.headers.authorization || ""));
  return match && match[1];
}

function routeName(url) {
  const pathname = new URL(url || "/", "http://localhost").pathname;
  const match = /^(?:\/v1\/callable)?\/(ensureSenderAccount|updateSenderNotificationState|getSenderWalletTransactions|verifyRiderAccountAccess|advanceRiderOnboarding|updateRiderProfile|submitRiderApplication)$/.exec(pathname);
  return match && Object.prototype.hasOwnProperty.call(OPERATIONS, match[1]) ? match[1] : null;
}

function createRateLimiter(options = {}) {
  const now = options.now || Date.now;
  const entries = new Map();
  return (key) => {
    const timestamp = now();
    const previous = entries.get(key);
    const entry = !previous || timestamp - previous.startedAt >= WINDOW_MS ? {startedAt: timestamp, count: 0} : previous;
    entry.count += 1;
    entries.set(key, entry);
    return entry.count <= (options.limit || MAX_REQUESTS_PER_WINDOW);
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
    "access-control-allow-headers": "Authorization, Content-Type, X-Firebase-AppCheck",
    "access-control-allow-methods": "POST, OPTIONS",
  });
  response.end(JSON.stringify(body));
}

function createServer(options = {}) {
  const dependenciesFactory = options.dependenciesFactory || productionDependencies;
  const allowRequest = options.allowRequest || createRateLimiter();
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
      if (size > MAX_BODY_BYTES) return writeJson(response, 413, {error: {status: "INVALID_ARGUMENT", message: "Request too large."}});
      try {
        if (!dependencies) dependencies = dependenciesFactory();
        const operation = dependencies.operations[name];
        const idToken = bearer(request);
        if (!idToken) throw callableError("unauthenticated", "Sign in to continue.");
        let decoded;
        try {
          decoded = await dependencies.verifyIdToken(idToken);
        } catch {
          throw callableError("unauthenticated", "Sign in to continue.");
        }
        const uid = decoded && (decoded.uid || decoded.sub);
        if (!uid) throw callableError("unauthenticated", "Invalid authentication token.");
        let app;
        if (operation.appCheckRequired) {
          const appCheckToken = clean(request.headers["x-firebase-appcheck"]);
          if (!appCheckToken) throw callableError("failed-precondition", "Circum security verification is required.");
          try {
            app = await dependencies.verifyAppCheck(appCheckToken);
          } catch {
            throw callableError("unauthenticated", "Sign in to continue.");
          }
        }
        if (!allowRequest(`${uid}:${name}`)) throw callableError("resource-exhausted", "Too many account requests. Try again shortly.");
        const payload = JSON.parse(Buffer.concat(chunks).toString("utf8") || "{}");
        if (!payload.data || typeof payload.data !== "object" || Array.isArray(payload.data)) {
          throw callableError("invalid-argument", "Callable request must contain data.");
        }
        const context = {auth: {uid, token: decoded}, app, rawRequest: request};
        const result = await operation.handler.run(payload.data, context);
        return writeJson(response, 200, {result});
      } catch (error) {
        const rawCode = String(error.code || "internal").replace(/^functions\//, "");
        const code = rawCode.startsWith("app-check/") ? "failed-precondition" : rawCode.startsWith("auth/") ? "unauthenticated" : rawCode;
        const status = code === "unauthenticated" ? 401 : code === "permission-denied" ? 403 : code === "not-found" ? 404 : code === "already-exists" ? 409 : code === "resource-exhausted" ? 429 : ["invalid-argument", "failed-precondition"].includes(code) ? 400 : code === "unavailable" ? 503 : 500;
        if (status >= 500) console.error("account_bootstrap_failed", {operation: name, reason: code});
        const message = {
          "already-exists": "The request conflicts with the current state.",
          "invalid-argument": "The request is invalid.",
          unauthenticated: "Sign in to continue.",
          "permission-denied": "You do not have access to this resource.",
          "failed-precondition": "Security verification is required.",
          "resource-exhausted": "Too many account requests. Try again shortly.",
          unavailable: "The account service is temporarily unavailable.",
          "not-found": "The requested resource was not found.",
        }[code] || "Account request failed.";
        return writeJson(response, status, {error: {status: STATUS[code] || "INTERNAL", message}});
      }
    });
  });
}

if (require.main === module) createServer().listen(Number(process.env.PORT || 8080), "0.0.0.0");

module.exports = {createRateLimiter, createServer, productionDependencies, routeName, MAX_BODY_BYTES};
