"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const tracking = require("./sender-tracking-state-core");

test("all 13 Sender tracking states are represented", () => {
  assert.deepEqual(Object.values(tracking.SENDER_TRACKING_STATES), [
    "no_active_delivery",
    "loading",
    "finding_rider",
    "rider_assigned",
    "rider_en_route_to_pickup",
    "rider_arrived_at_pickup",
    "pickup_complete",
    "in_transit",
    "rider_arriving_at_dropoff",
    "delivered",
    "cancelled",
    "issue",
    "error",
  ]);
});

test("backend statuses map to Sender tracking states", () => {
  const cases = {
    requested: "finding_rider",
    accepted: "rider_assigned",
    navigating_to_pickup: "rider_en_route_to_pickup",
    arrived_at_pickup: "rider_arrived_at_pickup",
    collected: "pickup_complete",
    navigating_to_dropoff: "in_transit",
    arrived_at_dropoff: "rider_arriving_at_dropoff",
    delivered: "delivered",
    cancelled: "cancelled",
    issue_reported: "issue",
    error: "error",
    "out-for-delivery": "in_transit",
  };
  for (const [status, expected] of Object.entries(cases)) {
    assert.equal(tracking.senderTrackingStateForBackendStatus(status), expected);
  }
});

test("delivery status transition rules block unsafe jumps", () => {
  assert.equal(tracking.canTransitionDeliveryStatus("requested", "accepted"), true);
  assert.equal(tracking.canTransitionDeliveryStatus("accepted", "navigating_to_pickup"), true);
  assert.equal(tracking.canTransitionDeliveryStatus("navigating_to_pickup", "arrived_at_pickup"), true);
  assert.equal(tracking.canTransitionDeliveryStatus("arrived_at_pickup", "pickup_verification"), true);
  assert.equal(tracking.canTransitionDeliveryStatus("pickup_verified", "collected"), true);
  assert.equal(tracking.canTransitionDeliveryStatus("collected", "navigating_to_dropoff"), true);
  assert.equal(tracking.canTransitionDeliveryStatus("arrived_at_dropoff", "pin_required"), true);
  assert.equal(tracking.canTransitionDeliveryStatus("pin_required", "delivered"), true);
  assert.equal(tracking.canTransitionDeliveryStatus("delivered", "accepted"), false);
  assert.equal(tracking.canTransitionDeliveryStatus("cancelled", "accepted"), false);
});
