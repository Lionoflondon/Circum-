"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {adjustmentFor, dispatchIntelligenceSignal, flagPolicy, gpsRiskDecision, riskLevel, trend} = require("./marketplace-intelligence");

const delivery = {assignedRiderId: "rider-1"};

test("completed delivery improves reliability without changing Trust Points or Rank", () => {
  const result = adjustmentFor({eventId: "event-1", deliveryId: "delivery-1", eventType: "Completed"}, delivery);
  assert.deepEqual(result, {points: 2, reason: "Successful delivery completed", counter: "completedDeliveries", riderId: "rider-1", deliveryId: "delivery-1", eventId: "event-1"});
  assert.equal("trustPoints" in result, false);
  assert.equal("rank" in result, false);
});

test("negative operational outcomes are explainable", () => {
  assert.equal(adjustmentFor({eventType: "Cancelled", actorType: "rider"}, delivery).points, -6);
  assert.equal(adjustmentFor({eventType: "Cancelled", actorType: "customer"}, delivery), null);
  assert.equal(adjustmentFor({eventType: "DisputeCreated"}, delivery), null);
  assert.equal(adjustmentFor({eventType: "ConfirmedDeliveryDispute"}, delivery).points, -4);
  assert.equal(adjustmentFor({eventType: "VerificationFailed"}, delivery).points, -4);
});

test("customer ratings use bounded semantic adjustments", () => {
  assert.equal(adjustmentFor({eventType: "CustomerRatingReceived", metadata: {rating: 5}}, delivery).points, 1);
  assert.equal(adjustmentFor({eventType: "CustomerRatingReceived", metadata: {rating: 2}}, delivery).points, -2);
  assert.equal(adjustmentFor({eventType: "CustomerRatingReceived", metadata: {rating: 3}}, delivery), null);
});

test("duplicate-safe source identity is carried into an adjustment", () => {
  const one = adjustmentFor({eventId: "same-event", deliveryId: "delivery-1", eventType: "EvidenceUploaded"}, delivery);
  const two = adjustmentFor({eventId: "same-event", deliveryId: "delivery-1", eventType: "EvidenceUploaded"}, delivery);
  assert.deepEqual(one, two);
  assert.equal(one.eventId, "same-event");
});

test("score trend and risk levels remain bounded and explainable", () => {
  assert.equal(trend(80, 82), "IMPROVING");
  assert.equal(trend(80, 77), "DECLINING");
  assert.equal(riskLevel(80), "GREEN");
  assert.equal(riskLevel(65), "AMBER");
  assert.equal(riskLevel(90, 1), "RED");
});

test("dispatch intelligence is advisory and cannot decide eligibility", () => {
  assert.deepEqual(dispatchIntelligenceSignal({reliabilityScore: 92, reliabilityRiskLevel: "GREEN"}), {score: 92, riskLevel: "GREEN", priorityBand: "PREFERRED", advisoryOnly: true});
  assert.equal("eligible" in dispatchIntelligenceSignal({reliabilityScore: 10}), false);
});

test("valid movement creates no false GPS flag", () => {
  const result = gpsRiskDecision({latitude: 51.5, longitude: -0.1, updatedAt: "2026-08-09T12:00:00Z"}, {latitude: 51.501, longitude: -0.1, updatedAt: "2026-08-09T12:01:00Z"});
  assert.equal(result.flag, false);
});

test("teleport and impossible speed create review evidence", () => {
  const result = gpsRiskDecision({latitude: 51.5, longitude: -0.1, updatedAt: "2026-08-09T12:00:00Z"}, {latitude: 52.0, longitude: -0.1, updatedAt: "2026-08-09T12:01:00Z"});
  assert.equal(result.flag, true);
  assert.equal(result.signal, "teleporting_coordinates");
  assert.equal(result.severity, "RED");
  assert.ok(result.evidence.distanceMeters > 10000);
});

test("risk flags are review signals and never automatic punishment", () => {
  const policy = flagPolicy({eventType: "GPSRiskFlag", metadata: {signal: "impossible_speed", severity: "RED"}});
  assert.deepEqual(policy, {flagType: "impossible_speed", severity: "RED"});
  assert.equal("suspend" in policy, false);
  assert.equal("eligible" in policy, false);
});
