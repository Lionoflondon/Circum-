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
  vanTunnelTariffAuthority,
  cczVehicleAuthority,
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

test("Dartford quotes every Van at the large tariff and settles actual axle liability", () => {
  const crossing = [{chargeId: "dartford_crossing", crossingId: "dart-vehicle", at: "2026-08-07T12:00:00Z"}];
  const car = evaluateRoadCharges({routeFacts: route({crossings: crossing}), selectedVehicle: "car"});
  const vanProfile = {axleCount: 2, roadChargeFactsVerificationStatus: "verified"};
  const van = evaluateRoadCharges({
    routeFacts: route({crossings: crossing}),
    selectedVehicle: "van",
    vehicleProfile: vanProfile,
  });
  const vanSettlement = evaluateRoadCharges({
    routeFacts: route({crossings: crossing}),
    selectedVehicle: "van",
    vehicleProfile: vanProfile,
    pricingContext: "settlement",
  });
  const unknownVan = evaluateRoadCharges({routeFacts: route({crossings: crossing}), selectedVehicle: "van"});
  assert.equal(car.customerContributionPence, 350);
  assert.equal(van.customerContributionPence, 840);
  assert.equal(van.charges[0].actualClassification, "VAN_2_AXLE");
  assert.equal(van.charges[0].pricingTariffApplied, "VAN_MULTI_AXLE_COMMERCIAL");
  assert.equal(vanSettlement.riderReimbursementPence, 420);
  assert.equal(unknownVan.customerContributionPence, 840);
  assert.equal(unknownVan.charges[0].pricingTariffApplied, "VAN_MULTI_AXLE_COMMERCIAL");
  assert.equal(unknownVan.charges[0].actualClassification, "UNKNOWN");
});

test("Van tunnel quotes always use the large-Van commercial tariff", () => {
  const crossing = [{
    chargeId: "blackwall_silvertown",
    crossingId: "van-tunnel",
    direction: "northbound",
    at: "2026-08-07T08:00:00Z",
  }];
  const evaluate = (vehicleProfile = {}, pricingContext = "quote") => evaluateRoadCharges({
    routeFacts: route({crossings: crossing}),
    selectedVehicle: "van",
    vehicleProfile,
    pricingContext,
  });
  const verifiedSmall = evaluate({
    tunnelTariffClass: "small_van",
    referenceMassKg: 1100,
    roadChargeFactsVerificationStatus: "verified",
  });
  const verifiedLarge = evaluate({
    tunnelTariffClass: "large_van",
    referenceMassKg: 1800,
    roadChargeFactsVerificationStatus: "verified",
  });
  const unknown = evaluate();
  const forgedSmall = evaluate({tunnelTariffClass: "small_van", referenceMassKg: 1000});
  const conflicting = evaluate({
    tunnelTariffClass: "small_van",
    referenceMassKg: 1800,
    roadChargeFactsVerificationStatus: "verified",
  });
  assert.equal(verifiedSmall.customerContributionPence, 650);
  assert.equal(verifiedSmall.charges[0].actualClassification, "SMALL_VAN");
  assert.equal(verifiedSmall.charges[0].pricingTariffApplied, "LARGE_VAN_COMMERCIAL");
  assert.equal(verifiedLarge.customerContributionPence, 650);
  assert.equal(verifiedLarge.charges[0].pricingTariffApplied, "LARGE_VAN_COMMERCIAL");
  for (const result of [unknown, forgedSmall, conflicting]) {
    assert.equal(result.customerContributionPence, 650);
    assert.equal(result.charges[0].actualClassification, "UNKNOWN");
    assert.equal(result.charges[0].pricingTariffApplied, "LARGE_VAN_CONSERVATIVE");
  }
  assert.equal(evaluate({}, "settlement").authoritativePricingComplete, false);
});

test("conservative Van quote never inflates actual Rider reimbursement", () => {
  const routeFacts = route({crossings: [{
    chargeId: "blackwall_silvertown",
    crossingId: "variance",
    direction: "northbound",
    at: "2026-08-07T08:00:00Z",
  }]});
  const quote = evaluateRoadCharges({routeFacts, selectedVehicle: "van"});
  const actualSmall = evaluateRoadCharges({
    routeFacts,
    selectedVehicle: "van",
    vehicleProfile: {
      tunnelTariffClass: "small_van",
      referenceMassKg: 1100,
      roadChargeFactsVerificationStatus: "verified",
    },
    pricingContext: "settlement",
  });
  const actualLarge = evaluateRoadCharges({
    routeFacts,
    selectedVehicle: "van",
    vehicleProfile: {
      tunnelTariffClass: "large_van",
      referenceMassKg: 1800,
      roadChargeFactsVerificationStatus: "verified",
    },
    pricingContext: "settlement",
  });
  assert.equal(quote.customerContributionPence, 650);
  assert.equal(actualSmall.riderReimbursementPence, 400);
  assert.equal(actualLarge.riderReimbursementPence, 650);
  assert.equal(quote.customerContributionPence, 650);
});

test("all Van quotes use the large tariff and CIRCUM retains the lawful difference", () => {
  const routeFacts = route({crossings: [{
    chargeId: "blackwall_silvertown",
    crossingId: "all-vans-large",
    direction: "northbound",
    at: "2026-08-07T08:00:00Z",
  }]});
  const verifiedSmallProfile = {
    tunnelTariffClass: "small_van",
    referenceMassKg: 1100,
    roadChargeFactsVerificationStatus: "verified",
  };
  const quote = evaluateRoadCharges({
    routeFacts,
    selectedVehicle: "van",
    vehicleProfile: verifiedSmallProfile,
    pricingContext: "quote",
  });
  const settlement = evaluateRoadCharges({
    routeFacts,
    selectedVehicle: "van",
    vehicleProfile: verifiedSmallProfile,
    pricingContext: "settlement",
  });
  assert.equal(quote.customerContributionPence, 650);
  assert.equal(quote.charges[0].actualClassification, "SMALL_VAN");
  assert.equal(quote.charges[0].pricingTariffApplied, "LARGE_VAN_COMMERCIAL");
  assert.equal(settlement.riderReimbursementPence, 400);
  assert.equal(quote.customerContributionPence - settlement.riderReimbursementPence, 250);
});

test("vehicle switch after quote changes actual liability but never customer payment", () => {
  const routeFacts = route({crossings: [{
    chargeId: "blackwall_silvertown",
    crossingId: "vehicle-switch",
    direction: "northbound",
    at: "2026-08-07T08:00:00Z",
  }]});
  const quotedCar = evaluateRoadCharges({routeFacts, selectedVehicle: "car"});
  const assignedLargeVan = evaluateRoadCharges({
    routeFacts,
    selectedVehicle: "van",
    vehicleProfile: {
      tunnelTariffClass: "large_van",
      referenceMassKg: 1800,
      roadChargeFactsVerificationStatus: "verified",
    },
    pricingContext: "settlement",
  });
  assert.equal(quotedCar.customerContributionPence, 400);
  assert.equal(assignedLargeVan.riderReimbursementPence, 650);
  assert.equal(quotedCar.customerContributionPence, 400);
});

test("Van authority keeps unknown distinct from verified large Van", () => {
  const unknown = vanTunnelTariffAuthority({tunnelTariffClass: "large_van"});
  const verified = vanTunnelTariffAuthority({
    tunnelTariffClass: "large_van",
    roadChargeFactsVerificationStatus: "approved",
  });
  assert.equal(unknown.actualClassification, "UNKNOWN");
  assert.equal(unknown.pricingTariffApplied, "LARGE_VAN_CONSERVATIVE");
  assert.equal(verified.actualClassification, "LARGE_VAN");
  assert.equal(verified.pricingTariffApplied, "LARGE_VAN_COMMERCIAL");
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

test("CCZ authority separates chargeable, exempt, discounted, and unknown facts", () => {
  assert.deepEqual(cczVehicleAuthority("motorbike"), {
    status: "VERIFIED_EXEMPT", liabilityPence: 0, discountPercent: 100, verified: true,
  });
  assert.equal(cczVehicleAuthority("car").status, "UNKNOWN");
  assert.equal(cczVehicleAuthority("van").liabilityPence, 1800);
  assert.equal(cczVehicleAuthority("car", {
    cczAuthorityStatus: "VERIFIED_EXEMPT",
    roadChargeFactsVerificationStatus: "verified",
  }).liabilityPence, 0);
  assert.equal(cczVehicleAuthority("car", {
    cczAuthorityStatus: "VERIFIED_DISCOUNT",
    cczDiscountPercent: 25,
    roadChargeFactsVerificationStatus: "verified",
  }).liabilityPence, 1350);
  assert.equal(cczVehicleAuthority("van", {
    cczAuthorityStatus: "VERIFIED_DISCOUNT",
    cczDiscountPercent: 50,
    roadChargeFactsVerificationStatus: "verified",
  }).liabilityPence, 900);
  assert.equal(cczVehicleAuthority("car", {
    cczAuthorityStatus: "VERIFIED_EXEMPT",
  }).status, "UNKNOWN");
});

test("verified CCZ treatment controls quote while unverified claims remain conservative", () => {
  const routeFacts = route({congestionZone: {entered: true, at: "2026-08-07T10:00:00Z"}});
  const evaluate = (selectedVehicle, vehicleProfile = {}) => evaluateRoadCharges({
    routeFacts, selectedVehicle, vehicleProfile,
  });
  assert.equal(evaluate("car").customerContributionPence, 900);
  assert.equal(evaluate("van").customerContributionPence, 900);
  assert.equal(evaluate("motorbike").customerContributionPence, 0);
  assert.equal(evaluate("car", {cczAuthorityStatus: "VERIFIED_EXEMPT"}).customerContributionPence, 900);
  assert.equal(evaluate("car", {
    cczAuthorityStatus: "VERIFIED_EXEMPT",
    roadChargeFactsVerificationStatus: "verified",
  }).customerContributionPence, 0);
  assert.equal(evaluate("car", {
    cczAuthorityStatus: "VERIFIED_DISCOUNT",
    cczDiscountPercent: 25,
    roadChargeFactsVerificationStatus: "verified",
  }).customerContributionPence, 675);
  assert.equal(evaluate("van", {
    cczAuthorityStatus: "VERIFIED_DISCOUNT",
    cczDiscountPercent: 50,
    roadChargeFactsVerificationStatus: "verified",
  }).customerContributionPence, 450);
});

test("unknown CCZ authority is conservative for quote and fails closed for settlement", () => {
  const routeFacts = route({congestionZone: {entered: true, at: "2026-08-07T10:00:00Z"}});
  const quote = evaluateRoadCharges({routeFacts, selectedVehicle: "car"});
  const settlement = evaluateRoadCharges({
    routeFacts,
    selectedVehicle: "car",
    vehicleId: "car-unknown",
    pricingContext: "settlement",
    requireVehicleIdentity: true,
  });
  assert.equal(quote.customerContributionPence, 900);
  assert.equal(quote.charges[0].vehicleAuthorityStatus, "UNKNOWN");
  assert.equal(settlement.authoritativePricingComplete, false);
  assert.equal(settlement.charges[0].status, "tariff_classification_unknown");
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

test("daily recovery matrix is exact at 0, 1, 2, 3, 10, and 100 jobs", () => {
  const expected = new Map([
    [0, {fees: 0, recovery: 0, revenue: 0}],
    [1, {fees: 900, recovery: 900, revenue: 0}],
    [2, {fees: 1800, recovery: 1800, revenue: 0}],
    [3, {fees: 2700, recovery: 1800, revenue: 900}],
    [10, {fees: 9000, recovery: 1800, revenue: 7200}],
    [100, {fees: 90000, recovery: 1800, revenue: 88200}],
  ]);
  for (const [jobs, totals] of expected) {
    let recoveredPence = 0;
    let fees = 0;
    let recovery = 0;
    let revenue = 0;
    for (let job = 0; job < jobs; job += 1) {
      const allocation = dailyRecoveryAllocation({
        liabilityPence: 1800,
        customerFeePence: 900,
        recoveredPence,
      });
      recoveredPence = allocation.recoveredAfterPence;
      fees += allocation.customerFeePence;
      recovery += allocation.riderRecoveryPence;
      revenue += allocation.circumRevenuePence;
    }
    assert.deepEqual({fees, recovery, revenue}, totals);
  }
});

test("per-crossing reimbursement is not capped by the daily-liability waterfall", () => {
  const result = evaluateRoadCharges({
    routeFacts: route({crossings: [{
      chargeId: "blackwall_silvertown",
      crossingId: "three-peak-crossings",
      count: 3,
      direction: "northbound",
      at: "2026-08-07T08:00:00Z",
    }]}),
    selectedVehicle: "car",
  });
  assert.equal(result.customerContributionPence, 1200);
  assert.equal(result.riderReimbursementPence, 1200);
  assert.equal(result.circumRevenuePence, 0);
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
