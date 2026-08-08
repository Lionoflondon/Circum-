"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {evaluateRoadChargePolicy} = require("./road-charge-policy");

test("road-charge policy fails closed when no approved tariff exists", () => {
  const result = evaluateRoadChargePolicy({
    routeFacts: {version: "circum_routes_v1", centralLondonEntered: true},
    vehicle: "car",
    product: "standard",
  });
  assert.equal(result.customerAmount, 0);
  assert.equal(result.approvedTariffApplied, false);
  assert.equal(result.reason, "no_approved_tariff");
});

test("road-charge policy applies only an explicit approved tariff", () => {
  const result = evaluateRoadChargePolicy({
    routeFacts: {version: "circum_routes_v1", centralLondonEntered: true},
    vehicle: "van",
    product: "business",
    approvedPolicy: {centralLondon: {van: {approved: true, amount: 9}}},
  });
  assert.equal(result.customerAmount, 9);
  assert.equal(result.lineItems[0].chargeType, "daily_liability");
});

test("provider toll metadata cannot create a customer charge", () => {
  const result = evaluateRoadChargePolicy({
    routeFacts: {
      version: "circum_routes_v1",
      centralLondonEntered: false,
      tollInfo: {estimatedPrice: [{currencyCode: "GBP", units: "100"}]},
    },
    vehicle: "car",
  });
  assert.equal(result.customerAmount, 0);
  assert.equal(result.lineItems.length, 0);
});
