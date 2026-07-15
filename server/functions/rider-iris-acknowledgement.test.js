/* eslint-disable max-len */
const assert = require("node:assert/strict");
const test = require("node:test");
const fs = require("node:fs");
const path = require("node:path");
const core = require("./rider-iris-acknowledgement-core");

test("IRIS acknowledgement is permitted only during pickup verification", () => {
  assert.equal(core.canConfirmAtPickup({deliveryStage: "accepted"}), false);
  assert.equal(core.canConfirmAtPickup({deliveryStage: "arrived_at_pickup"}), true);
  assert.equal(core.canConfirmAtPickup({deliveryStage: "pickup_verification"}), true);
  assert.equal(core.canConfirmAtPickup({deliveryStage: "waiting", waiting: {phase: "pickup"}}), true);
  assert.equal(core.canConfirmAtPickup({deliveryStage: "waiting", waiting: {phase: "dropoff"}}), false);
  assert.equal(core.canConfirmAtPickup({deliveryStage: "collected"}), false);
  assert.equal(core.canConfirmAtPickup({deliveryStage: "delivered"}), false);
});

test("acknowledgement snapshots existing backend IRIS evidence", () => {
  const acknowledgement = core.buildAcknowledgement({
    deliveryId: "delivery-1",
    riderId: "rider-1",
    delivery: {
      irisRecommendation: {detectedItem: "Parcel", version: "iris-v4"},
      parcelPhotoUrl: "https://storage/item.jpg",
    },
  });
  assert.deepEqual(acknowledgement, {
    deliveryId: "delivery-1",
    riderId: "rider-1",
    status: "confirmed",
    acknowledgementStatus: "confirmed",
    irisAssessment: {detectedItem: "Parcel", version: "iris-v4"},
    irisVersion: "iris-v4",
    itemSnapshotReference: "https://storage/item.jpg",
    source: "rider_pickup_iris_confirmation",
  });
});

test("callable is idempotent and cannot mutate lifecycle fields", () => {
  const source = fs.readFileSync(path.join(__dirname, "rider-iris-acknowledgement.js"), "utf8");
  assert.match(source, /riderIrisAcknowledgements/);
  assert.match(source, /existingSnapshot\.exists/);
  assert.match(source, /duplicate: true/);
  assert.match(source, /adminAuditLogs/);
  assert.match(source, /auditHistory: FieldValue\.arrayUnion/);
  assert.doesNotMatch(source, /deliveryStatus\s*:/);
  assert.doesNotMatch(source, /deliveryStage\s*:/);
  assert.doesNotMatch(source, /\bstatus\s*:\s*["'](?:accepted|collected|delivered)/);
});
