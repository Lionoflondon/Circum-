/* eslint-disable max-len */
"use strict";

const http = require("node:http");
const {initializeApp, getApps} = require("firebase-admin/app");
const {decodeEventData, EVENT_TYPE} = require("./rider-policy-firestore-event");

const MAX_EVENT_BODY_BYTES = 2 * 1024 * 1024;
function productionHandlers() {
  if (!getApps().length) initializeApp();
  return require("./referrals").cloudRunHandlers;
}

function writeJson(response, status, body) {
  response.writeHead(status, {"content-type": "application/json; charset=utf-8", "cache-control": "no-store"});
  response.end(JSON.stringify(body));
}

function documentIdentity(headers, decoded) {
  const raw = String(headers["ce-document"] || headers["ce-subject"] || decoded.documentName || "");
  const path = (raw.split("/documents/")[1] || raw.replace(/^documents\//, "")).replace(/^\//, "");
  const match = /^(deliveryRequests|giftRequests|prescriptionPickups)\/([A-Za-z0-9_-]{1,256})$/.exec(path);
  return match && {collection: match[1], id: match[2]};
}

function createServer(options = {}) {
  const handlersFactory = options.handlersFactory || productionHandlers;
  let handlers;
  return http.createServer((request, response) => {
    if (request.method === "GET" && request.url === "/health") return writeJson(response, 200, {status: "ok", runtime: "node22", source: process.env.CIRCUM_SOURCE_SHA || "unknown"});
    if (request.url !== "/v1/events/firestore/referral-completion") return writeJson(response, 404, {error: "not_found"});
    if (request.method !== "POST") return writeJson(response, 405, {error: "method_not_allowed"});
    if (String(request.headers["ce-type"] || "") !== EVENT_TYPE) return writeJson(response, 400, {error: "invalid_event_type"});
    const eventId = String(request.headers["ce-id"] || "").trim();
    if (!eventId || eventId.length > 128) return writeJson(response, 400, {error: "invalid_event_id"});
    let size = 0;
    const chunks = [];
    request.on("data", (chunk) => {
      size += chunk.length;
      if (size <= MAX_EVENT_BODY_BYTES) chunks.push(chunk);
    });
    request.on("end", async () => {
      if (size > MAX_EVENT_BODY_BYTES) return writeJson(response, 413, {error: "request_too_large"});
      try {
        const decoded = decodeEventData(Buffer.concat(chunks));
        const identity = documentIdentity(request.headers, decoded);
        if (!identity) return writeJson(response, 400, {error: "invalid_event_document"});
        if (!handlers) handlers = handlersFactory();
        if (!handlers.becameCompleted(decoded.before, decoded.after)) return writeJson(response, 200, {outcome: "IGNORED", eventId});
        let result;
        if (identity.collection === "deliveryRequests") result = await handlers.handleDeliveryCompletedReferral({delivery: decoded.after, deliveryId: identity.id});
        if (identity.collection === "giftRequests") result = await handlers.handleGiftCompletedReferral({giftId: identity.id, senderId: decoded.after.senderId, senderEmail: decoded.after.senderEmail});
        if (identity.collection === "prescriptionPickups") result = await handlers.handleHealthPlusCompletedReferral({pickupId: identity.id, userId: decoded.after.senderId || decoded.after.userId || decoded.after.profileId, email: decoded.after.email});
        console.info(JSON.stringify({event: "referral_completion_processed", eventId, collection: identity.collection, documentId: identity.id, outcome: result && result.status || "processed"}));
        return writeJson(response, 200, {outcome: "PROCESSED", eventId});
      } catch (error) {
        console.error("referral_event_failed", {eventId, reason: error.message || "internal_error"});
        return writeJson(response, 500, {error: "event_processing_failed"});
      }
    });
  });
}

if (require.main === module) createServer().listen(Number(process.env.PORT || 8080), "0.0.0.0");

module.exports = {createServer, documentIdentity, productionHandlers, MAX_EVENT_BODY_BYTES};
