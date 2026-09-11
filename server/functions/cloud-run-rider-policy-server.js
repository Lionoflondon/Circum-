/* eslint-disable max-len */
"use strict";

const http = require("node:http");
const {initializeApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const {createProcessor} = require("./rider-policy-worker-core");

const MAX_BODY_BYTES = 16 * 1024;

function productionProcessor() {
  initializeApp();
  const db = getFirestore();
  db.settings({ignoreUndefinedProperties: true});
  const apply = require("./rider-presence")._test.applyRiderOperationalState;
  return createProcessor({db, applyRiderOperationalState: apply});
}

function json(response, status, body) {
  response.writeHead(status, {"content-type": "application/json; charset=utf-8", "cache-control": "no-store"});
  response.end(JSON.stringify(body));
}

function createServer(options = {}) {
  const processorFactory = options.processorFactory || productionProcessor;
  let processor;
  return http.createServer((request, response) => {
    if (request.method === "GET" && request.url === "/health") return json(response, 200, {status: "ok", runtime: "node22", version: process.env.CIRCUM_SOURCE_SHA || "unknown"});
    if (request.url !== "/v1/recompute") return json(response, 404, {error: "not_found"});
    if (request.method !== "POST") return json(response, 405, {error: "method_not_allowed"});
    if (!String(request.headers["content-type"] || "").toLowerCase().startsWith("application/json")) return json(response, 415, {error: "unsupported_media_type"});
    let size = 0;
    const chunks = [];
    request.on("data", (chunk) => {
      size += chunk.length;
      if (size <= MAX_BODY_BYTES) chunks.push(chunk);
    });
    request.on("end", async () => {
      if (size > MAX_BODY_BYTES) return json(response, 413, {error: "request_too_large"});
      try {
        const body = JSON.parse(Buffer.concat(chunks).toString("utf8") || "{}");
        if (!processor) processor = processorFactory();
        json(response, 200, await processor(body));
      } catch (error) {
        const status = Number(error.statusCode) || (error instanceof SyntaxError ? 400 : 500);
        if (status === 500) console.error("rider_policy_worker_failed", {reason: error.message || "internal_error"});
        json(response, status, {error: status === 500 ? "worker_failed" : error.message});
      }
    });
  });
}

if (require.main === module) createServer().listen(Number(process.env.PORT || 8080), "0.0.0.0");

module.exports = {createServer, productionProcessor, MAX_BODY_BYTES};
