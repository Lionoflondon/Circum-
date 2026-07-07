"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const deliveryTracking = require("./delivery-tracking")._private;

test("collection PIN verification patch updates backend tracking fields", () => {
  const patch = deliveryTracking.patchForTransition({
    action: "verify_collection_pin",
    nextStatus: "pickup_verified",
    riderId: "rider-1",
  });
  assert.equal(patch.status, "pickup_verified");
  assert.equal(patch.collectionPinVerified, true);
  assert.equal(patch.collectionPinVerifiedBy, "rider-1");
  assert.equal(Object.prototype.hasOwnProperty.call(patch, "deliveryPin"), false);
  assert.equal(Object.prototype.hasOwnProperty.call(patch, "collectionPin"), false);
});

test("receiver PIN verification patch delivers without exposing PIN values", () => {
  const patch = deliveryTracking.patchForTransition({
    action: "verify_receiver_pin",
    nextStatus: "delivered",
    riderId: "rider-1",
  });
  assert.equal(patch.status, "delivered");
  assert.equal(patch.deliveryPinVerified, true);
  assert.equal(patch.deliveryPinVerifiedBy, "rider-1");
  assert.equal(Object.prototype.hasOwnProperty.call(patch, "deliveryPin"), false);
  assert.equal(Object.prototype.hasOwnProperty.call(patch, "receiverPin"), false);
});

test("rider location patch preserves live GPS contract", () => {
  const patch = deliveryTracking.locationPatch({
    latitude: 51.5074,
    longitude: -0.1278,
  });
  assert.equal(patch.riderLocation.latitude, 51.5074);
  assert.equal(patch.riderLocation.longitude, -0.1278);
  assert.equal(patch.riderLocation.geopoint.latitude, 51.5074);
  assert.equal(patch.riderLocation.geopoint.longitude, -0.1278);
});
