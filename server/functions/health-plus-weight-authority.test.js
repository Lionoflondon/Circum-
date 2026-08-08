"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {
  validateMedicationWeightKg,
  calculateAuthoritativeHealthPlusPricing,
  MAX_VALIDATED_MEDICATION_WEIGHT_KG,
} = require("./health-plus-core");

test("Health+ validates finite positive medication weight", () => {
  assert.equal(validateMedicationWeightKg(0.25), 0.25);
  assert.equal(validateMedicationWeightKg(MAX_VALIDATED_MEDICATION_WEIGHT_KG), MAX_VALIDATED_MEDICATION_WEIGHT_KG);
  for (const value of [0, -1, "NaN", "Infinity", Infinity, NaN, MAX_VALIDATED_MEDICATION_WEIGHT_KG + 1]) {
    assert.throws(() => validateMedicationWeightKg(value), /weight/);
  }
});

test("Health+ freezes validated weight into authoritative pricing", () => {
  const quote = calculateAuthoritativeHealthPlusPricing({
    distanceMiles: 4,
    medicationWeightKg: 8,
    frequency: "one_off",
  });
  assert.equal(quote.medicationWeightKg, 8);
  assert.equal(quote.weightCategory, "Medium Parcel");
});
