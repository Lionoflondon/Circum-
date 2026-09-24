/* eslint-disable max-len, require-jsdoc */
"use strict";

const http = require("node:http");
const {initializeApp, getApps} = require("firebase-admin/app");
const {getAppCheck} = require("firebase-admin/app-check");
const {getAuth} = require("firebase-admin/auth");
const adminAuthority = require("./admin-operations-authority");

const MAX_BODY_BYTES = 16 * 1024;
const ROUTE = "adminResolveAccess";
const STATUS = {
  "invalid-argument": "INVALID_ARGUMENT",
  unauthenticated: "UNAUTHENTICATED",
  "permission-denied": "PERMISSION_DENIED",
  "failed-precondition": "FAILED_PRECONDITION",
  unavailable: "UNAVAILABLE",
  "deadline-exceeded": "DEADLINE_EXCEEDED",
  internal: "INTERNAL",
};

function callableError(code, message) {
  return Object.assign(new Error(message), {code});
}

function bearer(request) {
  const match = /^Bearer ([^\s]+)$/.exec(String(request.headers.authorization || ""));
  return match && match[1];
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

function productionDependencies() {
  if (!getApps().length) initializeApp();
  return {
    verifyIdToken: (token) => getAuth().verifyIdToken(token, true),
    verifyAppCheck: (token) => getAppCheck().verifyToken(token),
    handler: adminAuthority._private.resolveAdminAccess,
  };
}

function routeName(url) {
  const pathname = new URL(url || "/", "http://localhost").pathname;
  return /^\/(?:v1\/callable\/)?adminResolveAccess$/.test(pathname) ? ROUTE : null;
}

function errorResponse(error) {
  const rawCode = String(error.code || "internal").replace(/^functions\//, "");
  const code = rawCode.startsWith("app-check/") || rawCode.startsWith("auth/") ? "unauthenticated" : rawCode;
  const status = code === "unauthenticated" ? 401 :
    code === "permission-denied" ? 403 :
    code === "unavailable" ? 503 :
    code === "deadline-exceeded" ? 504 :
    ["invalid-argument", "failed-precondition"].includes(code) ? 400 : 500;
  return {
    status,
    payload: {
      error: {
        status: STATUS[code] || "INTERNAL",
        message: status >= 500 ? "Admin access request failed." : error.message,
      },
    },
    code,
  };
}

function createServer(options = {}) {
  const dependenciesFactory = options.dependenciesFactory || productionDependencies;
  let dependencies;
  return http.createServer((request, response) => {
    if (request.method === "GET" && ["/health", "/healthz"].includes(request.url)) {
      return writeJson(response, 200, {
        status: "ok",
        runtime: "node22",
        service: "circum-admin-access",
        source: process.env.CIRCUM_SOURCE_SHA || "unknown",
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
      try {
        const idToken = bearer(request);
        if (!idToken) throw callableError("unauthenticated", "Sign in to continue.");
        if (!dependencies) dependencies = dependenciesFactory();
        const decoded = await dependencies.verifyIdToken(idToken);
        const uid = decoded && (decoded.uid || decoded.sub);
        if (!uid) throw callableError("unauthenticated", "Invalid authentication token.");
        const appCheckToken = String(request.headers["x-firebase-appcheck"] || "").trim();
        if (!appCheckToken) throw callableError("failed-precondition", "Circum security verification is required.");
        const decodedAppCheck = await dependencies.verifyAppCheck(appCheckToken);
        const payload = JSON.parse(Buffer.concat(chunks).toString("utf8") || "{}");
        if (!payload || typeof payload !== "object" || Array.isArray(payload) ||
            !Object.prototype.hasOwnProperty.call(payload, "data") ||
            !payload.data || typeof payload.data !== "object" || Array.isArray(payload.data)) {
          throw callableError("invalid-argument", "Callable request must contain data.");
        }
        const result = await dependencies.handler(payload.data, {
          auth: {uid, token: decoded},
          app: decodedAppCheck,
          rawRequest: request,
        });
        return writeJson(response, 200, {result});
      } catch (error) {
        const failure = errorResponse(error);
        if (failure.status >= 500) {
          console.error("admin_access_failed", {route: ROUTE, reason: failure.code});
        }
        return writeJson(response, failure.status, failure.payload);
      }
    });
  });
}

if (require.main === module) createServer().listen(Number(process.env.PORT || 8080), "0.0.0.0");

module.exports = {createServer, errorResponse, productionDependencies, routeName, MAX_BODY_BYTES};
