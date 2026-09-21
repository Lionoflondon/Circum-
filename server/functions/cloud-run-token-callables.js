/* eslint-disable max-len, require-jsdoc */
"use strict";

const http = require("node:http");
const {initializeApp, getApps} = require("firebase-admin/app");
const {getAppCheck} = require("firebase-admin/app-check");
const {getAuth} = require("firebase-admin/auth");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const deviceTokenAuthority = require("./device-token-authority");

const MAX_BODY_BYTES = 32 * 1024;
const ROUTES = new Set([
  "updateSenderPushToken",
  "updateRiderPushToken",
  "sendRiderUpdate",
]);
const RIDER_APP_CHECK_ROUTES = new Set([
  "updateRiderPushToken",
]);
const STATUS = {
  "invalid-argument": "INVALID_ARGUMENT",
  unauthenticated: "UNAUTHENTICATED",
  "permission-denied": "PERMISSION_DENIED",
  "failed-precondition": "FAILED_PRECONDITION",
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
  const registerProfileToken = options.registerProfileToken || deviceTokenAuthority.registerProfileToken;
  const serverTimestamp = options.serverTimestamp || (() => FieldValue.serverTimestamp());
  return {
    async updateSenderPushToken(data, context) {
      const token = clean(data && data.fcmToken);
      if (!token) throw callableError("invalid-argument", "Push token is required.");
      await registerProfileToken({uid: context.auth.uid, role: "sender", token, db});
      await db.collection("senderProfileEvents").doc().set({
        uid: context.auth.uid,
        action: "sender_push_token_updated",
        source: "updateSenderPushToken",
        createdAt: serverTimestamp(),
      });
      return {ok: true};
    },
    async updateRiderPushToken(data, context) {
      const token = clean(data && data.fcmToken);
      if (!token) throw callableError("invalid-argument", "Push token is required.");
      await registerProfileToken({uid: context.auth.uid, role: "rider", token, db});
      await db.collection("riderOnboardingEvents").doc().set({
        type: "rider_push_token_updated",
        riderId: context.auth.uid,
        actorType: "rider",
        actorId: context.auth.uid,
        actorEmail: context.auth.token.email || null,
        source: "cloud-run-token-callables",
        createdAt: serverTimestamp(),
      });
      return {ok: true};
    },
    async sendRiderUpdate() {
      throw callableError(
          "failed-precondition",
          "Legacy direct-token Rider notifications are disabled. Use an authorised server-owned notification path.",
      );
    },
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

function bearer(request) {
  const match = /^Bearer ([^\s]+)$/.exec(String(request.headers.authorization || ""));
  return match && match[1];
}

function routeName(url) {
  const pathname = new URL(url || "/", "http://localhost").pathname;
  const match = /^(?:\/v1\/callable)?\/(updateSenderPushToken|updateRiderPushToken|sendRiderUpdate)$/.exec(pathname);
  return match && ROUTES.has(match[1]) ? match[1] : null;
}

function createServer(options = {}) {
  const dependenciesFactory = options.dependenciesFactory || productionDependencies;
  let dependencies;
  return http.createServer((request, response) => {
    if (request.method === "GET" && ["/health", "/healthz"].includes(request.url)) {
      return writeJson(response, 200, {status: "ok", runtime: "node22", source: process.env.CIRCUM_SOURCE_SHA || "unknown"});
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
        const idToken = bearer(request);
        if (!idToken) throw callableError("unauthenticated", "Sign in to continue.");
        if (!dependencies) dependencies = dependenciesFactory();
        const decoded = await dependencies.verifyIdToken(idToken);
        if (!decoded || !(decoded.uid || decoded.sub)) throw callableError("unauthenticated", "Invalid authentication token.");
        let decodedAppCheck = null;
        if (RIDER_APP_CHECK_ROUTES.has(name)) {
          const appCheckToken = clean(request.headers["x-firebase-appcheck"]);
          if (!appCheckToken) throw callableError("failed-precondition", "Circum Rider security verification is required.");
          decodedAppCheck = await dependencies.verifyAppCheck(appCheckToken);
        }
        const payload = JSON.parse(Buffer.concat(chunks).toString("utf8") || "{}");
        if (!Object.prototype.hasOwnProperty.call(payload, "data")) throw callableError("invalid-argument", "Callable request must contain data.");
        const context = {
          auth: {uid: decoded.uid || decoded.sub, token: decoded},
          ...(decodedAppCheck ? {app: decodedAppCheck} : {}),
        };
        const result = await dependencies.handlers[name](payload.data, context);
        return writeJson(response, 200, {result});
      } catch (error) {
        const rawCode = String(error.code || "internal").replace(/^functions\//, "");
        const code = rawCode.startsWith("app-check/") || rawCode.startsWith("auth/") ? "unauthenticated" : rawCode;
        const status = code === "unauthenticated" ? 401 : code === "permission-denied" ? 403 : ["invalid-argument", "failed-precondition"].includes(code) ? 400 : 500;
        if (status === 500) console.error("token_callable_failed", {callable: name, reason: error.message || "internal_error"});
        return writeJson(response, status, {error: {status: STATUS[code] || "INTERNAL", message: status === 500 ? "Token request failed." : error.message}});
      }
    });
  });
}

if (require.main === module) createServer().listen(Number(process.env.PORT || 8080), "0.0.0.0");

module.exports = {createServer, createHandlers, productionDependencies, routeName, MAX_BODY_BYTES};
