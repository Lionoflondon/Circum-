/* eslint-disable max-len */
"use strict";

const http = require("node:http");
const {initializeApp} = require("firebase-admin/app");
const {getFirestore, FieldValue, Timestamp} = require("firebase-admin/firestore");
const {decodeEventData} = require("./rider-policy-firestore-event");
const {FIXTURE_COLLECTION, fixtureDb} = require("./gift-story-fixture-db");

const MAX_BODY_BYTES = 2 * 1024 * 1024;
const CLAIM_LEASE_MS = 5 * 60 * 1000;
const handlers = {
  delivery_created: {
    eventType: "google.cloud.firestore.document.v1.created",
    run: async ({db, deliveryId, after, effects}) => {
      const {handleDeliveryCreated} = require("./platform-notifications");
      return handleDeliveryCreated({id: deliveryId, data: () => after, ref: db.collection("deliveryRequests").doc(deliveryId)}, {effects});
    },
  },
  gift_delivery_completed: {
    eventType: "google.cloud.firestore.document.v1.updated",
    qualifies: ({before, after}) => {
      const {isGiftDelivery, isComplete} = require("./gift-story-automation");
      return isGiftDelivery(after) && !isComplete(before.status) && isComplete(after.status);
    },
    run: async ({db, deliveryId, before, after}) => {
      const {handleGiftDeliveryCompleted} = require("./gift-story-automation");
      const {isGiftStoryOwner} = require("./gift-story-completion-core");
      if (!await isGiftStoryOwner(db, "cloud_run")) {
        throw Object.assign(new Error("gift_story_owner_transitioning"), {statusCode: 503});
      }
      const ref = db.collection(eventCollection("gift_delivery_completed")).doc(deliveryId);
      return handleGiftDeliveryCompleted({before: {id: deliveryId, data: () => before, ref}, after: {id: deliveryId, data: () => after, ref}}, {params: {deliveryId}}, {source: "cloud_run", db});
    },
  },
};

function json(res, status, body) {
  res.writeHead(status, {"content-type": "application/json; charset=utf-8", "cache-control": "no-store"});
  res.end(JSON.stringify(body));
}

function eventCollection(kind) {
  if (kind === "gift_delivery_completed" &&
      process.env.GIFT_STORY_EVENT_COLLECTION_OVERRIDE === FIXTURE_COLLECTION) {
    return FIXTURE_COLLECTION;
  }
  return "deliveryRequests";
}

function deliveryIdFromName(name, collection = "deliveryRequests") {
  const path = String(name || "").split("/documents/")[1] || String(name || "").replace(/^documents\//, "");
  const escapedCollection = collection.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const match = new RegExp(`^${escapedCollection}\\/([^/]+)$`).exec(path);
  return match && match[1];
}

function claimId(kind, deliveryId) {
  return Buffer.from(`${kind}:${deliveryId}`).toString("base64url");
}

async function waitForCompletedClaim(ref, maxWaitMs = 30000) {
  const deadline = Date.now() + maxWaitMs;
  while (Date.now() < deadline) {
    await new Promise((resolve) => setTimeout(resolve, 50));
    const snapshot = await ref.get();
    const current = snapshot.exists ? snapshot.data() || {} : {};
    if (current.status === "completed") return {status: "duplicate"};
    if (current.status !== "processing") break;
  }
  throw Object.assign(new Error("event_already_processing"), {statusCode: 503});
}

function jsonValueToJs(value) {
  if (!value || typeof value !== "object") return undefined;
  if (Object.prototype.hasOwnProperty.call(value, "nullValue")) return null;
  if (Object.prototype.hasOwnProperty.call(value, "booleanValue")) return value.booleanValue;
  if (Object.prototype.hasOwnProperty.call(value, "integerValue")) return String(value.integerValue);
  if (Object.prototype.hasOwnProperty.call(value, "doubleValue")) return value.doubleValue;
  if (Object.prototype.hasOwnProperty.call(value, "stringValue")) return value.stringValue;
  if (Object.prototype.hasOwnProperty.call(value, "referenceValue")) return value.referenceValue;
  if (Object.prototype.hasOwnProperty.call(value, "bytesValue")) return value.bytesValue;
  if (Object.prototype.hasOwnProperty.call(value, "timestampValue")) return value.timestampValue;
  if (Object.prototype.hasOwnProperty.call(value, "geoPointValue")) return value.geoPointValue;
  if (Object.prototype.hasOwnProperty.call(value, "arrayValue")) {
    return (value.arrayValue.values || []).map(jsonValueToJs);
  }
  if (Object.prototype.hasOwnProperty.call(value, "mapValue")) {
    return Object.fromEntries(Object.entries(value.mapValue.fields || {})
        .map(([key, nested]) => [key, jsonValueToJs(nested)]));
  }
  return undefined;
}

function jsonDocumentFields(document = {}) {
  return Object.fromEntries(Object.entries(document.fields || {})
      .map(([key, value]) => [key, jsonValueToJs(value)]));
}

function decodeJsonDocumentEvent(event = {}) {
  const value = event.value || event.after || {};
  const oldValue = event.oldValue || event.before || {};
  return {
    before: jsonDocumentFields(oldValue),
    after: jsonDocumentFields(value),
    changedPaths: event.updateMask && event.updateMask.fieldPaths ||
      event.updateMask && event.updateMask.paths || [],
    documentName: value.name || oldValue.name || "",
  };
}

function parseJson(buffer) {
  try {
    return JSON.parse(buffer.toString("utf8"));
  } catch (_) {
    return null;
  }
}

// Eventarc's Pub/Sub push binding wraps the Firestore protobuf event in
// message.data.  Keep support for direct protobuf events too, so a transport
// change cannot turn a valid event into an unclaimed 500 response.
function decodeEventarcPayload(body) {
  try {
    const outer = parseJson(body);
    if (!outer || !outer.message || typeof outer.message.data !== "string") {
      return decodeEventData(body);
    }
    const messageData = Buffer.from(outer.message.data, "base64");
    const cloudEvent = parseJson(messageData);
    if (!cloudEvent) return decodeEventData(messageData);

    if (typeof cloudEvent.data_base64 === "string") {
      return decodeEventData(Buffer.from(cloudEvent.data_base64, "base64"));
    }
    if (typeof cloudEvent.data === "string") {
      const nested = Buffer.from(cloudEvent.data, "base64");
      return decodeEventData(nested);
    }
    if (cloudEvent.data && typeof cloudEvent.data === "object") {
      return decodeJsonDocumentEvent(cloudEvent.data);
    }
    if (cloudEvent.value || cloudEvent.oldValue) return decodeJsonDocumentEvent(cloudEvent);
    throw Object.assign(new Error("invalid_event_payload"), {statusCode: 400});
  } catch (error) {
    if (!error.statusCode) error.statusCode = 400;
    throw error;
  }
}

async function processOnce({db, kind, eventId, deliveryId, before, after, run, waitForBusyMs = 30000}) {
  const ref = db.collection("eventHandlerClaims").doc(claimId(kind, deliveryId));
  const lease = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const current = snap.exists ? snap.data() || {} : {};
    if (current.status === "completed") return "duplicate";
    const leaseUntil = current.leaseExpiresAt && typeof current.leaseExpiresAt.toMillis === "function" ? current.leaseExpiresAt.toMillis() : 0;
    if (current.status === "processing" && leaseUntil > Date.now()) return "busy";
    const now = Date.now();
    const leaseOwner = `${eventId}:${now}`;
    tx.set(ref, {
      operation: kind,
      handler: kind,
      deliveryId,
      eventId,
      lastEventId: eventId,
      status: "processing",
      leaseOwner,
      leaseAcquiredAt: Timestamp.fromMillis(now),
      leaseExpiresAt: Timestamp.fromMillis(now + CLAIM_LEASE_MS),
      attemptCount: Number(current.attemptCount || 0) + 1,
      createdAt: current.createdAt || FieldValue.serverTimestamp(),
      startedAt: current.startedAt || FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    return {leaseOwner};
  });
  if (lease === "duplicate") return {status: "duplicate"};
  if (lease === "busy") return waitForCompletedClaim(ref, waitForBusyMs);
  const effects = {
    run: async (effectId, execute) => {
      const mayRun = await db.runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        const current = snap.exists ? snap.data() || {} : {};
        const expiresAt = current.leaseExpiresAt && typeof current.leaseExpiresAt.toMillis === "function" ? current.leaseExpiresAt.toMillis() : 0;
        if (current.status !== "processing" || current.leaseOwner !== lease.leaseOwner || expiresAt <= Date.now()) throw Object.assign(new Error("lease_lost"), {statusCode: 503});
        const effect = current.effects && current.effects[effectId];
        return !(effect && effect.status === "completed");
      });
      if (!mayRun) return {status: "duplicate"};
      const result = await execute();
      await db.runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        const current = snap.exists ? snap.data() || {} : {};
        const expiresAt = current.leaseExpiresAt && typeof current.leaseExpiresAt.toMillis === "function" ? current.leaseExpiresAt.toMillis() : 0;
        if (current.status !== "processing" || current.leaseOwner !== lease.leaseOwner || expiresAt <= Date.now()) throw Object.assign(new Error("lease_lost"), {statusCode: 503});
        tx.update(ref, {[`effects.${effectId}`]: {status: "completed", completedAt: FieldValue.serverTimestamp()}});
      });
      return {status: "completed", result};
    },
  };
  try {
    await run({db, deliveryId, before, after, effects});
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const current = snap.exists ? snap.data() || {} : {};
      const expiresAt = current.leaseExpiresAt && typeof current.leaseExpiresAt.toMillis === "function" ? current.leaseExpiresAt.toMillis() : 0;
      if (current.status !== "processing" || current.leaseOwner !== lease.leaseOwner || expiresAt <= Date.now()) throw Object.assign(new Error("lease_lost"), {statusCode: 503});
      tx.update(ref, {status: "completed", completedAt: FieldValue.serverTimestamp(), leaseOwner: null, leaseExpiresAt: Timestamp.fromMillis(Date.now()), updatedAt: FieldValue.serverTimestamp()});
    });
    return {status: "completed"};
  } catch (error) {
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const current = snap.exists ? snap.data() || {} : {};
      if (current.leaseOwner !== lease.leaseOwner) return;
      tx.update(ref, {status: "retryable_failed", lastError: String(error && error.message || error).slice(0, 500), leaseOwner: null, leaseExpiresAt: Timestamp.fromMillis(Date.now()), updatedAt: FieldValue.serverTimestamp()});
    }).catch(() => {});
    throw error;
  }
}

function createServer(options = {}) {
  const kind = options.kind || process.env.HANDLER_KIND;
  const definition = handlers[kind];
  const once = options.processOnce || processOnce;
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
        const decoded = decodeEventarcPayload(Buffer.concat(chunks));
        const deliveryId = deliveryIdFromName(decoded.documentName || req.headers["ce-subject"], eventCollection(kind));
        if (!deliveryId) return json(res, 400, {error: "invalid_document"});
        if (definition.qualifies && !definition.qualifies(decoded)) return json(res, 200, {ok: true, status: "ignored"});
        if (!db) db = dbFactory();
        const eventDb = kind === "gift_delivery_completed" && eventCollection(kind) === FIXTURE_COLLECTION ?
          fixtureDb(db, deliveryId) : db;
        const result = await once({db: eventDb, kind, eventId, deliveryId, before: decoded.before, after: decoded.after, run: definition.run});
        return json(res, 200, {ok: true, ...result});
      } catch (error) {
        console.error("notification_event_failed", {handler: kind, eventId, reason: error && error.message || "unknown"});
        return json(res, Number(error.statusCode) || 500, {error: Number(error.statusCode) === 503 ? "busy" : "handler_failed"});
      }
    });
  });
}

if (require.main === module) createServer().listen(Number(process.env.PORT || 8080), "0.0.0.0");

module.exports = {
  createServer,
  decodeEventarcPayload,
  deliveryIdFromName,
  processOnce,
  claimId,
  handlers,
};
