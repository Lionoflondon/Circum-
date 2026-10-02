/* eslint-disable max-len, require-jsdoc */
"use strict";

const crypto = require("crypto");
const {FieldValue} = require("firebase-admin/firestore");

const EVENT_VERSION = "2026-08-operations-brain-v1";

function clean(value, max = 500) {
  return `${value || ""}`.trim().slice(0, max);
}

function safeKey(value) {
  const normalized = clean(value, 300).replace(/[^A-Za-z0-9_-]+/g, "_").replace(/^_+|_+$/g, "");
  return normalized || "event";
}

function eventIdFor({deliveryId, eventType, correlationId}) {
  const authority = [clean(deliveryId), clean(eventType), clean(correlationId)].join("|");
  const digest = crypto.createHash("sha256").update(authority).digest("hex").slice(0, 20);
  return `${safeKey(eventType).toLowerCase()}_${digest}`;
}

function sanitizeMetadata(value, depth = 0) {
  if (depth > 3 || value === undefined) return null;
  if (value === null || typeof value === "boolean" || typeof value === "number") return value;
  if (typeof value === "string") return clean(value, 1000);
  if (Array.isArray(value)) return value.slice(0, 20).map((item) => sanitizeMetadata(item, depth + 1));
  if (typeof value !== "object") return clean(value, 1000);
  const result = {};
  Object.entries(value).slice(0, 40).forEach(([key, item]) => {
    const normalized = key.toLowerCase();
    if (["token", "secret", "password", "clientsecret", "stripekey", "fcm", "pushtoken"].some((part) => normalized.includes(part))) return;
    result[clean(key, 80)] = sanitizeMetadata(item, depth + 1);
  });
  return result;
}

function eventRecord(input = {}) {
  const deliveryId = clean(input.deliveryId, 180);
  const eventType = clean(input.eventType, 100);
  const correlationId = clean(input.correlationId || `${eventType}:${deliveryId}`, 300);
  if (!deliveryId || !eventType) throw new Error("Operational events require deliveryId and eventType.");
  const eventId = clean(input.eventId) || eventIdFor({deliveryId, eventType, correlationId});
  const timestamp = input.timestamp || FieldValue.serverTimestamp();
  return {
    eventId,
    deliveryId,
    eventType,
    event: eventType,
    eventKey: safeKey(eventType).toLowerCase(),
    timestamp,
    createdAt: timestamp,
    actorType: clean(input.actorType || "system", 60),
    actorId: clean(input.actorId, 180) || null,
    actor: clean(input.actorId || input.actorType || "system", 180),
    source: clean(input.source || "backend", 160),
    correlationId,
    metadata: sanitizeMetadata(input.metadata || {}),
    previousState: clean(input.previousState, 100) || null,
    newState: clean(input.newState, 100) || null,
    eventVersion: EVENT_VERSION,
    immutable: true,
  };
}

function eventRef(db, deliveryId, eventId) {
  return db.collection("deliveryRequests").doc(deliveryId).collection("timeline").doc(eventId);
}

async function appendOperationalEvent(db, input, {transaction = null, batch = null} = {}) {
  const record = eventRecord(input);
  const ref = eventRef(db, record.deliveryId, record.eventId);
  if (transaction) {
    transaction.set(ref, record, {merge: false});
    return record;
  }
  if (batch) {
    batch.set(ref, record, {merge: false});
    return record;
  }
  await ref.create(record).catch((error) => {
    if (error && (error.code === 6 || error.code === "already-exists")) return;
    throw error;
  });
  return record;
}

module.exports = {
  EVENT_VERSION,
  appendOperationalEvent,
  eventIdFor,
  eventRecord,
  eventRef,
  sanitizeMetadata,
};
