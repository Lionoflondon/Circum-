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
