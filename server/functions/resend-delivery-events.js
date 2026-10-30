/* eslint-disable max-len, require-jsdoc */
"use strict";
const crypto = require("node:crypto");
const http = require("node:http");
const {Webhook} = require("svix");
const {getApps, initializeApp} = require("firebase-admin/app");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const EVENTS = new Set(["email.sent", "email.delivered", "email.delivery_delayed", "email.bounced", "email.complained", "email.failed", "email.suppressed"]);
const FAILURE = new Set(["email.bounced", "email.complained", "email.failed", "email.suppressed"]);
const eventId = (value) => crypto.createHash("sha256").update(value).digest("hex");
function writeLog(log, value) {
  const line = JSON.stringify(value);
  if (typeof log === "function") log(line);
  else console.log(line);
}
function millis(value) {
  return value && typeof value.toMillis === "function" ? value.toMillis() : Date.parse(value || "") || 0;
}
const delay = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
async function findQueueReceipt({db, providerId, wait = delay}) {
  for (let attempt = 0; attempt < 9; attempt++) {
    const queue = await db.collection("emailQueue").where("providerId", "==", providerId).limit(2).get();
    if (queue.docs.length) return queue.docs;
    if (attempt < 8) await wait(250);
  }
  return [];
}
async function applyLatestProviderOutcome({db, providerId, queueDocs}) {
  const events = await db.collection("emailProviderEvents")
      .where("providerId", "==", providerId).get();
  if (!events.docs.length || !queueDocs.length) return {status: "pending_receipt"};
  const latest = events.docs.reduce((winner, row) => {
    return millis(row.data().providerEventAt) > millis(winner.data().providerEventAt) ? row : winner;
  });
  const latestEvent = latest.data();
  await db.runTransaction(async (tx) => {
    const snapshots = [];
    for (const row of queueDocs) snapshots.push(await tx.get(row.ref));
    for (const snap of snapshots) {
      if (!snap.exists) continue;
      const current = snap.data() || {};
      const previous = current.providerEventAt && typeof current.providerEventAt.toMillis === "function" ? current.providerEventAt.toMillis() : Date.parse(current.providerEventAt || "") || 0;
      const next = millis(latestEvent.providerEventAt);
      if (next >= previous) tx.set(snap.ref, {providerDeliveryStatus: latestEvent.eventType.slice(6), providerEventAt: latestEvent.providerEventAt, providerOutcomeUpdatedAt: FieldValue.serverTimestamp()}, {merge: true});
    }
  });
  const pending = events.docs.filter((row) => row.data().matchedQueueCount === 0);
  if (pending.length) {
    await db.runTransaction(async (tx) => {
      for (const row of pending) {
        const snap = await tx.get(row.ref);
        if (snap.exists && snap.data().matchedQueueCount === 0) tx.set(row.ref, {matchedQueueCount: queueDocs.length, receiptMatchedAt: FieldValue.serverTimestamp()}, {merge: true});
      }
    });
  }
  return {status: "recorded", matchedQueueCount: queueDocs.length};
}
async function recordOutcome({db, event, deliveryId, log = console.log, wait = delay}) {
  if (!event || !EVENTS.has(event.type)) return {status: "ignored"};
  const providerId = String(event.data && event.data.email_id || "");
  const at = Date.parse(event.created_at);
  if (!/^[a-f0-9-]{36}$/i.test(providerId) || !Number.isFinite(at)) throw Object.assign(new Error("invalid_event"), {statusCode: 400});
  if (typeof deliveryId !== "string" || !deliveryId) throw Object.assign(new Error("invalid_event"), {statusCode: 400});
  const ref = db.collection("emailProviderEvents").doc(eventId(deliveryId));
  const queue = await db.collection("emailQueue").where("providerId", "==", providerId).limit(2).get();
  const result = await db.runTransaction(async (tx) => {
    const old = await tx.get(ref);
    if (old.exists) return {status: "duplicate"};
    tx.create(ref, {provider: "resend", providerId, eventType: event.type, providerEventAt: new Date(at), receivedAt: FieldValue.serverTimestamp(), matchedQueueCount: queue.docs.length});
    return {status: "recorded", matchedQueueCount: queue.docs.length};
  });
  if (result.status === "recorded" && FAILURE.has(event.type)) writeLog(log, {severity: "ERROR", event: "transactional_email_delivery_failure", provider: "resend", providerId, eventType: event.type, matchedQueueCount: queue.docs.length});
  if (result.status === "duplicate") {
    if (queue.docs.length) await applyLatestProviderOutcome({db, providerId, queueDocs: queue.docs});
  }
  if (!queue.docs.length) {
    writeLog(log, {severity: "WARNING", event: "email_provider_event_waiting_for_queue_receipt", provider: "resend", providerId, eventType: event.type});
    // Keep the single webhook service as the only delivery-event owner. Wait
    // briefly for the sender's Firestore receipt; if it remains absent, leave
    // the minimal event record durable and return retryable 503 so Resend retries.
    const appeared = await findQueueReceipt({db, providerId, wait});
    if (!appeared.length) throw Object.assign(new Error("queue_receipt_not_ready"), {statusCode: 503, code: "queue_receipt_not_ready"});
    return applyLatestProviderOutcome({db, providerId, queueDocs: appeared});
  }
  return result.status === "duplicate" ? result : applyLatestProviderOutcome({db, providerId, queueDocs: queue.docs});
}
function createServer({dbFactory = () => {
if (!getApps().length) initializeApp(); return getFirestore();
}, secret = process.env.RESEND_WEBHOOK_SECRET, log, wait} = {}) {
  let db;
  return http.createServer((req, res) => {
    const reply = (status, value) => {
res.writeHead(status, {"content-type": "application/json"}); res.end(JSON.stringify(value));
};
    if (req.method === "GET" && req.url === "/health") return reply(200, {status: "ok", configured: Boolean(secret), source: process.env.CIRCUM_SOURCE_SHA || "unknown"});
    if (req.url !== "/resend/events" || req.method !== "POST") return reply(404, {error: "not_found"});
    if (!secret) return reply(503, {error: "not_configured"});
    let size = 0; const chunks = [];
    req.on("data", (chunk) => {
size += chunk.length; if (size <= 262144) chunks.push(chunk);
});
    req.on("end", async () => {
      if (size > 262144) return reply(413, {error: "too_large"});
      let event;
      try {
const body = Buffer.concat(chunks).toString("utf8"); new Webhook(secret).verify(body, req.headers); event = JSON.parse(body);
} catch (_) {
return reply(401, {error: "invalid_signature"});
}
      try {
        if (!db) db = dbFactory();
        return reply(200, await recordOutcome({db, event, deliveryId: req.headers["svix-id"], log, wait}));
      } catch (error) {
writeLog(log, {severity: "ERROR", event: "email_outcome_record_failed", operation: "record_or_reconcile", code: String(error.code || error.statusCode || "unknown")}); return reply(error.statusCode || 503, {error: error.statusCode === 400 ? "invalid_event" : "retry_required"});
}
    });
  });
}
if (require.main === module) createServer().listen(Number(process.env.PORT || 8080), "0.0.0.0");
module.exports = {createServer, recordOutcome, applyLatestProviderOutcome, findQueueReceipt};
