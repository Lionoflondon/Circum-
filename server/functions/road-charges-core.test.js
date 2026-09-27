"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  CONGESTION_CHARGE_ON_TIME_PENCE,
  CONGESTION_CHARGE_LATE_PENCE,
  ROAD_CHARGE_POLICY,
  chargeIsEffective,
  congestionChargeable,
  evaluateRoadCharges,
} = require("./road-charges-core");

const authoritativeFacts = ({
  crossings = [],
  congestionZone,
  ulez,
} = {}) => ({
  authority: "authoritative_route",
  crossings,
  ...(congestionZone ? {congestionZone} : {}),
  ...(ulez ? {ulez} : {}),
});

const crossing = ({
  crossingId = "blackwall",
  at,
  crossingAt,
  direction = "northbound",
  count = 1,
} = {}) => ({
  chargeId: "blackwall_silvertown",
  crossingId,
  at: at || crossingAt,
  direction,
  count,
});

function tunnelCharge(options = {}) {
  const result = evaluateRoadCharges({
    routeFacts: authoritativeFacts({
      crossings: [crossing(options)],
    }),
    selectedVehicle: options.vehicle || "car",
    vehicleProfile: options.vehicleProfile || {},
    at: options.at || options.crossingAt,
  });
  return result.charges[0];
}

test("current official Blackwall/Silvertown tariff is stored with labels", () => {
  const rates = ROAD_CHARGE_POLICY.charges.blackwall_silvertown.ratesPence;
  assert.deepEqual(rates.motorbike, {offPeak: 155, peak: 260});
  assert.deepEqual(rates.car, {offPeak: 155, peak: 420});
  assert.deepEqual(rates.van_small, {offPeak: 155, peak: 420});
  assert.deepEqual(rates.van_large, {offPeak: 260, peak: 680});
  assert.equal(
      ROAD_CHARGE_POLICY.charges.blackwall_silvertown.customerLabel,
      "Blackwall/Silvertown tunnel charge",
  );
});

test("Blackwall/Silvertown switches exactly at 21 September 2026", () => {
  const before = tunnelCharge({
    crossingAt: "2026-09-20T12:00:00+01:00",
    direction: "northbound",
  });
  const after = tunnelCharge({
    crossingAt: "2026-09-21T12:00:00+01:00",
    direction: "northbound",
  });
  assert.equal(before.amountPence, 150);
  assert.equal(after.amountPence, 155);
  assert.equal(
      chargeIsEffective(
          ROAD_CHARGE_POLICY.charges.blackwall_silvertown,
          "2026-09-21T00:00:00+01:00",
      ),
      true,
  );
});

test("Blackwall/Silvertown peak windows are direction and Europe/London aware", () => {
  assert.equal(tunnelCharge({
    crossingAt: "2026-09-21T09:59:59+01:00",
    direction: "northbound",
  }).amountPence, 420);
  assert.equal(tunnelCharge({
    crossingAt: "2026-09-21T10:00:00+01:00",
    direction: "northbound",
  }).amountPence, 155);
  assert.equal(tunnelCharge({
    crossingAt: "2026-09-21T16:00:00+01:00",
    direction: "southbound",
  }).amountPence, 420);
  assert.equal(tunnelCharge({
    crossingAt: "2026-09-21T19:00:00+01:00",
    direction: "southbound",
  }).amountPence, 155);
  assert.equal(tunnelCharge({
    crossingAt: "2026-09-20T12:00:00+01:00",
    direction: "northbound",
  }).amountPence, 150);
  assert.equal(tunnelCharge({
    crossingAt: "2026-09-21T22:00:00+01:00",
    direction: "northbound",
  }).status, "outside_charging_hours");
});

test("verified van facts select the existing small/large tunnel mapping", () => {
  assert.equal(tunnelCharge({
    crossingAt: "2026-09-21T12:00:00+01:00",
    vehicle: "van",
    vehicleProfile: {
      type: "van",
      tunnelTariffClass: "small_van",
      roadChargeFactsVerificationStatus: "verified",
    },
  }).amountPence, 155);
  assert.equal(tunnelCharge({
    crossingAt: "2026-09-21T12:00:00+01:00",
    vehicle: "van",
    vehicleProfile: {
      type: "van",
      tunnelTariffClass: "large_van",
      roadChargeFactsVerificationStatus: "verified",
    },
  }).amountPence, 260);
  const fallback = tunnelCharge({
    crossingAt: "2026-09-21T12:00:00+01:00",
    vehicle: "van",
    vehicleProfile: {type: "van"},
  });
  assert.equal(fallback.amountPence, 260);
  assert.equal(fallback.pricingTariffApplied, "LARGE_VAN_CONSERVATIVE");
});

test("two tunnel crossings are charged once each and duplicate evidence is ignored", () => {
  const facts = authoritativeFacts({
    crossings: [
      crossing({
        crossingId: "blackwall",
        crossingAt: "2026-09-21T09:00:00+01:00",
        at: "2026-09-21T09:00:00+01:00",
      }),
      crossing({
        crossingId: "silvertown",
        crossingAt: "2026-09-21T09:00:00+01:00",
        at: "2026-09-21T09:00:00+01:00",
      }),
      crossing({
        crossingId: "blackwall",
        crossingAt: "2026-09-21T09:00:00+01:00",
        at: "2026-09-21T09:00:00+01:00",
      }),
    ],
  });
  const result = evaluateRoadCharges({
    routeFacts: facts,
    selectedVehicle: "car",
    at: "2026-09-21T09:00:00+01:00",
  });
  assert.equal(result.charges.length, 2);
  assert.equal(result.customerContributionPence, 840);
});

test("Congestion Charge keeps £18 as normal liability and £21 only as reference", () => {
  const charge = ROAD_CHARGE_POLICY.charges.congestion_charge;
  assert.equal(charge.amountPence, CONGESTION_CHARGE_ON_TIME_PENCE);
  assert.equal(charge.latePaymentAmountPence, CONGESTION_CHARGE_LATE_PENCE);
  const result = evaluateRoadCharges({
    routeFacts: authoritativeFacts({
      congestionZone: {
        entered: true,
        at: "2026-09-21T08:00:00+01:00",
      },
    }),
    selectedVehicle: "car",
    vehicleProfile: {
      type: "car",
      roadChargeFactsVerificationStatus: "verified",
      cczAuthorityStatus: "CHARGEABLE",
    },
  });
  assert.equal(result.charges[0].amountPence, 1800);
  assert.equal(result.charges[0].customerContributionPence, 900);
});

test("Congestion Charge observes London weekend, bank-holiday, and Christmas windows", () => {
  assert.equal(congestionChargeable({at: "2026-09-21T06:59:59+01:00"}), false);
  assert.equal(congestionChargeable({at: "2026-09-21T07:00:00+01:00"}), true);
  assert.equal(congestionChargeable({at: "2026-09-20T11:59:59+01:00"}), false);
  assert.equal(congestionChargeable({at: "2026-09-20T12:00:00+01:00"}), true);
  assert.equal(congestionChargeable({
    at: "2026-08-31T11:59:59+01:00",
    isBankHoliday: true,
  }), false);
  assert.equal(congestionChargeable({
    at: "2026-08-31T12:00:00+01:00",
    isBankHoliday: true,
  }), true);
  assert.equal(congestionChargeable({at: "2026-12-25T13:00:00+00:00"}), false);
  assert.equal(congestionChargeable({at: "2027-01-01T13:00:00+00:00"}), false);
});

test("ULEZ stores the official rate but remains compliance-conditional", () => {
  assert.equal(ROAD_CHARGE_POLICY.charges.ulez.dailyAmountPence, 1250);
  const result = evaluateRoadCharges({
    routeFacts: authoritativeFacts({
      ulez: {
        applicable: true,
        compliant: false,
        at: "2026-09-21T12:00:00+01:00",
      },
    }),
    selectedVehicle: "car",
  });
  assert.equal(result.charges[0].amountPence, 0);
  assert.equal(result.charges[0].status, "compliance_audit_required");
  assert.equal(result.customerContributionPence, 0);
  assert.equal(result.charges[0].customerLabel, "ULEZ charge");
});

test("Dartford uses current one-off rates, keeps motorcycles free, and respects hours", () => {
  const dartford = (vehicle, vehicleProfile = {}, at = "2026-09-21T12:00:00+01:00") =>
    evaluateRoadCharges({
      routeFacts: authoritativeFacts({
        crossings: [{
          chargeId: "dartford_crossing",
          crossingId: "dartford",
          at,
        }],
      }),
      selectedVehicle: vehicle,
      vehicleProfile,
      at,
    }).charges[0];
  assert.equal(dartford("motorbike").amountPence, 0);
  assert.equal(dartford("car").amountPence, 350);
  assert.equal(dartford("van", {
    type: "van",
    axleCount: 2,
    roadChargeFactsVerificationStatus: "verified",
  }).amountPence, 420);
  assert.equal(dartford("van", {
    type: "van",
    axleCount: 3,
    roadChargeFactsVerificationStatus: "verified",
  }).amountPence, 840);
  assert.equal(dartford("car", {}, "2026-09-21T22:00:00+01:00").status, "outside_charging_hours");
});
