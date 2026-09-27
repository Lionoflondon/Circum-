/* eslint-disable max-len, require-jsdoc */
"use strict";

const http = require("node:http");
const {initializeApp, getApps} = require("firebase-admin/app");
const {getAuth} = require("firebase-admin/auth");
const {getAppCheck} = require("firebase-admin/app-check");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {classifyIris, customerSafeIris} = require("./iris-core");
const {loadLearningExamples} = require("./iris")._private;
const {buildPhotoAnalysis, decodeBase64Image, detectImageType} = require("./iris-photo-analysis")._private;

const ROUTES = new Set(["analyseIris", "analyseParcelPhotoForIris"]);
const MAX_BODY_BYTES = 14 * 1024 * 1024;
const STATUS = {"invalid-argument": "INVALID_ARGUMENT", unauthenticated: "UNAUTHENTICATED", "permission-denied": "PERMISSION_DENIED", "failed-precondition": "FAILED_PRECONDITION", "resource-exhausted": "RESOURCE_EXHAUSTED", unavailable: "UNAVAILABLE", internal: "INTERNAL"};
const QA_FAULT_MODES = new Set(["unavailable", "rate_limit", "malformed"]);
const error = (code, message) => Object.assign(new Error(message), {code});

function qaFaultModeFor({data, uid, env = process.env}) {
  const mode = data && data.qaFaultMode;
  if (mode === undefined) return null;
  if (!QA_FAULT_MODES.has(mode)) throw error("invalid-argument", "Unsupported QA fault mode.");
  if (env.GCLOUD_PROJECT !== "circum-2797c" || env.STRIPE_MODE !== "TEST" || env.QA_LIFECYCLE_ENABLED !== "true") {
    throw error("permission-denied", "QA fault injection is not permitted.");
  }
  let credentials;
  try {
    credentials = JSON.parse(env.CIRCUM_QA_CERTIFICATION_CREDENTIALS || "");
  } catch (_) {
    throw error("permission-denied", "QA fault injection is not permitted.");
  }
  const identities = credentials && credentials.identities;
  const allowlisted = ["admin", "sender", "rider"].some((role) => identities && identities[role] && identities[role].uid === uid);
  if (!allowlisted) throw error("permission-denied", "QA fault injection is not permitted.");
  return mode;
}

function createHandlers({db = getFirestore(), examples = loadLearningExamples} = {}) {
  return {
    async analyseIris(data) {
      const description = String(data.description || data.packageDescription || "").trim();
      const completedExamples = await examples(description);
      return customerSafeIris(classifyIris({...data, completedExamples}));
    },
    async analyseParcelPhotoForIris(data, context) {
      const bytes = decodeBase64Image(data);
      const contentType = detectImageType(bytes, data.contentType);
      const analysis = buildPhotoAnalysis({uid: context.auth.uid, data, bytes, contentType});
      await db.collection("irisPhotoAnalyses").doc(analysis.analysisId).set({...analysis, createdAt: FieldValue.serverTimestamp(), expiresAt: new Date(Date.now() + 24 * 60 * 60 * 1000)}, {merge: true});
      return {...analysis, imageHash: undefined, descriptionHash: undefined};
    },
  };
}

function productionDependencies() {
  if (!getApps().length) initializeApp();
  return {verifyIdToken: (token) => getAuth().verifyIdToken(token, true), verifyAppCheck: (token) => getAppCheck().verifyToken(token), handlers: createHandlers()};
}

function writeJson(response, status, body) {
  response.writeHead(status, {"content-type": "application/json; charset=utf-8", "cache-control": "no-store", "access-control-allow-origin": "*", "access-control-allow-headers": "Authorization, Content-Type, X-Firebase-AppCheck", "access-control-allow-methods": "POST, OPTIONS"});
  response.end(JSON.stringify(body));
}

function createRateLimiter({now = Date.now, limit = 30} = {}) {
  const entries = new Map();
  return (key) => {
    const time = now(); const prior = entries.get(key);
    const next = !prior || time - prior.startedAt > 60000 ? {startedAt: time, count: 0} : prior;
    next.count += 1; entries.set(key, next);
    return next.count <= limit;
  };
}

function createServer({dependenciesFactory = productionDependencies, allowRequest = createRateLimiter(), env = process.env} = {}) {
  let dependencies;
  return http.createServer((request, response) => {
    if (request.method === "GET" && ["/health", "/healthz"].includes(request.url)) return writeJson(response, 200, {status: "ok", source: process.env.CIRCUM_SOURCE_SHA || "unknown", operations: [...ROUTES]});
    if (request.method === "OPTIONS") return writeJson(response, 204, {});
    const match = /^(?:\/v1\/callable)?\/(analyseIris|analyseParcelPhotoForIris)$/.exec(new URL(request.url || "/", "http://localhost").pathname);
    const route = match && match[1];
    if (!route || !ROUTES.has(route)) return writeJson(response, 404, {error: {status: "NOT_FOUND", message: "Not found."}});
    if (request.method !== "POST") return writeJson(response, 405, {error: {status: "INVALID_ARGUMENT", message: "POST required."}});
    if (!String(request.headers["content-type"] || "").toLowerCase().startsWith("application/json")) return writeJson(response, 415, {error: {status: "INVALID_ARGUMENT", message: "JSON required."}});
    let size = 0; const chunks = [];
    request.on("data", (chunk) => {
      size += chunk.length;
      if (size <= MAX_BODY_BYTES) chunks.push(chunk);
    });
    request.on("end", async () => {
      if (size > MAX_BODY_BYTES) return writeJson(response, 413, {error: {status: "INVALID_ARGUMENT", message: "Request too large."}});
      try {
        const authMatch = /^Bearer ([^\s]+)$/.exec(String(request.headers.authorization || ""));
        if (!authMatch) throw error("unauthenticated", "Sign in to continue.");
        const appCheckToken = String(request.headers["x-firebase-appcheck"] || "").trim();
        if (!appCheckToken) throw error("failed-precondition", "Circum security verification is required.");
        if (!dependencies) dependencies = dependenciesFactory();
        const [decoded] = await Promise.all([dependencies.verifyIdToken(authMatch[1]), dependencies.verifyAppCheck(appCheckToken)]);
        const uid = decoded && (decoded.uid || decoded.sub);
        if (!uid) throw error("unauthenticated", "Invalid authentication token.");
        const body = JSON.parse(Buffer.concat(chunks).toString("utf8") || "{}");
        if (!body.data || typeof body.data !== "object" || Array.isArray(body.data)) throw error("invalid-argument", "Callable request must contain data.");
        if (!allowRequest(uid)) throw error("resource-exhausted", "Too many IRIS requests. Try again shortly.");
        const qaFaultMode = qaFaultModeFor({data: body.data, uid, env});
        if (qaFaultMode === "unavailable") throw error("unavailable", "QA fault injection requested.");
        if (qaFaultMode === "rate_limit") throw error("resource-exhausted", "QA fault injection requested.");
        if (qaFaultMode === "malformed") throw error("internal", "QA fault injection requested.");
        const result = await dependencies.handlers[route](body.data, {auth: {uid, token: decoded}});
        return writeJson(response, 200, {result});
      } catch (failure) {
        const rawCode = String(failure.code || "internal").replace(/^functions\//, "");
        const code = rawCode.startsWith("app-check/") || rawCode.startsWith("auth/") ? "unauthenticated" : rawCode;
        const status = code === "unauthenticated" ? 401 : code === "permission-denied" ? 403 : code === "resource-exhausted" ? 429 : code === "unavailable" ? 503 : ["invalid-argument", "failed-precondition"].includes(code) ? 400 : 500;
        if (status >= 500) console.error("iris_request_failed", {operation: route, reason: code});
        return writeJson(response, status, {error: {status: STATUS[code] || "INTERNAL", message: status >= 500 ? "IRIS request failed. Try again." : failure.message}});
      }
    });
  });
}

if (require.main === module) createServer().listen(Number(process.env.PORT || 8080), "0.0.0.0");
module.exports = {createHandlers, createRateLimiter, createServer, productionDependencies, MAX_BODY_BYTES, qaFaultModeFor, QA_FAULT_MODES};
