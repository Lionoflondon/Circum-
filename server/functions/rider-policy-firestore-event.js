/* eslint-disable max-len, require-jsdoc */
"use strict";

const protobuf = require("protobufjs");

const EVENT_TYPE = "google.cloud.firestore.document.v1.updated";
const POLICY_FIELDS = new Set([
  "accountClosed", "accountStatus", "riderStatus", "driverStatus",
  "approvalStatus", "verificationStatus", "onboardingStatus",
  "isFrozen", "isSuspended", "isClosed", "vehicleApproved",
  "vehicleVerified", "vehicleStatus", "vehicle", "eligibilityState",
  "riderEligibilityState",
]);

function firestoreEventTypes() {
  const root = new protobuf.Root();
  const timestamp = new protobuf.Type("Timestamp")
      .add(new protobuf.Field("seconds", 1, "int64"))
      .add(new protobuf.Field("nanos", 2, "int32"));
  const geoPoint = new protobuf.Type("LatLng")
      .add(new protobuf.Field("latitude", 1, "double"))
      .add(new protobuf.Field("longitude", 2, "double"));
  const value = new protobuf.Type("Value");
  const arrayValue = new protobuf.Type("ArrayValue")
      .add(new protobuf.Field("values", 1, "Value", "repeated"));
  const mapValue = new protobuf.Type("MapValue")
      .add(new protobuf.MapField("fields", 1, "string", "Value"));
  value.add(new protobuf.Field("nullValue", 11, "int32"))
      .add(new protobuf.Field("booleanValue", 1, "bool"))
      .add(new protobuf.Field("integerValue", 2, "int64"))
      .add(new protobuf.Field("doubleValue", 3, "double"))
      .add(new protobuf.Field("timestampValue", 10, "Timestamp"))
      .add(new protobuf.Field("stringValue", 17, "string"))
      .add(new protobuf.Field("bytesValue", 18, "bytes"))
      .add(new protobuf.Field("referenceValue", 5, "string"))
      .add(new protobuf.Field("geoPointValue", 8, "LatLng"))
      .add(new protobuf.Field("arrayValue", 9, "ArrayValue"))
      .add(new protobuf.Field("mapValue", 6, "MapValue"));
  const document = new protobuf.Type("Document")
      .add(new protobuf.Field("name", 1, "string"))
      .add(new protobuf.MapField("fields", 2, "string", "Value"));
  const fieldMask = new protobuf.Type("FieldMask")
      .add(new protobuf.Field("paths", 1, "string", "repeated"));
  const eventData = new protobuf.Type("DocumentEventData")
      .add(new protobuf.Field("value", 1, "Document"))
      .add(new protobuf.Field("oldValue", 2, "Document"))
      .add(new protobuf.Field("updateMask", 3, "FieldMask"));
  root.define("circum.firestoreevent")
      .add(timestamp).add(geoPoint).add(value).add(arrayValue).add(mapValue)
      .add(document).add(fieldMask).add(eventData);
  return {eventData};
}

const {eventData: DocumentEventData} = firestoreEventTypes();

function valueToJs(value) {
  if (!value) return undefined;
  const has = (field) => Object.prototype.hasOwnProperty.call(value, field);
  if (has("nullValue")) return null;
  if (has("booleanValue")) return value.booleanValue;
  if (has("integerValue")) return `${value.integerValue}`;
  if (has("doubleValue")) return value.doubleValue;
  if (has("stringValue")) return value.stringValue;
  if (has("referenceValue")) return value.referenceValue;
  if (has("bytesValue")) return Buffer.from(value.bytesValue).toString("base64");
  if (has("timestampValue")) return {seconds: `${value.timestampValue.seconds}`, nanos: value.timestampValue.nanos || 0};
  if (has("geoPointValue")) return {latitude: value.geoPointValue.latitude, longitude: value.geoPointValue.longitude};
  if (has("arrayValue")) return (value.arrayValue.values || []).map(valueToJs);
  if (has("mapValue")) return Object.fromEntries(Object.entries(value.mapValue.fields || {}).map(([key, nested]) => [key, valueToJs(nested)]));
  return undefined;
}

function documentFields(document = {}) {
  return Object.fromEntries(Object.entries(document.fields || {}).map(([key, value]) => [key, valueToJs(value)]));
}

function decodeEventData(buffer) {
  const decoded = DocumentEventData.decode(buffer);
  return {
    before: documentFields(decoded.oldValue),
    after: documentFields(decoded.value),
    changedPaths: decoded.updateMask && decoded.updateMask.paths || [],
    documentName: decoded.value && decoded.value.name || decoded.oldValue && decoded.oldValue.name || "",
  };
}

function topLevelField(path) {
  return String(path || "").split(/[.`]/, 1)[0];
}

function relevantPolicyTransition(event) {
  const candidates = event.changedPaths.length > 0 ?
    event.changedPaths.map(topLevelField).filter((field) => POLICY_FIELDS.has(field)) :
    [...POLICY_FIELDS];
  const changedFields = [...new Set(candidates.filter((field) =>
    JSON.stringify(event.before[field] ?? null) !== JSON.stringify(event.after[field] ?? null),
  ))];
  return {relevant: changedFields.length > 0, changedFields};
}

function riderIdFromPath(path) {
  const normalized = String(path || "").replace(/^documents\//, "");
  const match = /^riderProfiles\/([A-Za-z0-9_-]{1,128})$/.exec(normalized);
  return match ? match[1] : null;
}

function parseFirestoreProfileEvent({headers = {}, body = Buffer.alloc(0)}) {
  const type = String(headers["ce-type"] || "");
  if (type !== EVENT_TYPE) throw Object.assign(new Error("invalid_event_type"), {statusCode: 400});
  const eventId = String(headers["ce-id"] || "").trim();
  if (!eventId || eventId.length > 128) throw Object.assign(new Error("invalid_event_id"), {statusCode: 400});
  const decoded = decodeEventData(body);
  const headerPath = headers["ce-document"] || String(headers["ce-subject"] || "").replace(/^documents\//, "");
  const bodyPath = decoded.documentName.split("/documents/")[1] || "";
  const riderId = riderIdFromPath(headerPath || bodyPath);
  if (!riderId) throw Object.assign(new Error("invalid_event_document"), {statusCode: 400});
  const transition = relevantPolicyTransition(decoded);
  return {eventId, riderId, ...transition, decoded};
}

module.exports = {
  DocumentEventData,
  EVENT_TYPE,
  POLICY_FIELDS,
  decodeEventData,
  parseFirestoreProfileEvent,
  relevantPolicyTransition,
  riderIdFromPath,
};
