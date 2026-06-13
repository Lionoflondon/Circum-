/* eslint-disable max-len */
const test = require("node:test");
const assert = require("node:assert/strict");
const {additionalAmount, isMaterialDiscrepancy} = require("./delivery-adjustment-core");

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
