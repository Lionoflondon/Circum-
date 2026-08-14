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

test("specialized movement projections use canonical delivered terminal state", () => {
  assert.equal(movement.giftMovement("gift-done", {status: "completed"}).status, "delivered");
  assert.equal(movement.healthMovement("health-done", {status: "delivered"}).status, "delivered");
});
