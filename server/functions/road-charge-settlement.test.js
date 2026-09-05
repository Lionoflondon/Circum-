const test = require("node:test");
const assert = require("node:assert/strict");
const {planRoadChargeSettlement} = require("./road-charge-settlement");

const delivery = (charges) => ({pricingBreakdown: {roadCharges: {charges}}});

test("CCZ recovery is capped by the frozen daily liability", () => {
  const charge = {
    chargeId: "congestion_charge",
    type: "daily_zone_charge",
    amountPence: 1800,
    customerContributionPence: 900,
    chargingDate: "2026-08-09",
  };
  const first = planRoadChargeSettlement({
    deliveryId: "a",
    riderId: "r",
    delivery: delivery([charge]),
    assignedVehicle: {id: "car-1", type: "car"},
  });
  const second = planRoadChargeSettlement({
    deliveryId: "b",
    riderId: "r",
    delivery: delivery([charge]),
    assignedVehicle: {id: "car-1", type: "car"},
    dailyState: {"car-1:2026-08-09:congestion_charge": {recoveredPence: 900}},
  });
  const third = planRoadChargeSettlement({
    deliveryId: "c",
    riderId: "r",
    delivery: delivery([charge]),
    assignedVehicle: {id: "car-1", type: "car"},
    dailyState: {"car-1:2026-08-09:congestion_charge": {recoveredPence: 1800}},
  });
  assert.equal(first.reimbursementPence, 900);
  assert.equal(second.reimbursementPence, 900);
  assert.equal(third.reimbursementPence, 0);
});

test("crossing reimbursement is one frozen, idempotent effect", () => {
  const result = planRoadChargeSettlement({
    deliveryId: "a",
    riderId: "r",
    delivery: delivery([
      {
        chargeId: "blackwall_silvertown",
        type: "route_toll",
        amountPence: 400,
        riderReimbursementPence: 400,
      },
    ]),
    assignedVehicle: {id: "car-1", type: "car"},
  });
  assert.equal(result.reimbursementPence, 400);
  assert.equal(result.effects[0].role, "crossing_reimbursement");
  assert.match(result.effects[0].id, /^a:blackwall_silvertown:/);
});

test("compliance-only charges create no settlement effect", () => {
  const result = planRoadChargeSettlement({
    deliveryId: "a",
    riderId: "r",
    delivery: delivery([
      {chargeId: "ulez", type: "vehicle_compliance", amountPence: 0},
    ]),
    assignedVehicle: {id: "car-1", type: "car"},
  });
  assert.equal(result.effects.length, 0);
  assert.equal(result.reimbursementPence, 0);
});
