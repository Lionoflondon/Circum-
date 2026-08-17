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

test("unknown backend statuses fail closed instead of inventing delivery progress", () => {
  assert.equal(
      tracking.senderTrackingStateForBackendStatus("unknown_future_status"),
      tracking.SENDER_TRACKING_STATES.ISSUE,
  );
  assert.equal(
      tracking.senderTrackingStateForBackendStatus(""),
      tracking.SENDER_TRACKING_STATES.NO_ACTIVE_DELIVERY,
  );
});

test("delivery status transition rules block unsafe jumps", () => {
  assert.equal(tracking.canTransitionDeliveryStatus("requested", "accepted"), true);
  assert.equal(tracking.canTransitionDeliveryStatus("accepted", "navigating_to_pickup"), true);
  assert.equal(tracking.canTransitionDeliveryStatus("navigating_to_pickup", "arrived_at_pickup"), true);
  assert.equal(tracking.canTransitionDeliveryStatus("arrived_at_pickup", "pickup_verification"), true);
  assert.equal(tracking.canTransitionDeliveryStatus("arrived_at_pickup", "pickup_verified"), true);
  assert.equal(tracking.canTransitionDeliveryStatus("pickup_verified", "collected"), true);
  assert.equal(tracking.canTransitionDeliveryStatus("pickup_verified", "navigating_to_dropoff"), true);
  assert.equal(tracking.canTransitionDeliveryStatus("collected", "navigating_to_dropoff"), true);
  assert.equal(tracking.canTransitionDeliveryStatus("picked_up", "navigating_to_dropoff"), true);
  assert.equal(tracking.canTransitionDeliveryStatus("in_transit", "arrived_at_dropoff"), true);
  assert.equal(tracking.canTransitionDeliveryStatus("out_for_delivery", "arrived_at_dropoff"), true);
  assert.equal(tracking.canTransitionDeliveryStatus("arrived_at_dropoff", "pin_required"), true);
  assert.equal(tracking.canTransitionDeliveryStatus("pin_required", "delivered"), true);
  assert.equal(tracking.canTransitionDeliveryStatus("delivered", "accepted"), false);
  assert.equal(tracking.canTransitionDeliveryStatus("cancelled", "accepted"), false);
});

test("rider actions resolve to canonical backend statuses", () => {
  assert.equal(tracking.statusForRiderAction("start_heading_to_pickup"), "navigating_to_pickup");
  assert.equal(tracking.statusForRiderAction("arrived_at_pickup"), "arrived_at_pickup");
  assert.equal(tracking.statusForRiderAction("verify_collection_pin"), "pickup_verified");
  assert.equal(tracking.statusForRiderAction("confirm_collected"), "collected");
  assert.equal(tracking.statusForRiderAction("start_delivery"), "navigating_to_dropoff");
  assert.equal(tracking.statusForRiderAction("near_dropoff"), "arrived_at_dropoff");
  assert.equal(tracking.statusForRiderAction("verify_receiver_pin"), "delivered");
  assert.equal(tracking.statusForRiderAction("report_issue"), "issue_reported");
  assert.equal(tracking.statusForRiderAction("unknown"), "");
});

test("standard (non-Vanguard) delivery: confirm_collected is reachable from arrived_at_pickup and waiting", () => {
  const collectedStatus = tracking.statusForRiderAction("confirm_collected");
  assert.equal(collectedStatus, "collected");
  assert.equal(
      tracking.canTransitionDeliveryStatus("arrived_at_pickup", collectedStatus),
      true,
  );
  assert.equal(
      tracking.canTransitionDeliveryStatus("waiting", collectedStatus),
      true,
  );
});
