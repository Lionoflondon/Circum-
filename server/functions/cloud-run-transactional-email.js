/* eslint-disable max-len, require-jsdoc */
"use strict";

const http = require("node:http");
const {initializeApp} = require("firebase-admin/app");
const {getFirestore, FieldValue, Timestamp} = require("firebase-admin/firestore");
const {parseFirestoreEventarcPayload} = require("./lib/eventarc-envelope");
const {deliverGiftEmail} = require("./gift-email-notifications");

const EVENT_TYPE = "google.cloud.firestore.document.v1.created";
const MAX_BODY_BYTES = 2 * 1024 * 1024;
const CLAIM_LEASE_MS = 5 * 60 * 1000;
const COLLECTION = "giftEmailNotifications";

function json(response, status, body) {
  response.writeHead(status, {"content-type": "application/json; charset=utf-8", "cache-control": "no-store"});
  response.end(JSON.stringify(body));
}

function notificationIdFromName(name) {
  const path = String(name || "").split("/documents/")[1] || String(name || "").replace(/^documents\//, "");
  const match = new RegExp(`^${COLLECTION}/([A-Za-z0-9_-]{1,200})$`).exec(path);
  return match && match[1];
}

function claimId(notificationId) {
  return Buffer.from(`gift_email:${notificationId}`).toString("base64url");
}

async function processEmailOnce({db, eventId, notificationId, after, deliver = deliverGiftEmail}) {
  const ref = db.collection("eventHandlerClaims").doc(claimId(notificationId));
  const lease = await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    const current = snapshot.exists ? snapshot.data() || {} : {};
    if (current.status === "completed") return "duplicate";
    const leaseUntil = current.leaseExpiresAt && typeof current.leaseExpiresAt.toMillis === "function" ? current.leaseExpiresAt.toMillis() : 0;
    if (current.status === "processing" && current.eventId !== eventId && leaseUntil > Date.now()) return "busy";
    const now = Date.now();
    const leaseOwner = `${eventId}:${now}`;
    transaction.set(ref, {
      operation: "gift_email_delivery",
      handler: "circum-transactional-email",
      notificationId,
      eventId,
      status: "processing",
      leaseOwner,
      leaseAcquiredAt: Timestamp.fromMillis(now),
      leaseExpiresAt: Timestamp.fromMillis(now + CLAIM_LEASE_MS),
      attemptCount: Number(current.attemptCount || 0) + 1,
      createdAt: current.createdAt || FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    return {leaseOwner};
  });
  if (lease === "duplicate") return {status: "duplicate"};
  if (lease === "busy") throw Object.assign(new Error("event_already_processing"), {statusCode: 503});

  const snapshot = {
    id: notificationId,
    data: () => ({...after, notificationId}),
    ref: db.collection(COLLECTION).doc(notificationId),
  };
  try {
    const result = await deliver(snapshot, {db});
    await db.runTransaction(async (transaction) => {
      const currentSnapshot = await transaction.get(ref);
      const current = currentSnapshot.exists ? currentSnapshot.data() || {} : {};
      const expiresAt = current.leaseExpiresAt && typeof current.leaseExpiresAt.toMillis === "function" ? current.leaseExpiresAt.toMillis() : 0;
      if (current.status !== "processing" || current.leaseOwner !== lease.leaseOwner || expiresAt <= Date.now()) throw Object.assign(new Error("lease_lost"), {statusCode: 503});
      transaction.update(ref, {status: "completed", completedAt: FieldValue.serverTimestamp(), leaseOwner: null, leaseExpiresAt: Timestamp.fromMillis(Date.now()), updatedAt: FieldValue.serverTimestamp()});
    });
    return result && result.status ? result : {status: "completed"};
  } catch (error) {
    await db.runTransaction(async (transaction) => {
      const currentSnapshot = await transaction.get(ref);
      const current = currentSnapshot.exists ? currentSnapshot.data() || {} : {};
      if (current.leaseOwner !== lease.leaseOwner) {
        return;
      }
      transaction.update(ref, {status: "retryable_failed", lastError: String(error && error.message || error).slice(0, 500), leaseOwner: null, leaseExpiresAt: Timestamp.fromMillis(Date.now()), updatedAt: FieldValue.serverTimestamp()});
    }).catch(() => {});
    throw error;
  }
}

function productionDb() {
  initializeApp();
  const db = getFirestore();
  db.settings({ignoreUndefinedProperties: true});
  return db;
}

function createServer(options = {}) {
  const dbFactory = options.dbFactory || productionDb;
  const processor = options.processEmailOnce || processEmailOnce;
  let db;
  return http.createServer((request, response) => {
    if (request.method === "GET" && request.url === "/health") {
      return json(response, 200, {
        status: "ok",
        runtime: "node22",
        service: "circum-transactional-email",
        sourceSha: process.env.CIRCUM_SOURCE_SHA || "unknown",
      });
    }
    if (request.method !== "POST" || request.url !== "/") {
      return json(response, 404, {error: "not_found"});
    }
    if (String(request.headers["ce-type"] || "") !== EVENT_TYPE) {
      return json(response, 400, {error: "invalid_event_type"});
    }
    const eventId = String(request.headers["ce-id"] || "").trim();
    if (!eventId || eventId.length > 256) return json(response, 400, {error: "invalid_event_id"});
    let size = 0;
    const chunks = [];
    request.on("data", (chunk) => {
      size += chunk.length;
      if (size <= MAX_BODY_BYTES) chunks.push(chunk);
    });
    request.on("end", async () => {
      if (size > MAX_BODY_BYTES) return json(response, 413, {error: "request_too_large"});
      try {
        const decoded = parseFirestoreEventarcPayload(Buffer.concat(chunks));
        const notificationId = notificationIdFromName(decoded.documentName || request.headers["ce-subject"]);
        if (!notificationId) return json(response, 400, {error: "invalid_document"});
        if (!db) db = dbFactory();
        const result = await processor({db, eventId, notificationId, after: decoded.after});
        return json(response, 200, {ok: true, ...result});
      } catch (error) {
        const status = Number(error.statusCode) || 500;
        if (status >= 500) console.error("transactional_email_event_failed", {eventId, reason: error.message || "unknown"});
        return json(response, status, {error: status === 503 ? "busy" : "handler_failed"});
      }
    });
  });
}

if (require.main === module) createServer().listen(Number(process.env.PORT || 8080), "0.0.0.0");

module.exports = {createServer, processEmailOnce, notificationIdFromName, claimId, EVENT_TYPE, MAX_BODY_BYTES};
