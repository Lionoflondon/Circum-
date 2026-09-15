"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {DocumentEventData} = require("./lib/eventarc-envelope");
const {parseAvailabilityEvent} = require("./rider-availability-firestore-event");

function protobufEvent(before, after, paths, collection = "riderProfiles") {
  const name = `projects/circum-2797c/databases/(default)/documents/${collection}/qa-rider`;
  return Buffer.from(DocumentEventData.encode(DocumentEventData.fromObject({oldValue: {name, fields: before}, value: {name, fields: after}, updateMask: {paths}})).finish());
}
function headers(collection = "riderProfiles") {
  return {"ce-type": "google.cloud.firestore.document.v1.updated", "ce-id": "availability-event-1", "ce-document": `${collection}/qa-rider`};
}

test("accepts an Eventarc Pub/Sub envelope for either availability source", () => {
  const raw = protobufEvent({approvalStatus: {stringValue: "pending"}}, {approvalStatus: {stringValue: "approved"}}, ["approvalStatus"]);
  const body = Buffer.from(JSON.stringify({message: {data: Buffer.from(JSON.stringify({data_base64: raw.toString("base64")})).toString("base64")}}));
  const profile = parseAvailabilityEvent({headers: headers(), body, collection: "riderProfiles"});
  assert.equal(profile.riderId, "qa-rider");
  assert.equal(profile.relevant, true);
  assert.deepEqual(profile.changedFields, ["approvalStatus"]);
  const record = parseAvailabilityEvent({headers: headers("riders"), body: protobufEvent({isOnline: {booleanValue: true}}, {isOnline: {booleanValue: false}}, ["isOnline"], "riders"), collection: "riders"});
  assert.equal(record.sourceCollection, "riders");
});

test("metadata-only rider events are ignored", () => {
  const event = parseAvailabilityEvent({headers: headers(), body: protobufEvent({updatedAt: {stringValue: "a"}}, {updatedAt: {stringValue: "b"}}, ["updatedAt"]), collection: "riderProfiles"});
  assert.equal(event.relevant, false);
  assert.deepEqual(event.changedFields, []);
});

test("fixture events accept only the dedicated certification path", () => {
  const {parseFixtureAvailabilityEvent} = require("./rider-availability-firestore-event");
  const name = "projects/circum-2797c/databases/(default)/documents/_runtimeFixtures/riderAvailability/events/cert-1";
  const body = Buffer.from(DocumentEventData.encode(DocumentEventData.fromObject({oldValue: {name, fields: {approvalStatus: {stringValue: "pending"}}}, value: {name, fields: {approvalStatus: {stringValue: "approved"}}}, updateMask: {paths: ["approvalStatus"]}})).finish());
  const event = parseFixtureAvailabilityEvent({headers: {"ce-type": "google.cloud.firestore.document.v1.updated", "ce-id": "fixture-event-1", "ce-document": "_runtimeFixtures/riderAvailability/events/cert-1"}, body});
  assert.equal(event.fixture, true);
  assert.equal(event.fixtureId, "cert-1");
  assert.equal(event.relevant, true);
  assert.throws(() => parseFixtureAvailabilityEvent({headers: {"ce-type": "google.cloud.firestore.document.v1.updated", "ce-id": "fixture-event-2", "ce-document": "riderProfiles/qa-rider"}, body}), /invalid_fixture_document/);
});
