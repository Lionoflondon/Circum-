"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {canonicalHealthPlusDeliveryPricing} = require("./health-plus-delivery-pricing-core");
const {quotePayload} = require("./sender-booking")._private;
const {canonicalGiftDeliveryPricing} = require("./gift-delivery-pricing-core");

function fixture(overrides = {}) {
  return {
    healthPlusPickupId: "health-1",
    authoritativeRouteFacts: {
      authority: "authoritative_route",
      distanceMiles: 10,
      durationSeconds: 1800,
      geography: {},
      ...overrides.routeFacts,
    },
    selectedVehicle: "motorbike",
    selectedSpeed: "standard",
    ...overrides,
  };
}

test("Health+ subscription and one-off charges never become Rider payout base", () => {
  const subscription = canonicalHealthPlusDeliveryPricing(fixture({
    healthPlusCharge: 100,
    paymentType: "subscription",
  }));
  const oneOff = canonicalHealthPlusDeliveryPricing(fixture({
    healthPlusCharge: 25,
    paymentType: "one_off",
  }));
  assert.deepEqual(subscription, oneOff);
  assert.notEqual(subscription.riderEarning, 65);
  assert.notEqual(oneOff.riderEarning, 16.25);
});

test("Health+ prescription value and all weight variants do not affect logistics earnings", () => {
  const low = canonicalHealthPlusDeliveryPricing(fixture({
    prescriptionValue: 10,
    medicationWeightKg: 0,
    estimatedWeightKg: 1,
    actualWeightKg: 2,
    irisWeightKg: 3,
  }));
  const high = canonicalHealthPlusDeliveryPricing(fixture({
    prescriptionValue: 2000,
    medicationValue: 2000,
    medicationWeightKg: 20,
    estimatedWeightKg: 30,
    actualWeightKg: 40,
    irisWeightKg: 50,
    packageWeightBand: "Extra Heavy",
  }));
  assert.deepEqual(high, low);
  assert.equal(high.weightContribution, 0);
  assert.equal(high.lineItems.find((item) => item.key === "weight").amount, 0);
});

test("Health+ uses normal logistics at zero weight with exact 65/35 split", () => {
  const input = fixture();
  const health = canonicalHealthPlusDeliveryPricing(input);
  const standardAtZeroWeight = quotePayload({
    authoritativeRouteFacts: input.authoritativeRouteFacts,
    sourceModule: "health_plus",
    serviceType: "HEALTH_PLUS",
    weightKg: 0,
    parcel: {weightKg: 0},
    selectedVehicle: input.selectedVehicle,
    selectedSpeed: input.selectedSpeed,
  }, "health-1");
  assert.equal(health.deliveryCharge, standardAtZeroWeight.total);
  assert.equal(health.logisticsValue, standardAtZeroWeight.total);
  assert.equal(health.riderEarning, standardAtZeroWeight.totalRiderEarnings);
  assert.equal(health.platformShare, standardAtZeroWeight.totalCircumRevenue);
  assert.equal(health.riderShareRate, 0.65);
  assert.equal(health.platformShareRate, 0.35);
  assert.equal(health.riderEarning + health.platformShare, health.deliveryCharge);
});

test("Scheduled Health+ uses the same logistics earnings", () => {
  const immediate = canonicalHealthPlusDeliveryPricing(fixture());
  const scheduled = canonicalHealthPlusDeliveryPricing(fixture({
    scheduledAt: "2099-08-14T12:00:00.000Z",
  }));
  assert.equal(scheduled.deliveryCharge, immediate.deliveryCharge);
  assert.equal(scheduled.riderEarning, immediate.riderEarning);
  assert.equal(scheduled.platformShare, immediate.platformShare);
});

test("Health+ logistics fails closed without backend route authority", () => {
  assert.equal(canonicalHealthPlusDeliveryPricing({healthPlusCharge: 100}), null);
  assert.equal(canonicalHealthPlusDeliveryPricing({
    authoritativeRouteFacts: {authority: "client", distanceMiles: 10},
  }), null);
});

test("Gift budget separation remains green beside Health+ economics", () => {
  const low = canonicalGiftDeliveryPricing(fixture({
    giftRequestId: "gift-1",
    giftBudget: 50,
    giftSpend: 40,
  }));
  const high = canonicalGiftDeliveryPricing(fixture({
    giftRequestId: "gift-1",
    giftBudget: 1500,
    giftSpend: 1400,
  }));
  assert.deepEqual(high, low);
});
