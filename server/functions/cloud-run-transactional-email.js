/* eslint-disable max-len, require-jsdoc */
"use strict";

const http = require("node:http");
const {initializeApp} = require("firebase-admin/app");
const {getFirestore, FieldValue, Timestamp} = require("firebase-admin/firestore");
const {decodeEventarcPayload} = require("./cloud-run-notification-events");
const {normalizeEmail} = require("./email-queue");

const EVENT_TYPE = "google.cloud.firestore.document.v1.created";
const MAX_BODY_BYTES = 2 * 1024 * 1024;
const CLAIM_LEASE_MS = 5 * 60 * 1000;
const DEFAULT_MAX_ATTEMPTS = 5;
const RETRY_BACKOFF_MS = [30 * 1000, 2 * 60 * 1000, 10 * 60 * 1000, 30 * 60 * 1000, 2 * 60 * 60 * 1000];
const EMAIL_API_URL = "https://api.resend.com/emails";
const DEFAULT_FROM = "Circum <gifts@circumuk.com>";

const text = (value) => `${value || ""}`.trim();

function queueEmailIdFromName(name) {
  const path = String(name || "").split("/documents/")[1] || String(name || "").replace(/^documents\//, "");
  const match = /^emailQueue\/([^/]+)$/.exec(path);
  return match && match[1];
}

function claimRef(db, emailId) {
  return db.collection("emailQueue").doc(emailId);
}

function millis(value) {
  if (!value) return 0;
  if (typeof value.toMillis === "function") return value.toMillis();
  const parsed = new Date(value).getTime();
  return Number.isFinite(parsed) ? parsed : 0;
}

function terminalStatus(status) {
  return new Set(["sent", "suppressed", "failed"]).has(text(status).toLowerCase());
}

async function claimEmail({db, emailId, eventId, nowMs = Date.now()}) {
  const ref = claimRef(db, emailId);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) return {status: "missing"};
    const current = snap.data() || {};
    if (terminalStatus(current.status)) return {status: "duplicate", current};
    const leaseUntil = millis(current.leaseExpiresAt);
    if (current.status === "processing" && leaseUntil > nowMs) {
      return {status: "busy", current};
    }
    const attempts = Number(current.attempts || 0);
    const maxAttempts = Math.max(1, Number(current.maxAttempts || DEFAULT_MAX_ATTEMPTS));
    if (attempts >= maxAttempts) {
      tx.set(ref, {
        status: "failed",
        failureReason: "max_attempts_exceeded",
        updatedAt: FieldValue.serverTimestamp(),
        leaseOwner: null,
        leaseExpiresAt: Timestamp.fromMillis(nowMs),
      }, {merge: true});
      return {status: "failed", current: {...current, status: "failed"}};
    }
    const nextAttemptAt = millis(current.nextAttemptAt);
    if (current.status === "retryable_failed" && nextAttemptAt > nowMs) {
      return {status: "deferred", current};
    }
    const leaseOwner = `${text(eventId)}:${nowMs}`;
    tx.set(ref, {
      status: "processing",
      eventId: text(eventId),
      leaseOwner,
      leaseAcquiredAt: Timestamp.fromMillis(nowMs),
      leaseExpiresAt: Timestamp.fromMillis(nowMs + CLAIM_LEASE_MS),
      attempts: attempts + 1,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    return {status: "claimed", leaseOwner, attempts: attempts + 1, maxAttempts};
  });
}

async function updateQueue(db, emailId, value) {
  await claimRef(db, emailId).set({...value, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
}

function sourceDescriptor(record = {}) {
  if (record.sourceCollection && record.sourceDocumentId) {
    return {collection: text(record.sourceCollection), id: text(record.sourceDocumentId)};
  }
  if (record.giftRequestId || record.giftId) {
    return {collection: "giftRequests", id: text(record.giftRequestId || record.giftId)};
  }
  if (record.pickupId || record.relatedEntityId) {
    return {collection: "prescriptionPickups", id: text(record.pickupId || record.relatedEntityId)};
  }
  return null;
}

function sourceState(data = {}) {
  return [data.status, data.state, data.deliveryStatus, data.giftStatus, data.lifecycleStatus]
      .map((value) => text(value).toLowerCase())
      .filter(Boolean);
}

async function revalidateSource(db, record) {
  const source = sourceDescriptor(record);
  if (!source) return {status: "valid"};
  const snapshot = await db.collection(source.collection).doc(source.id).get();
  if (!snapshot.exists) return {status: "suppressed", reason: "source_missing"};
  const required = text(record.sourceRequiredStatus).toLowerCase();
  if (required && !sourceState(snapshot.data() || {}).includes(required)) {
    return {status: "suppressed", reason: "source_state_changed"};
  }
  return {status: "valid", source: snapshot.data() || {}};
}

function recipientFor(record) {
  if (record.recipientSuppressed || record.suppressed || record.suppressionReason) {
    return {status: "suppressed", reason: text(record.suppressionReason) || "recipient_suppressed"};
  }
  const email = normalizeEmail(record.to || record.recipientEmail);
  return email ? {status: "valid", email} : {status: "suppressed", reason: "invalid_recipient"};
}

function retryableProviderStatus(status) {
  return status === 408 || status === 425 || status === 429 || status >= 500;
}

async function sendResend({record, to, fetchImpl = null, apiKey = process.env.RESEND_API_KEY, from = process.env.GIFTS_EMAIL_FROM || DEFAULT_FROM}) {
  if (!text(apiKey)) {
    throw Object.assign(new Error("email_provider_not_configured"), {retryable: true, statusCode: 503});
  }
  const transport = fetchImpl || (typeof global !== "undefined" ? global.fetch : null);
  if (typeof transport !== "function") {
    throw Object.assign(new Error("email_transport_unavailable"), {retryable: true, statusCode: 503});
  }
  const response = await transport(EMAIL_API_URL, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
      "Idempotency-Key": text(record.notificationId),
    },
    body: JSON.stringify({
      from,
      to: [to],
      subject: text(record.subject),
      text: text(record.text || record.body),
      ...(text(record.html) ? {html: record.html} : {}),
      tags: Array.isArray(record.providerTags) ? record.providerTags : [],
    }),
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    const error = new Error(text(payload.message) || `email_provider_http_${response.status}`);
    error.providerCode = text(payload.name) || `http_${response.status}`;
    error.retryable = retryableProviderStatus(response.status);
    error.statusCode = error.retryable ? 503 : 422;
    throw error;
  }
  return {providerId: text(payload.id)};
}

async function processEmailQueueRecord({db, emailId, eventId, fetchImpl = null, nowMs = Date.now(), apiKey, from}) {
  const claim = await claimEmail({db, emailId, eventId, nowMs});
  if (["duplicate", "missing", "deferred", "failed"].includes(claim.status)) return claim;
  if (claim.status === "busy") throw Object.assign(new Error("email_already_processing"), {statusCode: 503});
  const ref = claimRef(db, emailId);
  const snapshot = await ref.get();
  const record = snapshot.data() || {};
  const recipient = recipientFor(record);
  if (recipient.status !== "valid") {
    await updateQueue(db, emailId, {status: "suppressed", failureReason: recipient.reason, leaseOwner: null, leaseExpiresAt: Timestamp.fromMillis(nowMs)});
    return {status: "suppressed", reason: recipient.reason};
  }
  const source = await revalidateSource(db, record);
  if (source.status !== "valid") {
    await updateQueue(db, emailId, {status: "suppressed", failureReason: source.reason, leaseOwner: null, leaseExpiresAt: Timestamp.fromMillis(nowMs)});
    return {status: "suppressed", reason: source.reason};
  }
  try {
    const result = await sendResend({record, to: recipient.email, fetchImpl, apiKey, from});
    await updateQueue(db, emailId, {
      status: "sent",
      provider: "resend",
      providerId: result.providerId || null,
      sentAt: FieldValue.serverTimestamp(),
      failureReason: null,
      leaseOwner: null,
      leaseExpiresAt: Timestamp.fromMillis(nowMs),
    });
    return {status: "sent", providerId: result.providerId || null};
  } catch (error) {
    const retryable = error && error.retryable;
    const attempt = Number(claim.attempts || 1);
    const maxAttempts = Number(claim.maxAttempts || DEFAULT_MAX_ATTEMPTS);
    const terminal = !retryable || attempt >= maxAttempts;
    await updateQueue(db, emailId, {
      status: terminal ? "suppressed" : "retryable_failed",
      failureReason: text(error && (error.providerCode || error.message)) || "email_send_failed",
      nextAttemptAt: terminal ? null : Timestamp.fromMillis(nowMs + RETRY_BACKOFF_MS[Math.min(attempt - 1, RETRY_BACKOFF_MS.length - 1)]),
      leaseOwner: null,
      leaseExpiresAt: Timestamp.fromMillis(nowMs),
    });
    if (retryable && !terminal) throw Object.assign(error, {statusCode: 503});
    return {status: terminal ? "suppressed" : "failed", reason: text(error && error.message)};
  }
}

function json(res, status, body) {
  res.writeHead(status, {"content-type": "application/json; charset=utf-8", "cache-control": "no-store"});
  res.end(JSON.stringify(body));
}

function createServer(options = {}) {
  const dbFactory = options.dbFactory || (() => {
    initializeApp();
    const db = getFirestore();
    db.settings({ignoreUndefinedProperties: true});
    return db;
  });
  const processRecord = options.processRecord || processEmailQueueRecord;
  let db;
  return http.createServer((req, res) => {
    if (req.method === "GET" && req.url === "/health") {
      return json(res, 200, {
        status: "ok",
        service: "circum-transactional-email",
        sourceSha: process.env.CIRCUM_SOURCE_SHA || "unknown",
        providerConfigured: Boolean(text(process.env.RESEND_API_KEY)),
        fromConfigured: Boolean(text(process.env.GIFTS_EMAIL_FROM || DEFAULT_FROM)),
      });
    }
    if (req.method !== "POST" || req.url !== "/") return json(res, 404, {error: "not_found"});
    if (text(req.headers["ce-type"]) !== EVENT_TYPE) return json(res, 400, {error: "invalid_event_type"});
    const eventId = text(req.headers["ce-id"]);
    if (!eventId || eventId.length > 256) return json(res, 400, {error: "invalid_event_id"});
    let size = 0;
    const chunks = [];
    req.on("data", (chunk) => {
      size += chunk.length;
      if (size <= MAX_BODY_BYTES) chunks.push(chunk);
    });
    req.on("end", async () => {
      if (size > MAX_BODY_BYTES) return json(res, 413, {error: "request_too_large"});
      try {
        let decoded;
        try {
          decoded = decodeEventarcPayload(Buffer.concat(chunks));
        } catch (error) {
          throw Object.assign(error, {statusCode: Number(error.statusCode) || 400});
        }
        const emailId = queueEmailIdFromName(decoded.documentName || req.headers["ce-subject"]);
        if (!emailId) return json(res, 400, {error: "invalid_email_queue_document"});
        if (!db) db = dbFactory();
        const result = await processRecord({db, emailId, eventId});
        return json(res, 200, {ok: true, ...result});
      } catch (error) {
        console.error("transactional_email_failed", {eventId, reason: text(error && error.message) || "unknown"});
        return json(res, Number(error && error.statusCode) || 500, {error: Number(error && error.statusCode) === 503 ? "retryable" : "handler_failed"});
      }
    });
  });
}

if (require.main === module) createServer().listen(Number(process.env.PORT || 8080), "0.0.0.0");

module.exports = {
  EVENT_TYPE,
  CLAIM_LEASE_MS,
  queueEmailIdFromName,
  sourceDescriptor,
  recipientFor,
  claimEmail,
  revalidateSource,
  sendResend,
  processEmailQueueRecord,
  createServer,
};
