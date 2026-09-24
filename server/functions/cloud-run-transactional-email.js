/* eslint-disable max-len, require-jsdoc */
"use strict";

const http = require("node:http");
const {initializeApp} = require("firebase-admin/app");
const {getFirestore, FieldValue, Timestamp} = require("firebase-admin/firestore");
const {decodeEventarcPayload} = require("./cloud-run-notification-events");
const {normalizeEmail} = require("./email-queue");
const emailPublishers = require("./transactional-email-publishers");

const EVENT_TYPE = "google.cloud.firestore.document.v1.created";
const ACCEPTED_EVENT_TYPES = new Set([EVENT_TYPE, emailPublishers.UPDATED]);
const MAX_BODY_BYTES = 2 * 1024 * 1024;
const CLAIM_LEASE_MS = 5 * 60 * 1000;
const DEFAULT_MAX_ATTEMPTS = 5;
const RETRY_BACKOFF_MS = [30 * 1000, 2 * 60 * 1000, 10 * 60 * 1000, 30 * 60 * 1000, 2 * 60 * 60 * 1000];
const EMAIL_API_URL = "https://api.resend.com/emails";
const DEFAULT_FROM_BY_CATEGORY = Object.freeze({
  gifts: "Circum Gifts <gifts@circumuk.com>",
  business: "Circum <info@circumuk.com>",
  health: "Circum <info@circumuk.com>",
  info: "Circum <info@circumuk.com>",
});
const FROM_ENV_BY_CATEGORY = Object.freeze({
  gifts: "GIFTS_EMAIL_FROM",
  business: "BUSINESS_EMAIL_FROM",
  health: "HEALTH_EMAIL_FROM",
  info: "INFO_EMAIL_FROM",
});
const SENDER_CATEGORIES = new Set(Object.keys(DEFAULT_FROM_BY_CATEGORY));

const text = (value) => `${value || ""}`.trim();

const KNOWN_INFO_EVENT_PREFIXES = [
  "account", "delivery", "notification", "password", "referral", "rider", "roth", "security",
];

function inferredSenderCategory(eventType) {
  const value = text(eventType).toLowerCase();
  if (value.startsWith("gift")) return "gifts";
  if (value.startsWith("business")) return "business";
  if (value.startsWith("health_plus")) return "health";
  if (KNOWN_INFO_EVENT_PREFIXES.some((prefix) => value.startsWith(prefix))) return "info";
  return null;
}

function senderCategoryForRecord(record = {}) {
  const explicit = text(record.senderCategory || record.senderFamily).toLowerCase();
  if (explicit && !SENDER_CATEGORIES.has(explicit)) {
    throw Object.assign(new Error("invalid_sender_category"), {statusCode: 422});
  }
  const inferred = inferredSenderCategory(record.eventType || record.type);
  if (explicit && inferred && explicit !== inferred) {
    throw Object.assign(new Error("sender_family_mismatch"), {statusCode: 422});
  }
  return explicit || inferred || "info";
}

function senderAddress(value) {
  const match = /<([^>]+)>/.exec(text(value));
  return (match ? match[1] : text(value)).trim().toLowerCase();
}

function assertAllowedSenderIdentity(category, from) {
  const address = senderAddress(from);
  if (!/@circumuk\.com$/.test(address)) {
    throw Object.assign(new Error("sender_domain_not_allowed"), {statusCode: 422});
  }
  if (category === "gifts" && address !== "gifts@circumuk.com") {
    throw Object.assign(new Error("sender_family_mismatch"), {statusCode: 422});
  }
  if (category !== "gifts" && address === "gifts@circumuk.com") {
    throw Object.assign(new Error("sender_family_mismatch"), {statusCode: 422});
  }
  if (category === "business" && address === "health@circumuk.com") {
    throw Object.assign(new Error("sender_family_mismatch"), {statusCode: 422});
  }
  if (category === "health" && address === "business@circumuk.com") {
    throw Object.assign(new Error("sender_family_mismatch"), {statusCode: 422});
  }
  if (category === "info" && !["info@circumuk.com", "notifications@circumuk.com"].includes(address)) {
    throw Object.assign(new Error("info_sender_not_allowed"), {statusCode: 422});
  }
  return from;
}

function fromForRecord(record = {}, env = process.env) {
  const category = senderCategoryForRecord(record);
  const configured = text(env[FROM_ENV_BY_CATEGORY[category]] ||
    env.INFO_EMAIL_FROM || env.NOTIFICATIONS_EMAIL_FROM);
  return assertAllowedSenderIdentity(category, configured || DEFAULT_FROM_BY_CATEGORY[category]);
}

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
  return [data.status, data.state, data.deliveryStatus, data.giftStatus, data.lifecycleStatus,
    data.paymentStatus, data.paymentState, data.settlementStatus, data.cancellationSettlementStatus,
    data.approvalStatus, data.verificationStatus]
      .map((value) => text(value).toLowerCase())
      .filter(Boolean);
}

async function revalidateSource(db, record) {
  const eventType = text(record.eventType || record.type).toLowerCase();
  if (eventType === "gift_story_ready" &&
      (!text(record.sourceRequiredStatus) || !text(record.sourceRecipientField))) {
    return {status: "suppressed", reason: "source_metadata_missing"};
  }
  const source = sourceDescriptor(record);
  if (!source) return {status: "valid"};
  const snapshot = await db.collection(source.collection).doc(source.id).get();
  if (!snapshot.exists) return {status: "suppressed", reason: "source_missing"};
  const required = text(record.sourceRequiredStatus).toLowerCase();
  if (required && !sourceState(snapshot.data() || {}).includes(required)) {
    return {status: "suppressed", reason: "source_state_changed"};
  }
  const sourceData = snapshot.data() || {};
  for (const [field, expected] of Object.entries(record.sourceRequiredFields || {})) {
    const allowed = Array.isArray(expected) ? expected : [expected];
    const actual = sourceData[field];
    const valid = allowed.some((value) => typeof value === "number" ? Number(actual) === value :
      text(actual).toLowerCase() === text(value).toLowerCase());
    if (!valid) return {status: "suppressed", reason: "source_state_changed"};
  }
  if (record.eventType === "referral_award_finalized") {
    const [inviter, referred] = await Promise.all([
      db.collection("walletTransactions").doc(`referral_reward_${source.id}_referrer`).get(),
      db.collection("walletTransactions").doc(`referral_reward_${source.id}_referred`).get(),
    ]);
    if (!inviter.exists || !referred.exists ||
        text(inviter.data().status).toLowerCase() !== "completed" ||
        text(referred.data().status).toLowerCase() !== "completed") {
      return {status: "suppressed", reason: "source_state_changed"};
    }
  }
  const recipientField = text(record.sourceRecipientField);
  if (recipientField) {
    const authoritativeRecipient = normalizeEmail(sourceData[recipientField]);
    const queuedRecipient = normalizeEmail(record.to || record.recipientEmail);
    if (!authoritativeRecipient || authoritativeRecipient !== queuedRecipient) {
      return {status: "suppressed", reason: "source_recipient_changed"};
    }
  }
  return {status: "valid", source: sourceData};
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

async function sendResend({record, to, fetchImpl = null, apiKey = process.env.RESEND_API_KEY, from = null, env = process.env}) {
  if (!text(apiKey)) {
    throw Object.assign(new Error("email_provider_not_configured"), {retryable: true, statusCode: 503});
  }
  const transport = fetchImpl || (typeof global !== "undefined" ? global.fetch : null);
  if (typeof transport !== "function") {
    throw Object.assign(new Error("email_transport_unavailable"), {retryable: true, statusCode: 503});
  }
  const resolvedFrom = fromForRecord(record, env);
  if (text(from) && text(from) !== resolvedFrom) {
    throw Object.assign(new Error("sender_family_mismatch"), {statusCode: 422});
  }
  const response = await transport(EMAIL_API_URL, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
      "Idempotency-Key": text(record.notificationId),
    },
    body: JSON.stringify({
      from: resolvedFrom,
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
  if (claim.status === "deferred") {
    throw Object.assign(new Error("email_retry_deferred"), {statusCode: 503});
  }
  if (["duplicate", "missing", "failed"].includes(claim.status)) return claim;
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
      status: terminal ? "failed" : "retryable_failed",
      failureReason: text(error && (error.providerCode || error.message)) || "email_send_failed",
      nextAttemptAt: terminal ? null : Timestamp.fromMillis(nowMs + RETRY_BACKOFF_MS[Math.min(attempt - 1, RETRY_BACKOFF_MS.length - 1)]),
      leaseOwner: null,
      leaseExpiresAt: Timestamp.fromMillis(nowMs),
    });
    if (retryable && !terminal) throw Object.assign(error, {statusCode: 503});
    return {status: terminal ? "failed" : "retryable_failed", reason: text(error && error.message)};
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
        fromConfigured: Boolean(text(process.env.GIFTS_EMAIL_FROM || process.env.BUSINESS_EMAIL_FROM ||
          process.env.HEALTH_EMAIL_FROM || process.env.INFO_EMAIL_FROM || DEFAULT_FROM_BY_CATEGORY.info)),
      });
    }
    if (req.method !== "POST" || req.url !== "/") return json(res, 404, {error: "not_found"});
    const eventType = text(req.headers["ce-type"]);
    if (!ACCEPTED_EVENT_TYPES.has(eventType)) return json(res, 400, {error: "invalid_event_type"});
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
        if (!db) db = dbFactory();
        const emailId = queueEmailIdFromName(decoded.documentName || req.headers["ce-subject"]);
        const result = emailId && eventType === EVENT_TYPE ?
          await processRecord({db, emailId, eventId}) :
          await emailPublishers.publishFromEvent({db, eventType, eventId, decoded});
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
  ACCEPTED_EVENT_TYPES,
  CLAIM_LEASE_MS,
  queueEmailIdFromName,
  sourceDescriptor,
  recipientFor,
  claimEmail,
  revalidateSource,
  sendResend,
  senderCategoryForRecord,
  fromForRecord,
  processEmailQueueRecord,
  createServer,
};
