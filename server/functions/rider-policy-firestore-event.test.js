"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  DocumentEventData,
  EVENT_TYPE,
  parseFirestoreProfileEvent,
  relevantPolicyTransition,
  riderIdFromPath,
} = require("./rider-policy-firestore-event");

function stringValue(value) {
  return {stringValue: value};
}

function boolValue(value) {
  return {booleanValue: value};
}

function mapValue(fields) {
  return {mapValue: {fields}};
}

function encodedEvent(before, after, changedPaths = Object.keys(after)) {
  const name = "projects/circum-2797c/databases/(default)/documents/riderProfiles/qa-rider";
  return Buffer.from(DocumentEventData.encode(DocumentEventData.fromObject({
    oldValue: {name, fields: before},
    value: {name, fields: after},
    updateMask: {paths: changedPaths},
  })).finish());
}

function parse(before, after, changedPaths) {
  return parseFirestoreProfileEvent({
    headers: {
      "ce-type": EVENT_TYPE,
      "ce-id": "event-1",
      "ce-document": "riderProfiles/qa-rider",
    },
    body: encodedEvent(before, after, changedPaths),
  });
}

test("profile Eventarc path accepts only the exact canonical Rider document", () => {
  assert.equal(riderIdFromPath("riderProfiles/qa-rider"), "qa-rider");
  assert.equal(riderIdFromPath("documents/riderProfiles/qa-rider"), "qa-rider");
  assert.equal(riderIdFromPath("riders/qa-rider"), null);
  assert.equal(riderIdFromPath("riderProfiles/qa-rider/private/data"), null);
});

test("approval, rejection, terminal, recovery and vehicle transitions are relevant", () => {
  const scenarios = [
    ["approvalStatus", stringValue("pending"), stringValue("approved")],
    ["approvalStatus", stringValue("approved"), stringValue("rejected")],
    ["driverStatus", stringValue("active"), stringValue("suspended")],
    ["isFrozen", boolValue(false), boolValue(true)],
    ["accountStatus", stringValue("active"), stringValue("closed")],
    ["isSuspended", boolValue(true), boolValue(false)],
    ["vehicleApproved", boolValue(false), boolValue(true)],
    ["vehicle", mapValue({status: stringValue("pending")}), mapValue({status: stringValue("approved")})],
  ];
  for (const [field, before, after] of scenarios) {
    const event = parse({[field]: before}, {[field]: after}, [field]);
    assert.equal(event.relevant, true, field);
    assert.deepEqual(event.changedFields, [field]);
  }
});

test("updatedAt, availability, heartbeat and location-only updates are ignored", () => {
  for (const field of ["updatedAt", "availabilityStatus", "lastHeartbeatAt", "currentLocation", "isOnline"]) {
    const event = parse({[field]: stringValue("before")}, {[field]: stringValue("after")}, [field]);
    assert.equal(event.relevant, false, field);
  }
});

test("an update mask cannot manufacture a transition absent from before and after", () => {
  const transition = relevantPolicyTransition({
    before: {approvalStatus: "approved"},
    after: {approvalStatus: "approved"},
    changedPaths: ["approvalStatus", "updatedAt"],
  });
  assert.deepEqual(transition, {relevant: false, changedFields: []});
});

test("invalid event type and document are rejected", () => {
  const body = encodedEvent({}, {}, []);
  assert.throws(() => parseFirestoreProfileEvent({headers: {"ce-type": "wrong", "ce-id": "1"}, body}), /invalid_event_type/);
  assert.throws(() => parseFirestoreProfileEvent({headers: {"ce-type": EVENT_TYPE, "ce-id": "1", "ce-document": "riders/qa-rider"}, body}), /invalid_event_document/);
});

module.exports = {encodedEvent};
