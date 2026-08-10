/* eslint-disable max-len */
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {additionalAmount, buildAdjustment, isMaterialDiscrepancy} = require("./delivery-adjustment-core");

test("weight discrepancy requires at least a 20 percent increase", () => {
  assert.equal(isMaterialDiscrepancy({reason: "weight_exceeded", originalWeightKg: 10, observedWeightKg: 11.9}), false);
  assert.equal(isMaterialDiscrepancy({reason: "weight_exceeded", originalWeightKg: 10, observedWeightKg: 12}), true);
});

test("undeclared items and vehicle suitability changes are material", () => {
  assert.equal(isMaterialDiscrepancy({reason: "additional_undeclared_items"}), true);
  assert.equal(isMaterialDiscrepancy({reason: "weight_exceeded", originalWeightKg: 10, observedWeightKg: 10, vehicleSuitabilityChanged: true}), true);
});

test("additional amount cannot be negative", () => {
  assert.equal(additionalAmount(20, 27.456), 7.46);
  assert.equal(additionalAmount(20, 18), 0);
});

test("new adjustments remain under Admin review before sender payment", () => {
  const adjustment = buildAdjustment({
    bookingId: "booking-1",
    bookingRequestId: "request-1",
    senderId: "sender-1",
    riderId: "rider-1",
    originalQuote: 10,
    revisedQuote: 14,
    riderReason: "weight_exceeded",
  });
  assert.equal(adjustment.status, "awaiting_admin_review");
  assert.equal(adjustment.senderDecision, "pending");
  assert.equal(adjustment.additionalAmount, 4);
});

test("delivery adjustment callable requires Admin review before sender payment", () => {
  const source = fs.readFileSync(path.join(__dirname, "delivery-adjustments.js"), "utf8");
  assert.match(source, /exports\.reviewDeliveryAdjustment/);
  assert.match(source, /status: "awaiting_admin_review"/);
  assert.match(source, /status: "awaiting_adjustment_review"/);
  assert.match(source, /nextStatus = needsPayment \? "awaiting_sender_payment" : !vehicleCompatible \? "vehicle_reassignment_required"/);
  assert.match(source, /adminDecision !== "approve"/);
  assert.match(source, /request_more_evidence/);
  assert.match(source, /repriceWeightFromQuote/);
  assert.match(source, /paidWeightSnapshot\(booking\)/);
  assert.match(source, /verifyReferences/);
  assert.match(source, /WeightDiscrepancySubmitted/);
  assert.doesNotMatch(source, /booking\.finalWeightUsed \|\| booking\.finalChargeableWeight/);
  assert.doesNotMatch(source, /recommendation && recalculated\.recommendation\.estimatedPrice/);
});

test("Admin review UX exposes production review controls and audit fields", () => {
  const adminSource = fs.readFileSync(
      path.join(__dirname, "..", "..", "lib", "app", "admin", "admin_root.dart"),
      "utf8",
  );
  for (const marker of [
    "ChoiceChip",
    "Evidence preview",
    "Decision notes",
    "adminReviewedBy",
    "adminReviewedAt",
    "Sender statement",
    "Rider statement",
    "reviewDeliveryAdjustment",
    "request_more_evidence",
  ]) {
    assert.match(adminSource, new RegExp(marker));
  }
});
