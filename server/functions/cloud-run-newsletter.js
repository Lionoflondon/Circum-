/* eslint-disable max-len, require-jsdoc */
"use strict";

const http = require("node:http");
const {initializeApp, getApps} = require("firebase-admin/app");
const {getAppCheck} = require("firebase-admin/app-check");
const {getAuth} = require("firebase-admin/auth");

const MAX_BODY_BYTES = 32 * 1024;
const PUBLIC = new Set([
  "submitNewsletterSignup", "getNewsletterPreferences", "updateNewsletterPreferences",
  "unsubscribeNewsletter", "recordNewsletterAnalytics",
]);
const ADMIN = new Set([
  "adminNewsletterDashboard", "adminSearchNewsletterSubscribers", "adminExportNewsletterSubscribers",
]);
const ALL = new Set([...PUBLIC, ...ADMIN]);
const STATUS = {
  "invalid-argument": "INVALID_ARGUMENT", unauthenticated: "UNAUTHENTICATED",
  "permission-denied": "PERMISSION_DENIED", "failed-precondition": "FAILED_PRECONDITION",
  "resource-exhausted": "RESOURCE_EXHAUSTED", internal: "INTERNAL",
};

function productionDependencies() {
  if (!getApps().length) initializeApp();
  return {
    verifyAppCheck: (token) => getAppCheck().verifyToken(token),
    verifyIdToken: (token) => getAuth().verifyIdToken(token, true),
    handlers: require("./newsletter"),
  };
}

function writeJson(response, status, body) {
  response.writeHead(status, {
    "content-type": "application/json; charset=utf-8", "cache-control": "no-store",
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

function requestIp(request) {
  return String(request.headers["x-forwarded-for"] || request.socket.remoteAddress || "")
      .split(",")[0].trim();
}

function routeName(url) {
  const pathname = new URL(url || "/", "http://localhost").pathname;
  const match = /^(?:\/newsletter-api)?\/v1\/callable\/([A-Za-z0-9]+)$/.exec(pathname);
  return match && ALL.has(match[1]) ? match[1] : null;
}

function createServer(options = {}) {
  const dependenciesFactory = options.dependenciesFactory || productionDependencies;
  let dependencies;
  return http.createServer((request, response) => {
    if (request.method === "GET" && ["/health", "/healthz"].includes(request.url)) {
      return writeJson(response, 200, {status: "ok", runtime: "node22", source: process.env.CIRCUM_SOURCE_SHA || "unknown", signupEnabled: process.env.NEWSLETTER_SIGNUP_ENABLED === "true"});
    }
    if (request.method === "OPTIONS") return writeJson(response, 204, {});
    const name = routeName(request.url);
    if (!name) return writeJson(response, 404, {error: {status: "NOT_FOUND", message: "Not found."}});
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
        if (!dependencies) dependencies = dependenciesFactory();
        const appCheckToken = String(request.headers["x-firebase-appcheck"] || "");
        if (!appCheckToken) throw Object.assign(new Error("Circum security verification is required."), {code: "failed-precondition"});
        const app = await dependencies.verifyAppCheck(appCheckToken);
        const context = {app: {appId: app.appId || app.sub}, rawRequest: {ip: requestIp(request)}};
        if (ADMIN.has(name)) {
          const idToken = bearer(request);
          if (!idToken) throw Object.assign(new Error("Sign in first."), {code: "unauthenticated"});
          const decoded = await dependencies.verifyIdToken(idToken);
          context.auth = {uid: decoded.uid || decoded.sub, token: decoded};
        }
        const payload = JSON.parse(Buffer.concat(chunks).toString("utf8") || "{}");
        if (!Object.prototype.hasOwnProperty.call(payload, "data")) throw Object.assign(new Error("Callable request must contain data."), {code: "invalid-argument"});
        const result = await dependencies.handlers[name].run(payload.data, context);
        return writeJson(response, 200, {result});
      } catch (error) {
        const code = String(error.code || "internal").replace(/^functions\//, "");
        const status = code === "unauthenticated" ? 401 : code === "permission-denied" ? 403 : code === "resource-exhausted" ? 429 : ["invalid-argument", "failed-precondition"].includes(code) ? 400 : 500;
        if (status === 500) console.error("newsletter_callable_failed", {callable: name, reason: error.message || "internal_error"});
        return writeJson(response, status, {error: {status: STATUS[code] || "INTERNAL", message: status === 500 ? "Newsletter request failed." : error.message}});
      }
    });
  });
}

if (require.main === module) createServer().listen(Number(process.env.PORT || 8080), "0.0.0.0");

module.exports = {createServer, productionDependencies, MAX_BODY_BYTES, PUBLIC, ADMIN, routeName};
