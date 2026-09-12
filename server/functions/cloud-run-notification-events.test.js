"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {deliveryIdFromName, claimId} = require("./cloud-run-notification-events");

test("extracts only deliveryRequests document ids", () => {
  assert.equal(deliveryIdFromName("projects/p/databases/(default)/documents/deliveryRequests/d1"), "d1");
  assert.equal(deliveryIdFromName("documents/users/u1"), null);
});

test("business claim is stable per handler and delivery", () => {
  assert.equal(claimId("delivery_created", "d1"), claimId("delivery_created", "d1"));
  assert.notEqual(claimId("delivery_created", "d1"), claimId("gift_delivery_completed", "d1"));
});
