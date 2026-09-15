/*
 * Firestore Eventarc envelope parser.
 *
 * A Cloud Run destination can receive a direct Firestore protobuf event, or
 * Eventarc's Pub/Sub push envelope whose message.data is base64 encoded. That
 * value can itself be a Firestore protobuf or a JSON CloudEvent. New Cloud Run
 * Firestore handlers must use parseFirestoreEventarcPayload rather than
 * assuming that an HTTP body is always a raw DocumentEventData protobuf.
 */
"use strict";

const protobuf = require("protobufjs");

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

function documentFields(document) {
  return Object.fromEntries(Object.entries((document || {}).fields || {})
      .map(([key, value]) => [key, valueToJs(value)]));
}

function decodeFirestoreEventData(buffer) {
  const decoded = DocumentEventData.decode(buffer);
  return {
    before: documentFields(decoded.oldValue),
    after: documentFields(decoded.value),
    changedPaths: decoded.updateMask && decoded.updateMask.paths || [],
    documentName: decoded.value && decoded.value.name || decoded.oldValue && decoded.oldValue.name || "",
  };
}

function decodeJsonDocumentEvent(event = {}) {
  const value = event.value || event.after || {};
  const oldValue = event.oldValue || event.before || {};
  return {
    before: documentFields(oldValue),
    after: documentFields(value),
    changedPaths: event.updateMask && event.updateMask.fieldPaths || event.updateMask && event.updateMask.paths || [],
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

function parseFirestoreEventarcPayload(body) {
  const outer = parseJson(body);
  if (!outer || !outer.message || typeof outer.message.data !== "string") {
    return decodeFirestoreEventData(body);
  }
  const messageData = Buffer.from(outer.message.data, "base64");
  const cloudEvent = parseJson(messageData);
  if (!cloudEvent) return decodeFirestoreEventData(messageData);
  if (typeof cloudEvent.data_base64 === "string") {
    return decodeFirestoreEventData(Buffer.from(cloudEvent.data_base64, "base64"));
  }
  if (typeof cloudEvent.data === "string") {
    return decodeFirestoreEventData(Buffer.from(cloudEvent.data, "base64"));
  }
  if (cloudEvent.data && typeof cloudEvent.data === "object") return decodeJsonDocumentEvent(cloudEvent.data);
  if (cloudEvent.value || cloudEvent.oldValue) return decodeJsonDocumentEvent(cloudEvent);
  throw Object.assign(new Error("invalid_event_payload"), {statusCode: 400});
}

module.exports = {
  DocumentEventData,
  decodeFirestoreEventData,
  parseFirestoreEventarcPayload,
};
