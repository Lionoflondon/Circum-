"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {canonicalGiftDeliveryPricing} = require("./gift-delivery-pricing-core");
const {quotePayload} = require("./sender-booking")._private;
const fs = require("node:fs");
const path = require("node:path");

function fixture(overrides = {}) {
  return {
    giftRequestId: "gift-1",
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

test("Gift budget and purchase spend never enter delivery earnings", () => {
  const low = canonicalGiftDeliveryPricing(fixture({giftBudget: 50, giftSpend: 40}));
  const high = canonicalGiftDeliveryPricing(fixture({giftBudget: 1500, giftSpend: 1400}));
  assert.deepEqual(high, low);
});

test("Gift weight and IRIS weight contribute zero", () => {
  const light = canonicalGiftDeliveryPricing(fixture({weightKg: 1, irisWeightKg: 2}));
  const heavy = canonicalGiftDeliveryPricing(fixture({weightKg: 100, irisWeightKg: 150}));
  assert.deepEqual(heavy, light);
  assert.equal(heavy.weightContribution, 0);
  assert.equal(heavy.lineItems.find((item) => item.key === "weight").amount, 0);
});

test("Gift uses the normal backend fare and exact 65/35 split", () => {
  const input = fixture();
  const gift = canonicalGiftDeliveryPricing(input);
  const standardAtZeroWeight = quotePayload({
    authoritativeRouteFacts: input.authoritativeRouteFacts,
    sourceModule: "gifts",
    serviceType: "GIFTS",
    weightKg: 0,
    parcel: {weightKg: 0},
    selectedVehicle: input.selectedVehicle,
    selectedSpeed: input.selectedSpeed,
  }, "gift-1");
  assert.equal(gift.deliveryCharge, standardAtZeroWeight.total);
  assert.equal(gift.riderEarning, standardAtZeroWeight.totalRiderEarnings);
  assert.equal(gift.platformShare, standardAtZeroWeight.totalCircumRevenue);
  assert.equal(gift.riderShareRate, 0.65);
  assert.equal(gift.platformShareRate, 0.35);
  assert.equal(gift.riderEarning + gift.platformShare, gift.deliveryCharge);
});

test("Standard weight pricing remains active while Gift weight is excluded", () => {
  const input = fixture();
  const gift = canonicalGiftDeliveryPricing({...input, weightKg: 100});
  const heavyStandard = quotePayload({
    authoritativeRouteFacts: input.authoritativeRouteFacts,
    sourceModule: "sender",
    serviceType: "STANDARD",
    weightKg: 100,
    selectedVehicle: input.selectedVehicle,
    selectedSpeed: input.selectedSpeed,
  }, "standard-heavy");
  assert.ok(heavyStandard.total > gift.deliveryCharge);
  assert.ok(heavyStandard.lineItems.find((item) => item.key === "weight").amount > 0);
});

test("scheduled Gift uses the same earnings rule and currency rounding", () => {
  const immediate = canonicalGiftDeliveryPricing(fixture());
  const scheduled = canonicalGiftDeliveryPricing(fixture({scheduledAt: "2099-08-14T12:00:00.000Z"}));
  assert.equal(scheduled.riderEarning, immediate.riderEarning);
  assert.equal(scheduled.platformShare, immediate.platformShare);
  assert.equal(Number(scheduled.riderEarning.toFixed(2)), scheduled.riderEarning);
});

test("Gift pricing fails closed without backend route authority", () => {
  assert.equal(canonicalGiftDeliveryPricing({giftBudget: 1500}), null);
  assert.equal(canonicalGiftDeliveryPricing({
    authoritativeRouteFacts: {authority: "client", distanceMiles: 10},
  }), null);
});

test("Gift payment input cannot author logistics settlement fields", () => {
  const source = fs.readFileSync(path.join(__dirname, "gifts-payment.js"), "utf8");
  for (const field of [
    "deliveryCharge", "riderEarning", "riderPayout", "driverPayout",
    "platformShare", "riderSettlementAuthority", "giftDeliveryPricing",
    "authoritativeRouteFacts",
  ]) assert.match(source, new RegExp(`\\"${field}\\"`));
  assert.match(source, /withoutGiftDeliveryAuthority\(data\.giftDraft\)/);
});
