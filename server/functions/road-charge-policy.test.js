"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {evaluateRoadChargePolicy} = require("./road-charge-policy");

test("road-charge policy fails closed when authoritative geography is unavailable", () => {
  const result = evaluateRoadChargePolicy({
    routeFacts: {version: "circum_routes_v1"},
    vehicle: "car",
    product: "standard",
  });
  assert.equal(result.customerAmount, 0);
  assert.equal(result.approvedTariffApplied, false);
  assert.equal(result.reason, "authoritative_route_facts_unavailable");
});

test("road-charge policy applies the recovered Central London tariff", () => {
  const result = evaluateRoadChargePolicy({
    routeFacts: {
      authority: "authoritative_route",
      known: true,
      congestionZone: {entered: true, at: "2026-08-07T10:00:00Z"},
    },
    vehicle: "car",
    product: "standard",
    vehicleProfile: {
      roadChargeFactsVerificationStatus: "verified",
      cczAuthorityStatus: "CHARGEABLE",
    },
  });
  assert.equal(result.customerAmount, 9);
  assert.equal(result.lineItems[0].chargeType, "daily_zone_charge");
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
