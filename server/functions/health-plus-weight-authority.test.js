"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {
  validateMedicationWeightKg,
  calculateAuthoritativeHealthPlusPricing,
  MAX_VALIDATED_MEDICATION_WEIGHT_KG,
} = require("./health-plus-core");

test("Health+ accepts zero or known medication weight but rejects malformed values", () => {
  assert.equal(validateMedicationWeightKg(0), 0);
  assert.equal(validateMedicationWeightKg(0.25), 0.25);
  assert.equal(validateMedicationWeightKg(MAX_VALIDATED_MEDICATION_WEIGHT_KG), MAX_VALIDATED_MEDICATION_WEIGHT_KG);
  for (const value of [-1, "NaN", "Infinity", Infinity, NaN, MAX_VALIDATED_MEDICATION_WEIGHT_KG + 1]) {
    assert.throws(() => validateMedicationWeightKg(value), /weight/);
  }
});

test("Health+ records medication weight but excludes it from pricing economics", () => {
  const quote = calculateAuthoritativeHealthPlusPricing({
    distanceMiles: 4,
    medicationWeightKg: 8,
    frequency: "one_off",
  });
  assert.equal(quote.medicationWeightKg, 8);
  assert.equal(quote.weightCategory, "Small Parcel");
  assert.equal(quote.weightContributionPence, 0);
  assert.equal(quote.weightSurchargePence, 0);
});
