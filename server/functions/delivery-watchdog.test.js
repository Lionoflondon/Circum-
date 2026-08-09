"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {distanceMeters, evaluation, incidentId, locationOf} = require("./delivery-watchdog");
const {operationalProjection, watchdogCondition} = require("./movement-timeline");

test("accepted delivery is projected for bounded no-movement evaluation", () => {
  const projection = operationalProjection("delivery-1", {status: "requested"}, {status: "accepted", riderId: "rider-1"});
  assert.equal(projection.active, true);
  assert.equal(projection.incidentType, "accepted_no_movement");
  assert.ok(projection.nextCheckAt);
});

test("watchdog identifies every requested lifecycle risk", () => {
  assert.equal(watchdogCondition({status: "arrived_at_pickup"}), "arrived_not_collected");
  assert.equal(watchdogCondition({status: "collected"}), "collected_no_movement");
  assert.equal(watchdogCondition({status: "arrived_at_dropoff"}), "dropoff_completion_delay");
  assert.equal(watchdogCondition({status: "requested", paymentStatus: "succeeded"}), "payment_dispatch_failure");
});

test("meaningful movement clears accepted and collected movement risk", () => {
  const projection = {incidentType: "accepted_no_movement", baselineLocation: {latitude: 51.5, longitude: -0.1}};
  const result = evaluation(projection, {riderLiveLocation: {latitude: 51.502, longitude: -0.1}});
  assert.equal(result.action, "movement");
  assert.ok(result.movementMeters >= 100);
});

test("stationary Rider creates one deterministic logical incident", () => {
  const projection = {incidentType: "collected_no_movement", baselineLocation: {latitude: 51.5, longitude: -0.1}};
  assert.equal(evaluation(projection, {riderLiveLocation: {latitude: 51.50001, longitude: -0.1}}).action, "incident");
  assert.equal(incidentId("delivery-1", "collected_no_movement"), incidentId("delivery-1", "collected_no_movement"));
});

test("location parser accepts canonical maps and rejects invalid coordinates", () => {
  assert.deepEqual(locationOf({riderLiveLocation: {latitude: 51.5, longitude: -0.1}}), {latitude: 51.5, longitude: -0.1});
  assert.equal(locationOf({latitude: 999, longitude: -0.1}), null);
  assert.ok(distanceMeters({latitude: 51.5, longitude: -0.1}, {latitude: 51.501, longitude: -0.1}) > 100);
});
