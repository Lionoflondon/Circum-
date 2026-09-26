/* eslint-disable max-len, require-jsdoc */
"use strict";

const http = require("node:http");
const {initializeApp, getApps} = require("firebase-admin/app");
const {getAppCheck} = require("firebase-admin/app-check");
const {getAuth} = require("firebase-admin/auth");
const {getFirestore} = require("firebase-admin/firestore");

const MAX_BODY_BYTES = 32 * 1024;
const ROUTE = "qaSpecialFlowFixture";
const STATUS = {
  "invalid-argument": "INVALID_ARGUMENT",
  unauthenticated: "UNAUTHENTICATED",
  "permission-denied": "PERMISSION_DENIED",
  "failed-precondition": "FAILED_PRECONDITION",
  unavailable: "UNAVAILABLE",
  internal: "INTERNAL",
};

function callableError(code, message) {
  return Object.assign(new Error(message), {code});
}

function writeJson(response, status, body) {
  response.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "cache-control": "no-store",
    "access-control-allow-origin": "*",
    "access-control-allow-headers": "Authorization, Content-Type, X-Firebase-AppCheck, X-Firebase-Auth",
    "access-control-allow-methods": "POST, OPTIONS",
  });
  response.end(JSON.stringify(body));
}

function firebaseToken(request) {
  const value = request.headers["x-firebase-auth"];
  const match = /^Bearer ([^\s]+)$/.exec(String(value || ""));
  return match && match[1];
}

function routeName(url) {
  const pathname = new URL(url || "/", "http://localhost").pathname;
  return /^\/(?:v1\/callable\/)?qaSpecialFlowFixture$/.test(pathname) ? ROUTE : null;
}

function allowlistFromCredentials(raw) {
  let credentials;
  try {
    credentials = JSON.parse(raw || "");
  } catch (_) {
    throw callableError("failed-precondition", "QA configuration is unavailable.");
  }
  const identities = credentials && credentials.identities;
  const uid = (role) => identities && identities[role] && identities[role].uid;
  const lists = {operators: [uid("admin")], senders: [uid("sender")], riders: [uid("rider")]};
  if (Object.values(lists).some((values) => !values[0] || typeof values[0] !== "string")) {
    throw callableError("failed-precondition", "QA configuration is unavailable.");
  }
  return lists;
}

function productionDependencies() {
  if (!getApps().length) initializeApp();
  const secret = process.env.CIRCUM_QA_STRIPE_SECRET_KEY;
  if (!secret || !secret.startsWith("sk_test_")) throw callableError("failed-precondition", "QA TEST provider is unavailable.");
  const {factory} = require("./qa-special-flow")._test;
  const stripe = require("stripe")(secret, {timeout: 20000, maxNetworkRetries: 1});
  const env = {
    GCLOUD_PROJECT: process.env.GCLOUD_PROJECT,
    STRIPE_MODE: "TEST",
    QA_LIFECYCLE_ENABLED: "true",
    QA_LIFECYCLE_ALLOWLIST: JSON.stringify(allowlistFromCredentials(process.env.CIRCUM_QA_CERTIFICATION_CREDENTIALS)),
    CIRCUM_QA_STRIPE_SECRET_KEY: secret,
    GOOGLE_MAPS_DIRECTIONS_API_KEY: process.env.GOOGLE_MAPS_DIRECTIONS_API_KEY,
  };
  return {
    verifyIdToken: (token) => getAuth().verifyIdToken(token, true),
    verifyAppCheck: (token) => getAppCheck().verifyToken(token),
    handler: factory({db: getFirestore(), env, stripe}).handle,
  };
}

function errorResponse(error) {
  const code = String(error.code || "internal").replace(/^functions\//, "");
  const status = code === "unauthenticated" ? 401 :
    code === "permission-denied" ? 403 :
    code === "unavailable" ? 503 :
    ["invalid-argument", "failed-precondition"].includes(code) ? 400 : 500;
  return {
    status,
    payload: {error: {status: STATUS[code] || "INTERNAL", message: status >= 500 ? "QA certification request failed." : error.message}},
    code,
  };
}

function createServer(options = {}) {
  const dependenciesFactory = options.dependenciesFactory || productionDependencies;
  let dependencies;
  return http.createServer((request, response) => {
    if (request.method === "GET" && ["/health", "/healthz"].includes(request.url)) {
      return writeJson(response, 200, {
        status: "ok", runtime: "node22", service: "circum-qa-special-flow",
        source: process.env.CIRCUM_SOURCE_SHA || "unknown", stripeMode: "TEST",
      });
    }
    if (request.method === "OPTIONS") return writeJson(response, 204, {});
    if (!routeName(request.url)) return writeJson(response, 404, {error: {status: "NOT_FOUND", message: "Not found."}});
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
      let action = "unknown";
      try {
        if (!dependencies) dependencies = dependenciesFactory();
        const firebaseIdToken = firebaseToken(request);
        if (!firebaseIdToken) throw callableError("unauthenticated", "Sign in to continue.");
        const decoded = await dependencies.verifyIdToken(firebaseIdToken);
        const uid = decoded && (decoded.uid || decoded.sub);
        if (!uid) throw callableError("unauthenticated", "Invalid authentication token.");
        const appCheckToken = String(request.headers["x-firebase-appcheck"] || "").trim();
        if (!appCheckToken) throw callableError("failed-precondition", "Circum security verification is required.");
        const app = await dependencies.verifyAppCheck(appCheckToken);
        const payload = JSON.parse(Buffer.concat(chunks).toString("utf8") || "{}");
        if (!payload || typeof payload !== "object" || Array.isArray(payload) || !payload.data || typeof payload.data !== "object") {
          throw callableError("invalid-argument", "Callable request must contain data.");
        }
        action = String(payload.data.action || "unknown");
        const result = await dependencies.handler(payload.data, {
          auth: {uid, token: decoded},
          app: {appId: app.appId || app.sub},
          rawRequest: request,
        });
        console.info(JSON.stringify({event: "qa_special_flow_completed", action, outcome: "success"}));
        return writeJson(response, 200, {result});
      } catch (error) {
        const failure = errorResponse(error);
        console.info(JSON.stringify({event: "qa_special_flow_completed", action, outcome: "rejected", code: failure.code}));
        return writeJson(response, failure.status, failure.payload);
      }
    });
  });
}

if (require.main === module) createServer().listen(Number(process.env.PORT || 8080), "0.0.0.0");

module.exports = {createServer, productionDependencies, allowlistFromCredentials, errorResponse, routeName, MAX_BODY_BYTES};
