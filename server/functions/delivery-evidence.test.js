/* eslint-disable max-len */
"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const evidence = require("./delivery-evidence")._private;

test("delivery evidence storage paths are backend-derived", () => {
  assert.equal(
      evidence.evidenceStoragePath({
        deliveryId: "delivery-1",
        riderId: "rider-1",
        evidenceId: "evidence-1",
        contentType: "image/png",
      }),
      "deliveryEvidence/delivery-1/rider-1/evidence-1.png",
  );
});

test("delivery evidence type and stage normalize to canonical values", () => {
  assert.equal(evidence.normalizeEvidenceType("proof of delivery"), "completion_proof");
  assert.equal(evidence.normalizeEvidenceType("collection"), "pickup_proof");
  assert.equal(evidence.normalizeLifecycleStage("", "completion_proof"), "completion");
  assert.equal(evidence.normalizeLifecycleStage("", "pickup_proof"), "pickup");
});

test("completion proof visibility is customer safe except Health+", () => {
  assert.equal(evidence.visibilityFor("completion_proof", {}), "rider_sender_admin");
  assert.equal(evidence.visibilityFor("completion_proof", {isHealthPlus: true}), "rider_admin");
  assert.equal(evidence.visibilityFor("discrepancy", {}), "rider_admin");
});
