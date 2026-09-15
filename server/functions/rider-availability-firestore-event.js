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
const FIXTURE_PATH = /^_runtimeFixtures\/riderAvailability\/events\/([A-Za-z0-9_-]{1,128})$/;

function topLevelField(path) {
  return String(path || "").split(/[.`]/, 1)[0];
}

function riderDocument(path, collection) {
  const normalized = String(path || "").replace(/^documents\//, "");
  const match = new RegExp(`^${collection}/([A-Za-z0-9_-]{1,128})$`).exec(normalized);
  return match ? match[1] : null;
}

function fixtureDocument(path) {
  const normalized = String(path || "").replace(/^documents\//, "");
  const match = FIXTURE_PATH.exec(normalized);
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

function eventIdentity(headers) {
  const eventType = String(headers["ce-type"] || "");
  if (!EVENT_TYPES.has(eventType)) throw Object.assign(new Error("invalid_event_type"), {statusCode: 400});
  const eventId = String(headers["ce-id"] || "").trim();
  if (!eventId || eventId.length > 128) throw Object.assign(new Error("invalid_event_id"), {statusCode: 400});
  return {eventId, eventType};
}

function eventPath(headers, decoded) {
  return headers["ce-document"] || String(headers["ce-subject"] || "").replace(/^documents\//, "") || String(decoded.documentName || "").split("/documents/")[1] || "";
}

function parseAvailabilityEvent({headers = {}, body = Buffer.alloc(0), collection}) {
  const {eventId} = eventIdentity(headers);
  if (!["riderProfiles", "riders"].includes(collection)) throw Object.assign(new Error("invalid_event_collection"), {statusCode: 400});
  const decoded = parseFirestoreEventarcPayload(body);
  const riderId = riderDocument(eventPath(headers, decoded), collection);
  if (!riderId) throw Object.assign(new Error("invalid_event_document"), {statusCode: 400});
  return {eventId, riderId, sourceCollection: collection, decoded, ...relevantAvailabilityTransition(decoded)};
}

function parseFixtureAvailabilityEvent({headers = {}, body = Buffer.alloc(0)}) {
  const {eventId} = eventIdentity(headers);
  const decoded = parseFirestoreEventarcPayload(body);
  const fixtureId = fixtureDocument(eventPath(headers, decoded));
  if (!fixtureId) throw Object.assign(new Error("invalid_fixture_document"), {statusCode: 400});
  return {eventId, fixtureId, sourceCollection: "_runtimeFixtures", fixture: true, decoded, ...relevantAvailabilityTransition(decoded)};
}

module.exports = {AVAILABILITY_FIELDS, EVENT_TYPES, FIXTURE_PATH, fixtureDocument, parseAvailabilityEvent, parseFixtureAvailabilityEvent, relevantAvailabilityTransition, riderDocument};
