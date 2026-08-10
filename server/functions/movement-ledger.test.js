/* eslint-disable max-len */
"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const movement = require("./movement-ledger");

test("gift movement remains held until ready for dispatch", () => {
  const pending = movement.giftMovement("g1", {status: "procuring", senderId: "u1"});
  assert.equal(pending.serviceType, "GIFTS");
  assert.equal(pending.status, "awaiting_procurement");
  assert.equal(pending.matchingStatus, "held");

  const ready = movement.giftMovement("g1", {status: "packed", senderId: "u1"});
  assert.equal(ready.status, "requested");
  assert.equal(ready.matchingStatus, "available");
});

test("Health+ movement remains held until collection details are ready", () => {
  const scheduled = movement.healthMovement("h1", {status: "scheduled"});
  assert.equal(scheduled.serviceType, "HEALTH_PLUS");
  assert.equal(scheduled.status, "scheduled");
  assert.equal(scheduled.matchingStatus, "held");

  const ready = movement.healthMovement("h1", {
    status: "scheduled",
    collectionDetailsReady: true,
  });
  assert.equal(ready.status, "requested");
  assert.equal(ready.matchingStatus, "available");
});

test("movement delivery ids are deterministic", () => {
  assert.equal(movement.giftMovement("abc", {}).deliveryId, "gift_abc");
  assert.equal(movement.healthMovement("xyz", {}).deliveryId, "health_xyz");
});

test("Health+ source states preserve the canonical Rider lifecycle", () => {
  const assigned = movement.healthMovement("h1", {status: "assigned", assignedDriverId: "r1"});
  assert.equal(assigned.status, "accepted");
  assert.equal(assigned.matchingStatus, "accepted");
  assert.equal(assigned.assignedRiderId, "r1");
  assert.equal(movement.healthSourceStatus("arrived_at_pickup"), "arrived_at_pickup");
  assert.equal(movement.healthSourceStatus("collected"), "collected");
  assert.equal(movement.healthSourceStatus("navigating_to_dropoff"), "out_for_delivery");
  assert.equal(movement.healthSourceStatus("completed"), "delivered");
});

test("Health+ movement exposes only operational custody policy to Rider projections", () => {
  const projection = movement.healthMovement("health-1", {
    status: "ready_for_collection",
    pharmacyAddressCanonical: {coordinates: {latitude: 51.5, longitude: -0.1}},
    deliveryAddressCanonical: {coordinates: {latitude: 51.51, longitude: -0.11}},
    coldChainRequired: true,
    evidenceRequired: true,
    collectionPinRequired: true,
    prescriptionNotes: "private clinical note",
  });
  assert.equal(projection.isHealthPlus, true);
  assert.deepEqual(projection.handlingRequirements, ["cold_chain"]);
  assert.equal(projection.evidenceRequired, true);
  assert.equal(projection.collectionPinRequired, true);
  assert.equal(projection.prescriptionNotes, undefined);
});
