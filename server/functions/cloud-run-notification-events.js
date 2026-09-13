/* eslint-disable max-len */
"use strict";

const http = require("node:http");
const {initializeApp} = require("firebase-admin/app");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {decodeEventData} = require("./rider-policy-firestore-event");

const MAX_BODY_BYTES = 2 * 1024 * 1024;
const handlers = {
  delivery_created: {
    eventType: "google.cloud.firestore.document.v1.created",
    run: async ({db, deliveryId, after}) => {
      const {handleDeliveryCreated} = require("./platform-notifications");
      return handleDeliveryCreated({id: deliveryId, data: () => after, ref: db.collection("deliveryRequests").doc(deliveryId)});
    },
  },
  gift_delivery_completed: {
    eventType: "google.cloud.firestore.document.v1.updated",
    run: async ({db, deliveryId, before, after}) => {
      const {handleGiftDeliveryCompleted} = require("./gift-story-automation");
      const ref = db.collection("deliveryRequests").doc(deliveryId);
      return handleGiftDeliveryCompleted({before: {id: deliveryId, data: () => before, ref}, after: {id: deliveryId, data: () => after, ref}}, {params: {deliveryId}});
    },
  },
};

function json(res, status, body) {
  res.writeHead(status, {"content-type": "application/json; charset=utf-8", "cache-control": "no-store"});
  res.end(JSON.stringify(body));
}

function deliveryIdFromName(name) {
  const path = String(name || "").split("/documents/")[1] || String(name || "").replace(/^documents\//, "");
  const match = /^deliveryRequests\/([^/]+)$/.exec(path);
  return match && match[1];
}

function claimId(kind, deliveryId) {
  return Buffer.from(`${kind}:${deliveryId}`).toString("base64url");
}

async function processOnce({db, kind, eventId, deliveryId, before, after, run}) {
  const ref = db.collection("eventHandlerClaims").doc(claimId(kind, deliveryId));
  const state = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const current = snap.exists ? snap.data() || {} : {};
    if (current.status === "completed") return "duplicate";
    if (current.status === "processing" && current.eventId !== eventId) return "busy";
    tx.set(ref, {handler: kind, deliveryId, eventId, status: "processing", startedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()}, {merge: true});
    return "claimed";
  });
  if (state === "duplicate") return {status: "duplicate"};
  if (state === "busy") throw Object.assign(new Error("event_already_processing"), {statusCode: 503});
  try {
    await run({db, deliveryId, before, after});
    await ref.set({status: "completed", completedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()}, {merge: true});
    return {status: "completed"};
  } catch (error) {
    await ref.set({status: "failed", failureReason: String(error && error.message || error).slice(0, 500), updatedAt: FieldValue.serverTimestamp()}, {merge: true}).catch(() => {});
    throw error;
  }
}

function createServer(options = {}) {
  const kind = options.kind || process.env.HANDLER_KIND;
  const definition = handlers[kind];
  const dbFactory = options.dbFactory || (() => {
    initializeApp();
    const db = getFirestore();
    db.settings({ignoreUndefinedProperties: true});
    return db;
  });
  let db;
  return http.createServer((req, res) => {
    if (req.method === "GET" && req.url === "/health") return json(res, definition ? 200 : 500, {status: definition ? "ok" : "misconfigured", handler: kind || "unset", sourceSha: process.env.CIRCUM_SOURCE_SHA || "unknown"});
    if (!definition || req.url !== "/" || req.method !== "POST") return json(res, 404, {error: "not_found"});
    if (String(req.headers["ce-type"] || "") !== definition.eventType) return json(res, 400, {error: "invalid_event_type"});
    const eventId = String(req.headers["ce-id"] || "").trim();
    if (!eventId || eventId.length > 256) return json(res, 400, {error: "invalid_event_id"});
    let size = 0; const chunks = [];
    req.on("data", (chunk) => {
 size += chunk.length; if (size <= MAX_BODY_BYTES) chunks.push(chunk);
});
    req.on("end", async () => {
      if (size > MAX_BODY_BYTES) return json(res, 413, {error: "request_too_large"});
      try {
        const decoded = decodeEventData(Buffer.concat(chunks));
        const deliveryId = deliveryIdFromName(decoded.documentName || req.headers["ce-subject"]);
        if (!deliveryId) return json(res, 400, {error: "invalid_document"});
        if (!db) db = dbFactory();
        const result = await processOnce({db, kind, eventId, deliveryId, before: decoded.before, after: decoded.after, run: definition.run});
        return json(res, 200, {ok: true, ...result});
      } catch (error) {
        console.error("notification_event_failed", {handler: kind, eventId, reason: error && error.message || "unknown"});
        return json(res, Number(error.statusCode) || 500, {error: Number(error.statusCode) === 503 ? "busy" : "handler_failed"});
      }
    });
  });
}

if (require.main === module) createServer().listen(Number(process.env.PORT || 8080), "0.0.0.0");

module.exports = {createServer, deliveryIdFromName, processOnce, claimId, handlers};
