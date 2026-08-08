"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  CENTRAL_LONDON_FEE_PENCE,
  ROAD_CHARGE_POLICY,
  ROAD_CHARGE_POLICY_VERSION,
  evaluateRoadCharges,
  stableLiabilityKey,
  dispatchRoadChargeScore,
  dailyRecoveryAllocation,
  normalizeVehicle,
  vehicleTariffClassification,
} = require("./road-charges-core");

const route = (overrides = {}) => ({
  authority: "authoritative_route",
  ...overrides,
});

test("unknown vehicle data never falls back to the cheapest tariff", () => {
  assert.equal(normalizeVehicle("hovercraft"), "unknown");
  assert.equal(vehicleTariffClassification({type: "hovercraft"}), "unknown");
  const result = evaluateRoadCharges({
    routeFacts: route({crossings: [{
      chargeId: "blackwall_silvertown",
      crossingId: "unknown-1",
      direction: "northbound",
      at: "2026-08-07T08:00:00Z",
    }]}),
    selectedVehicle: "hovercraft",
  });
  assert.equal(result.charges[0].status, "tariff_classification_unknown");
  assert.equal(result.authoritativePricingComplete, false);
  assert.equal(result.customerContributionPence, 0);
});

test("road-charge policy is versioned and uses integer pence", () => {
  assert.match(ROAD_CHARGE_POLICY_VERSION, /^2026-08-/);
  assert.equal(CENTRAL_LONDON_FEE_PENCE, 900);
  assert.equal(stableLiabilityKey({
    vehicleId: "vehicle-1",
    date: "2026-08-08",
    chargeId: "congestion_charge",
  }), "vehicle-1:2026-08-08:congestion_charge");
});

test("customer policy uses commercial fee wording without a discount or pass-through claim", () => {
  const presentation = ROAD_CHARGE_POLICY.commercialPolicy;
  assert.equal(presentation.customerLabel, "Central London fee");
  assert.equal(
      presentation.customerCopy,
      "Applies to eligible deliveries within the Congestion Charge Zone.",
  );
  assert.doesNotMatch(
      JSON.stringify(presentation),
      /50%|discount|save £9|covered by circum|tfl discount|£18\s*(?:->|→)\s*£9/i,
  );
});

test("Blackwall/Silvertown route toll is passed through once with no commission", () => {
  const result = evaluateRoadCharges({
    routeFacts: route({crossings: [{
      chargeId: "blackwall_silvertown",
      crossingId: "bw-1",
      direction: "northbound",
      at: "2026-08-07T08:00:00Z",
    }]}),
    selectedVehicle: "car",
  });
  assert.equal(result.charges.length, 1);
  assert.equal(result.customerContributionPence, 400);
  assert.equal(result.riderReimbursementPence, 400);
  assert.equal(result.circumContributionPence, 0);
});

test("Dartford motorcycle is zero-rate and duplicate crossing identity is ignored", () => {
  const result = evaluateRoadCharges({
    routeFacts: route({crossings: [
      {chargeId: "dartford_crossing", crossingId: "dart-1", at: "2026-08-07T12:00:00Z"},
      {chargeId: "dartford_crossing", crossingId: "dart-1", at: "2026-08-07T12:00:00Z"},
    ]}),
    selectedVehicle: "motorbike",
  });
  assert.equal(result.charges.length, 1);
  assert.equal(result.customerContributionPence, 0);
  assert.equal(result.riderReimbursementPence, 0);
});

test("Dartford uses independent Car and Van axle tariffs", () => {
  const crossing = [{chargeId: "dartford_crossing", crossingId: "dart-vehicle", at: "2026-08-07T12:00:00Z"}];
  const car = evaluateRoadCharges({routeFacts: route({crossings: crossing}), selectedVehicle: "car"});
  const van = evaluateRoadCharges({
    routeFacts: route({crossings: crossing}),
    selectedVehicle: "van",
    vehicleProfile: {axleCount: 2},
  });
  const unknownVan = evaluateRoadCharges({routeFacts: route({crossings: crossing}), selectedVehicle: "van"});
  assert.equal(car.customerContributionPence, 350);
  assert.equal(van.customerContributionPence, 420);
  assert.equal(unknownVan.authoritativePricingComplete, false);
});

test("Blackwall and Silvertown distinguish direction-sensitive peak pricing", () => {
  const evaluate = (direction, at) => evaluateRoadCharges({
    routeFacts: route({crossings: [{
      chargeId: "blackwall_silvertown",
      crossingId: `${direction}-${at}`,
      direction,
      at,
    }]}),
    selectedVehicle: "car",
  }).customerContributionPence;
  assert.equal(evaluate("northbound", "2026-08-07T08:00:00Z"), 400);
  assert.equal(evaluate("northbound", "2026-08-07T12:00:00Z"), 150);
  assert.equal(evaluate("southbound", "2026-08-07T17:00:00Z"), 400);
});

test("Motorbike, Car, and Van receive independent Central London treatment", () => {
  const congestionZone = {entered: true, at: "2026-08-07T10:00:00Z"};
  const motorbike = evaluateRoadCharges({routeFacts: route({congestionZone}), selectedVehicle: "motorbike"});
  const car = evaluateRoadCharges({routeFacts: route({congestionZone}), selectedVehicle: "car", vehicleId: "car-1"});
  const van = evaluateRoadCharges({routeFacts: route({congestionZone}), selectedVehicle: "van", vehicleId: "van-1"});
  assert.equal(motorbike.customerContributionPence, 0);
  assert.equal(car.customerContributionPence, 900);
  assert.equal(van.customerContributionPence, 900);
});

test("Central London fee funds the daily Rider recovery waterfall", () => {
  const result = evaluateRoadCharges({
    routeFacts: route({congestionZone: {
      entered: true,
      at: "2026-08-07T10:00:00Z",
    }}),
    selectedVehicle: "car",
    vehicleId: "vehicle-1",
  });
  assert.equal(result.charges[0].status, "new_daily_liability");
  assert.equal(result.customerContributionPence, 900);
  assert.equal(result.riderReimbursementPence, 900);
  assert.equal(result.circumRevenuePence, 0);
});

test("Recovered daily liability still charges the commercial fee without double recovery", () => {
  const key = stableLiabilityKey({
    vehicleId: "vehicle-1",
    date: "2026-08-07",
    chargeId: "congestion_charge",
  });
  const result = evaluateRoadCharges({
    routeFacts: route({congestionZone: {
      entered: true,
      at: "2026-08-07T10:00:00Z",
    }}),
    selectedVehicle: "car",
    vehicleId: "vehicle-1",
    liabilityState: {coveredKeys: [key]},
  });
  assert.equal(result.charges[0].status, "daily_liability_recovered");
  assert.equal(result.customerContributionPence, 900);
  assert.equal(result.riderReimbursementPence, 0);
  assert.equal(result.circumRevenuePence, 900);
});

test("one £18 vehicle-day liability caps recovery and yields the £882 hundred-job result", () => {
  let recoveredPence = 0;
  let customerFeesPence = 0;
  let riderRecoveryPence = 0;
  let circumRevenuePence = 0;
  const perJob = [];
  for (let job = 1; job <= 100; job += 1) {
    const allocation = dailyRecoveryAllocation({
      liabilityPence: 1800,
      customerFeePence: 900,
      recoveredPence,
    });
    customerFeesPence += allocation.customerFeePence;
    riderRecoveryPence += allocation.riderRecoveryPence;
    circumRevenuePence += allocation.circumRevenuePence;
    recoveredPence = allocation.recoveredAfterPence;
    perJob.push(allocation);
  }
  assert.equal(perJob[0].riderRecoveryPence, 900);
  assert.equal(perJob[1].riderRecoveryPence, 900);
  assert.equal(perJob[2].riderRecoveryPence, 0);
  assert.equal(customerFeesPence, 90000);
  assert.equal(riderRecoveryPence, 1800);
  assert.equal(circumRevenuePence, 88200);
});

test("ULEZ and LEZ are compliance records, not Sender charges", () => {
  const result = evaluateRoadCharges({
    routeFacts: route({
      ulez: {applicable: true, compliant: false},
      lez: {applicable: true, compliant: true},
    }),
    selectedVehicle: "van",
  });
  assert.equal(result.charges.length, 2);
  assert.equal(result.customerContributionPence, 0);
  assert.equal(result.riderReimbursementPence, 0);
  assert.equal(result.charges[0].status, "compliance_audit_required");
});

test("Missing or untrusted route facts fail closed without inventing a charge", () => {
  const result = evaluateRoadCharges({
    routeFacts: {authority: "client"},
    selectedVehicle: "car",
  });
  assert.equal(result.routeKnown, false);
  assert.equal(result.customerContributionPence, 0);
  assert.equal(result.reason, "authoritative_route_facts_unavailable");
});

test("dispatch score exposes incremental reimbursement without filtering eligible Riders", () => {
  const score = dispatchRoadChargeScore({
    routeFacts: route({congestionZone: {entered: true, at: "2026-08-07T10:00:00Z"}}),
    rider: {id: "rider-1", vehicleType: "car"},
    request: {},
  });
  assert.equal(score.incrementalPence, 900);
});
