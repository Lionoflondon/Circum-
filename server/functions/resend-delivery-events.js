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
async function recordOutcome({db, event, deliveryId, log = console.log}) {
  if (!event || !EVENTS.has(event.type)) return {status: "ignored"};
  const providerId = String(event.data && event.data.email_id || "");
  const at = Date.parse(event.created_at);
  if (!/^[a-f0-9-]{36}$/i.test(providerId) || !Number.isFinite(at)) throw Object.assign(new Error("invalid_event"), {statusCode: 400});
  const ref = db.collection("emailProviderEvents").doc(eventId(deliveryId));
  const queue = await db.collection("emailQueue").where("providerId", "==", providerId).limit(2).get();
  if (!queue.docs.length) throw Object.assign(new Error("queue_receipt_not_ready"), {statusCode: 503});
  const result = await db.runTransaction(async (tx) => {
    const old = await tx.get(ref);
    if (old.exists) return {status: "duplicate"};
    const snapshots = [];
    for (const row of queue.docs) snapshots.push(await tx.get(row.ref));
    tx.create(ref, {provider: "resend", providerId, eventType: event.type, providerEventAt: new Date(at), receivedAt: FieldValue.serverTimestamp(), matchedQueueCount: snapshots.length});
    for (const snap of snapshots) {
      const current = snap.data() || {};
      const previous = current.providerEventAt && typeof current.providerEventAt.toMillis === "function" ? current.providerEventAt.toMillis() : Date.parse(current.providerEventAt || "") || 0;
      if (at >= previous) tx.set(snap.ref, {providerDeliveryStatus: event.type.slice(6), providerEventAt: new Date(at), providerOutcomeUpdatedAt: FieldValue.serverTimestamp()}, {merge: true});
    }
    return {status: "recorded", matchedQueueCount: snapshots.length};
  });
  if (result.status === "recorded" && FAILURE.has(event.type)) log(JSON.stringify({severity: "ERROR", event: "transactional_email_delivery_failure", provider: "resend", providerId, eventType: event.type, matchedQueueCount: result.matchedQueueCount}));
  return result;
}
function createServer({dbFactory = () => {
if (!getApps().length) initializeApp(); return getFirestore();
}, secret = process.env.RESEND_WEBHOOK_SECRET, log} = {}) {
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
        return reply(200, await recordOutcome({db, event, deliveryId: req.headers["svix-id"], log}));
      } catch (error) {
console.error("email_outcome_record_failed"); return reply(error.statusCode || 503, {error: error.statusCode === 400 ? "invalid_event" : "retry_required"});
}
    });
  });
}
if (require.main === module) createServer().listen(Number(process.env.PORT || 8080), "0.0.0.0");
module.exports = {createServer, recordOutcome};
