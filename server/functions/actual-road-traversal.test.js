"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {appendPoint, evaluateActualTraversal} = require("./actual-road-traversal");

test("server observed movement is bounded and ignores sub-25m duplicates", () => {
  let points = [];
  points = appendPoint(points, {latitude: 51.50, longitude: -0.10, at: "2026-08-09T12:00:00Z"});
  points = appendPoint(points, {latitude: 51.50001, longitude: -0.10001, at: "2026-08-09T12:00:10Z"});
  points = appendPoint(points, {latitude: 51.51, longitude: -0.08, at: "2026-08-09T12:01:00Z"});
  assert.equal(points.length, 2);
});

test("insufficient movement evidence stays unresolved", () => {
  const result = evaluateActualTraversal({points: [{latitude: 51.5, longitude: -0.1}]});
  assert.equal(result.status, "UNRESOLVED");
  assert.equal(result.evidenceCompleteness, "UNRESOLVED");
});

test("complete actual movement produces server-owned route facts", () => {
  const result = evaluateActualTraversal({
    deliveryId: "d1",
    riderId: "r1",
    assignedVehicle: {id: "car-1", type: "Car", roadChargeFactsVerificationStatus: "verified", cczAuthorityStatus: "CHARGEABLE"},
    points: [
      {latitude: 51.49, longitude: -0.19, at: "2026-08-09T12:00:00Z"},
      {latitude: 51.50, longitude: -0.10, at: "2026-08-09T12:10:00Z"},
    ],
  });
  assert.equal(result.evidenceCompleteness, "COMPLETE");
  assert.equal(result.routeFacts.authority, "authoritative_route");
  assert.ok(["INCURRED", "NOT_INCURRED"].includes(result.status));
  assert.equal(result.deliveryId, "d1");
});

test("malformed or out-of-order movement cannot become refund evidence", () => {
  const malformed = evaluateActualTraversal({points: [
    {latitude: 51.49, longitude: -0.19, at: "not-a-date"},
    {latitude: 51.50, longitude: -0.10, at: "2026-08-09T12:10:00Z"},
  ]});
  const outOfOrder = evaluateActualTraversal({points: [
    {latitude: 51.49, longitude: -0.19, at: "2026-08-09T12:10:00Z"},
    {latitude: 51.50, longitude: -0.10, at: "2026-08-09T12:09:00Z"},
  ]});
  assert.equal(malformed.evidenceCompleteness, "UNRESOLVED");
  assert.equal(outOfOrder.evidenceCompleteness, "UNRESOLVED");
});

test("impossible movement segment cannot become refund evidence", () => {
  const result = evaluateActualTraversal({points: [
    {latitude: 51.49, longitude: -0.19, at: "2026-08-09T12:00:00Z"},
    {latitude: 51.50, longitude: -0.10, at: "2026-08-09T12:00:01Z"},
  ]});
  assert.equal(result.evidenceCompleteness, "UNRESOLVED");
});
