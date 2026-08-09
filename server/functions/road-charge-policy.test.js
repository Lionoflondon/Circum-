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

test("Blackwall/Silvertown charges respect the 06:00-22:00 operating window", () => {
  const routeFacts = (at) => ({
    authority: "authoritative_route",
    known: true,
    crossings: [{
      chargeId: "blackwall_silvertown",
      crossingId: "blackwall_silvertown",
      direction: "northbound",
      at,
    }],
  });
  const vehicleProfile = {
    roadChargeFactsVerificationStatus: "verified",
    tunnelTariffClass: "small_van",
  };
  const before = evaluateRoadChargePolicy({
    routeFacts: routeFacts("2026-08-07T04:59:00Z"),
    vehicle: "car",
    product: "standard",
  });
  const open = evaluateRoadChargePolicy({
    routeFacts: routeFacts("2026-08-07T05:00:00Z"),
    vehicle: "car",
    product: "standard",
  });
  const after = evaluateRoadChargePolicy({
    routeFacts: routeFacts("2026-08-07T21:00:00Z"),
    vehicle: "car",
    product: "standard",
  });
  assert.equal(before.customerAmount, 0);
  assert.equal(open.customerAmount, 4);
  assert.equal(after.customerAmount, 0);
  const van = evaluateRoadChargePolicy({
    routeFacts: routeFacts("2026-08-07T05:00:00Z"),
    vehicle: "van",
    product: "standard",
    vehicleProfile,
  });
  assert.equal(van.customerAmount, 4);
});

test("Dartford charges respect the independent daily 06:00-22:00 window", () => {
  const routeFacts = (at) => ({
    authority: "authoritative_route",
    known: true,
    crossings: [{
      chargeId: "dartford_crossing",
      crossingId: "dartford_crossing",
      direction: "northbound",
      at,
    }],
  });
  const quote = (at) => evaluateRoadChargePolicy({
    routeFacts: routeFacts(at),
    vehicle: "car",
    product: "standard",
  });
  assert.equal(quote("2026-08-07T04:59:00Z").customerAmount, 0);
  assert.equal(quote("2026-08-07T05:00:00Z").customerAmount, 3.5);
  assert.equal(quote("2026-08-07T20:59:00Z").customerAmount, 3.5);
  assert.equal(quote("2026-08-07T21:00:00Z").customerAmount, 0);
  assert.equal(quote("2026-08-07T21:01:00Z").customerAmount, 0);
  assert.equal(evaluateRoadChargePolicy({
    routeFacts: {authority: "authoritative_route", known: true, crossings: []},
    vehicle: "car",
    product: "standard",
  }).customerAmount, 0);
});
