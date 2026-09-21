/* eslint-disable max-len, require-jsdoc */
"use strict";

const http = require("node:http");
const {initializeApp, getApps} = require("firebase-admin/app");
const {getAppCheck} = require("firebase-admin/app-check");
const {getAuth} = require("firebase-admin/auth");
const addressCore = require("./free-address-core");

const MAX_BODY_BYTES = 8 * 1024;
const WINDOW_MS = 60 * 1000;
const MAX_REQUESTS_PER_WINDOW = 30;
const ROUTES = new Set(["searchFreeUkAddresses", "resolveUkAddressPlace"]);
const STATUS = {
  "invalid-argument": "INVALID_ARGUMENT",
  unauthenticated: "UNAUTHENTICATED",
  "permission-denied": "PERMISSION_DENIED",
  "failed-precondition": "FAILED_PRECONDITION",
  "resource-exhausted": "RESOURCE_EXHAUSTED",
  unavailable: "UNAVAILABLE",
  internal: "INTERNAL",
};

function callableError(code, message) {
  return Object.assign(new Error(message), {code});
}

function clean(value, max = 256) {
  return String(value || "").trim().slice(0, max);
}

function createHandlers(options = {}) {
  const apiKey = clean(options.googlePlacesApiKey === undefined ? process.env.BACKEND_GOOGLE_PLACES_API_KEY : options.googlePlacesApiKey, 512);
  const search = options.searchFreeUkAddresses || addressCore.searchFreeUkAddresses;
  const resolve = options.resolveUkAddressPlace || addressCore.resolveUkAddressPlace;
  return {
    async searchFreeUkAddresses(data) {
      const query = clean(data && data.query, 160);
      const sessionToken = clean(data && data.sessionToken, 128);
      if (query.length < 3) return {status: "ZERO_RESULTS", results: []};
      if (!apiKey) throw callableError("failed-precondition", "Address provider is not configured.");
      try {
        const result = await search({query, sessionToken, googlePlacesApiKey: apiKey});
        if (result.status === "OK" || result.status === "ZERO_RESULTS") return result;
        throw new Error(`provider_${clean(result.status, 48)}`);
      } catch (error) {
        throw callableError("unavailable", "Address search is unavailable. Enter the address manually or try again.");
      }
    },
    async resolveUkAddressPlace(data) {
      const placeId = clean(data && data.placeId, 256);
      const sessionToken = clean(data && data.sessionToken, 128);
      if (!placeId) throw callableError("invalid-argument", "A selected address is required.");
      if (!apiKey) throw callableError("failed-precondition", "Address provider is not configured.");
      try {
        const result = await resolve({placeId, sessionToken, googlePlacesApiKey: apiKey});
        const country = clean(result && result.components && result.components.country, 64).toLowerCase();
        if (!new Set(["united kingdom", "uk", "great britain"]).has(country)) {
          throw callableError("permission-denied", "Only United Kingdom addresses are supported.");
        }
        return result;
      } catch (error) {
        if (error.code === "permission-denied") throw error;
        throw callableError("unavailable", "Address details are unavailable. Enter the address manually or try again.");
      }
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
  const match = /^(?:\/v1\/callable)?\/(searchFreeUkAddresses|resolveUkAddressPlace)$/.exec(pathname);
  return match && ROUTES.has(match[1]) ? match[1] : null;
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

function createServer(options = {}) {
  const dependenciesFactory = options.dependenciesFactory || productionDependencies;
  const allowRequest = options.allowRequest || createRateLimiter();
  let dependencies;
  return http.createServer((request, response) => {
    if (request.method === "GET" && ["/health", "/healthz"].includes(request.url)) {
      return writeJson(response, 200, {status: "ok", runtime: "node22", source: process.env.CIRCUM_SOURCE_SHA || "unknown", operations: [...ROUTES]});
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
        const appCheckToken = clean(request.headers["x-firebase-appcheck"], 4096);
        if (!idToken) throw callableError("unauthenticated", "Sign in to continue.");
        if (!appCheckToken) throw callableError("failed-precondition", "Circum security verification is required.");
        if (!dependencies) dependencies = dependenciesFactory();
        const [decoded] = await Promise.all([
          dependencies.verifyIdToken(idToken),
          dependencies.verifyAppCheck(appCheckToken),
        ]);
        const uid = decoded && (decoded.uid || decoded.sub);
        if (!uid) throw callableError("unauthenticated", "Invalid authentication token.");
        const payload = JSON.parse(Buffer.concat(chunks).toString("utf8") || "{}");
        if (!Object.prototype.hasOwnProperty.call(payload, "data") || !payload.data || typeof payload.data !== "object" || Array.isArray(payload.data)) {
          throw callableError("invalid-argument", "Callable request must contain data.");
        }
        if (!allowRequest(uid)) throw callableError("resource-exhausted", "Too many address requests. Try again shortly.");
        const result = await dependencies.handlers[name](payload.data, {auth: {uid, token: decoded}});
        return writeJson(response, 200, {result});
      } catch (error) {
        const rawCode = String(error.code || "internal").replace(/^functions\//, "");
        const code = rawCode.startsWith("app-check/") || rawCode.startsWith("auth/") ? "unauthenticated" : rawCode;
        const status = code === "unauthenticated" ? 401 : code === "permission-denied" ? 403 : code === "resource-exhausted" ? 429 : ["invalid-argument", "failed-precondition"].includes(code) ? 400 : code === "unavailable" ? 503 : 500;
        if (status >= 500) console.error("address_places_failed", {operation: name, reason: code});
        return writeJson(response, status, {error: {status: STATUS[code] || "INTERNAL", message: status === 500 ? "Address request failed." : error.message}});
      }
    });
  });
}

if (require.main === module) createServer().listen(Number(process.env.PORT || 8080), "0.0.0.0");

module.exports = {createHandlers, createRateLimiter, createServer, productionDependencies, routeName, MAX_BODY_BYTES};
