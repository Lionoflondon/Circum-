/* eslint-disable max-len */
const test = require("node:test");
const assert = require("node:assert/strict");
const {
  buildLearningRecord,
  buildProductionDecision,
  customerConfidenceBand,
  customerReasons,
  learningRecordId,
  lowConfidenceSuggestions,
  vehicleFromIris,
} = require("./iris-production-core");
const {classifyIris} = require("./iris-core");

test("customer confidence maps to simple customer-facing bands", () => {
  assert.equal(customerConfidenceBand(91), "High");
  assert.equal(customerConfidenceBand(80), "High");
  assert.equal(customerConfidenceBand(79), "Medium");
  assert.equal(customerConfidenceBand(50), "Medium");
  assert.equal(customerConfidenceBand(49), "Low");
});

test("customer reasons are natural language and capped at three", () => {
  const reasons = customerReasons([
    "repository_exact_match",
    "parcel_photo_supplied",
    "dimensions_supplied",
    "internal_probability_score",
  ]);
  assert.deepEqual(reasons, [
    "Similar verified deliveries",
    "Parcel photos",
    "Parcel dimensions",
  ]);
  assert.equal(reasons.length, 3);
  assert.equal(reasons.some((reason) => reason.toLowerCase().includes("probability")), false);
});

test("production decision keeps numerical confidence internally but exposes band for customers", () => {
  const iris = classifyIris({description: "iPhone"});
  const decision = buildProductionDecision({
    decisionId: "decision_1",
    deliveryId: "delivery_1",
    userId: "user_1",
    input: {description: "iPhone", photoUrl: "photo.jpg"},
    iris,
    createdAt: "2026-07-04T10:00:00.000Z",
  });
  assert.equal(decision.decisionId, "decision_1");
  assert.equal(decision.deliveryId, "delivery_1");
  assert.equal(typeof decision.internalConfidence, "number");
  assert.equal(decision.customerConfidence, "High");
  assert.equal(decision.reasons.length <= 3, true);
  assert.equal(decision.recommendedVehicle, "car");
  assert.equal(decision.finalVerifiedWeight, null);
  assert.equal(decision.version, "ipil-v1");
});

test("low confidence offers helpful next steps without blocking booking", () => {
  assert.deepEqual(lowConfidenceSuggestions(20), [
    "Take another photo",
    "Add dimensions",
    "Describe parcel",
    "Rider will verify at pickup",
  ]);
  assert.deepEqual(lowConfidenceSuggestions(80), []);
});

test("vehicle intelligence chooses bike, car, and van from the same IRIS decision", () => {
  assert.equal(vehicleFromIris(classifyIris({description: "documents"})), "bike");
  assert.equal(vehicleFromIris(classifyIris({description: "laptop"})), "car");
  assert.equal(vehicleFromIris(classifyIris({description: "sofa"})), "van");
});

test("learning records are stable and deduplicated by decision outcome", () => {
  const learning = buildLearningRecord({
    decisionId: "decision_2",
    deliveryId: "delivery_2",
    itemDescription: "boxed espresso machine",
    finalVerifiedWeight: 8.2,
    riderVerified: true,
    adminAdjusted: true,
    finalOutcome: {finalCategory: "Electronics", finalWeightBand: "Medium Parcel"},
    createdAt: "2026-07-04T11:00:00.000Z",
  });
  assert.equal(learning.finalVerifiedWeight, 8.2);
  assert.equal(learning.riderVerified, true);
  assert.equal(learning.adminAdjusted, true);
  assert.equal(learning.learningApplied, false);
  assert.equal(learningRecordId(learning), learningRecordId({...learning, createdAt: "later"}));
});
