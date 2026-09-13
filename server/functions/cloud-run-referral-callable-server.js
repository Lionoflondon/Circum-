/* eslint-disable max-len */
"use strict";

const http = require("node:http");
const {initializeApp, getApps} = require("firebase-admin/app");
const {getAuth} = require("firebase-admin/auth");

const MAX_BODY_BYTES = 32 * 1024;
const CALLABLES = new Set(["ensureReferralCode", "attachReferralCode", "activateReferral"]);
const STATUS = {
  "invalid-argument": "INVALID_ARGUMENT",
  unauthenticated: "UNAUTHENTICATED",
  "permission-denied": "PERMISSION_DENIED",
  "already-exists": "ALREADY_EXISTS",
  internal: "INTERNAL",
};

function productionDependencies() {
  if (!getApps().length) initializeApp();
  return {
    verifyIdToken: (token) => getAuth().verifyIdToken(token, true),
    handlers: require("./referrals").cloudRunHandlers,
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

function createServer(options = {}) {
  const dependenciesFactory = options.dependenciesFactory || productionDependencies;
  let dependencies;
  return http.createServer((request, response) => {
    if (request.method === "GET" && request.url === "/health") return writeJson(response, 200, {status: "ok", runtime: "node22", source: process.env.CIRCUM_SOURCE_SHA || "unknown"});
    if (request.method === "OPTIONS") return writeJson(response, 204, {});
    const match = /^\/v1\/callable\/(ensureReferralCode|attachReferralCode|activateReferral)$/.exec(request.url || "");
    if (!match || !CALLABLES.has(match[1])) return writeJson(response, 404, {error: {status: "NOT_FOUND", message: "Not found."}});
    if (request.method !== "POST") return writeJson(response, 405, {error: {status: "INVALID_ARGUMENT", message: "POST required."}});
    if (!String(request.headers["content-type"] || "").toLowerCase().startsWith("application/json")) return writeJson(response, 415, {error: {status: "INVALID_ARGUMENT", message: "JSON required."}});
    let size = 0;
    const chunks = [];
    request.on("data", (chunk) => {
      size += chunk.length;
      if (size <= MAX_BODY_BYTES) chunks.push(chunk);
    });
    request.on("end", async () => {
      if (size > MAX_BODY_BYTES) return writeJson(response, 413, {error: {status: "INVALID_ARGUMENT", message: "Request too large."}});
      try {
        const token = bearer(request);
        if (!token) return writeJson(response, 401, {error: {status: "UNAUTHENTICATED", message: "Sign in to use referrals."}});
        if (!dependencies) dependencies = dependenciesFactory();
        const decoded = await dependencies.verifyIdToken(token);
        const payload = JSON.parse(Buffer.concat(chunks).toString("utf8") || "{}");
        if (!Object.prototype.hasOwnProperty.call(payload, "data")) throw Object.assign(new Error("Callable request must contain data."), {code: "invalid-argument"});
        const result = await dependencies.handlers[match[1]](payload.data, {auth: {uid: decoded.uid || decoded.sub, token: decoded}});
        return writeJson(response, 200, {result});
      } catch (error) {
        const code = error.code && String(error.code).replace(/^functions\//, "") || "internal";
        const status = code === "unauthenticated" ? 401 : code === "permission-denied" ? 403 : code === "invalid-argument" ? 400 : 500;
        if (status === 500) console.error("referral_callable_failed", {callable: match[1], reason: error.message || "internal_error"});
        return writeJson(response, status, {error: {status: STATUS[code] || "INTERNAL", message: status === 500 ? "Referral request failed." : error.message}});
      }
    });
  });
}

if (require.main === module) createServer().listen(Number(process.env.PORT || 8080), "0.0.0.0");

module.exports = {createServer, productionDependencies, MAX_BODY_BYTES};
