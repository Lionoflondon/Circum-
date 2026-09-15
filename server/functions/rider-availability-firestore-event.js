/* eslint-disable max-len, require-jsdoc */
"use strict";

const {parseFirestoreEventarcPayload} = require("./lib/eventarc-envelope");

const EVENT_TYPES = new Set([
  "google.cloud.firestore.document.v1.updated",
  "google.cloud.firestore.document.v1.written",
]);
const AVAILABILITY_FIELDS = new Set([
  "accountClosed", "accountStatus", "riderStatus", "driverStatus", "approvalStatus", "verificationStatus", "onboardingStatus",
  "isFrozen", "isSuspended", "isClosed", "vehicleApproved", "vehicleVerified", "vehicleStatus", "vehicle", "eligibilityState", "riderEligibilityState",
  "onlineIntent", "isOnline", "availabilityStatus", "dispatchEligible", "dispatchReason", "presenceState", "connectionStatus", "busy",
]);

function topLevelField(path) {
  return String(path || "").split(/[.`]/, 1)[0];
}

function riderDocument(path, collection) {
  const normalized = String(path || "").replace(/^documents\//, "");
  const match = new RegExp(`^${collection}/([A-Za-z0-9_-]{1,128})$`).exec(normalized);
  return match ? match[1] : null;
}

function relevantAvailabilityTransition(event = {}) {
  const candidates = event.changedPaths && event.changedPaths.length ?
    event.changedPaths.map(topLevelField).filter((field) => AVAILABILITY_FIELDS.has(field)) :
    [...AVAILABILITY_FIELDS];
  const changedFields = [...new Set(candidates.filter((field) =>
    JSON.stringify((event.before && event.before[field]) ?? null) !== JSON.stringify((event.after && event.after[field]) ?? null),
  ))];
  return {relevant: changedFields.length > 0, changedFields};
}

function parseAvailabilityEvent({headers = {}, body = Buffer.alloc(0), collection}) {
  const eventType = String(headers["ce-type"] || "");
  if (!EVENT_TYPES.has(eventType)) throw Object.assign(new Error("invalid_event_type"), {statusCode: 400});
  const eventId = String(headers["ce-id"] || "").trim();
  if (!eventId || eventId.length > 128) throw Object.assign(new Error("invalid_event_id"), {statusCode: 400});
  if (!["riderProfiles", "riders"].includes(collection)) throw Object.assign(new Error("invalid_event_collection"), {statusCode: 400});
  const decoded = parseFirestoreEventarcPayload(body);
  const headerPath = headers["ce-document"] || String(headers["ce-subject"] || "").replace(/^documents\//, "");
  const bodyPath = String(decoded.documentName || "").split("/documents/")[1] || "";
  const riderId = riderDocument(headerPath || bodyPath, collection);
  if (!riderId) throw Object.assign(new Error("invalid_event_document"), {statusCode: 400});
  return {eventId, riderId, sourceCollection: collection, decoded, ...relevantAvailabilityTransition(decoded)};
}

module.exports = {AVAILABILITY_FIELDS, EVENT_TYPES, parseAvailabilityEvent, relevantAvailabilityTransition, riderDocument};
