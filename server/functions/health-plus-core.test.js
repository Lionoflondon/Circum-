const assert = require("node:assert/strict");
const test = require("node:test");
const {
  HEALTH_PLUS_MINIMUM_PENCE,
  calculateHealthPlusAmountPence,
  calculateAuthoritativeHealthPlusPricing,
  healthPlusPricingInputFromBooking,
  normalizeSchedule,
  buildHealthPlusCheckoutParams,
  buildAdminStatusUpdate,
  buildCustodyEvent,
} = require("./health-plus-core");

test("creates a Health+ checkout amount with the £11 minimum", () => {
  assert.equal(calculateHealthPlusAmountPence({
    distanceMiles: 0.1,
    medicationWeightKg: 0.5,
  }), HEALTH_PLUS_MINIMUM_PENCE);
});

test("Health+ pricing ignores client breakdown values", () => {
  const lowClientQuote = {total: 11, distanceFare: 0, weightSurcharge: 0};
  const pricing = calculateAuthoritativeHealthPlusPricing({
    distanceMiles: 8,
    medicationWeightKg: 0.5,
    subscriptionPlan: "priority",
    frequency: "one_off",
    priceBreakdown: lowClientQuote,
  });
  assert.equal(pricing.amountPence, 1820);
  assert.equal(pricing.distanceFarePence, 1200);
  assert.equal(pricing.weightSurchargePence, 0);
  assert.equal(pricing.priorityFeePence, 0);
});

test("Health+ one-off pricing applies Health+ policy without weight economics", () => {
  const pricing = calculateAuthoritativeHealthPlusPricing({
    distanceMiles: 4.8,
    medicationWeightKg: 12,
    subscriptionPlan: "family",
    frequency: "one_off",
  });
  assert.equal(pricing.baseFarePence, 500);
  assert.equal(pricing.distanceFarePence, 720);
  assert.equal(pricing.weightSurchargePence, 0);
  assert.equal(pricing.weightContributionPence, 0);
  assert.equal(pricing.familySupportFeePence, 0);
  assert.equal(pricing.recurringDiscountPence, 0);
  assert.equal(pricing.amountPence, 1340);
});

test("Health+ unknown or changing medication weight does not change customer charge", () => {
  const unknown = calculateAuthoritativeHealthPlusPricing({
    distanceMiles: 4.8,
    subscriptionPlan: "family",
    frequency: "one_off",
  });
  const heavy = calculateAuthoritativeHealthPlusPricing({
    distanceMiles: 4.8,
    medicationWeightKg: 20,
    subscriptionPlan: "family",
    frequency: "one_off",
  });
  assert.equal(unknown.amountPence, heavy.amountPence);
  assert.equal(unknown.weightSurchargePence, 0);
  assert.equal(heavy.weightSurchargePence, 0);
});

test("Health+ subscriptions use the locked monthly plan prices", () => {
  assert.equal(calculateAuthoritativeHealthPlusPricing({
    distanceMiles: 4.8,
    medicationWeightKg: 0.5,
    subscriptionPlan: "basic",
    frequency: "monthly",
  }).amountPence, 1100);
  assert.equal(calculateAuthoritativeHealthPlusPricing({
    distanceMiles: 4.8,
    medicationWeightKg: 0.5,
    subscriptionPlan: "priority",
    frequency: "monthly",
  }).amountPence, 2500);
  const family = calculateAuthoritativeHealthPlusPricing({
    distanceMiles: 4.8,
    medicationWeightKg: 0.5,
    subscriptionPlan: "family",
    frequency: "monthly",
  });
  assert.equal(family.amountPence, 4000);
  assert.equal(family.unlimitedPickups, true);
  assert.equal(family.fairUseMonitored, true);
});

test("missing authoritative Health+ pricing inputs fail safely", () => {
  assert.throws(
      () => calculateAuthoritativeHealthPlusPricing({
        subscriptionPlan: "priority",
        frequency: "one_off",
      }),
      /route distance is required/,
  );
});

test("Health+ booking data determines checkout pricing input", () => {
  const input = healthPlusPricingInputFromBooking({
    pricingInputs: {distanceMiles: 4.8, medicationWeightKg: 0.5},
    frequency: "monthly",
    healthPlusPlan: "priority",
  });
  assert.deepEqual(input, {
    distanceMiles: 4.8,
    medicationWeightKg: 0.5,
    frequency: "monthly",
    subscriptionPlan: "priority",
  });
});

test("Health+ pricing uses authoritative route distance and road charges", () => {
  const quote = calculateAuthoritativeHealthPlusPricing({
    distanceMiles: 1,
    medicationWeightKg: 0.5,
    routeFacts: {distanceMiles: 8},
    roadChargeCustomerAmount: 9,
    roadCharges: {customerAmount: 9, lineItems: [{key: "daily_zone_charge", amount: 9}]},
    frequency: "one_off",
  });
  assert.equal(quote.distanceMiles, 8);
  assert.equal(quote.roadChargePence, 900);
  assert.equal(quote.roadCharges.customerAmount, 9);
});

test("creates recurring secure checkout session params", () => {
  const params = buildHealthPlusCheckoutParams({
    bookingId: "pickup_1",
    profileId: "profile_1",
    email: "user@example.com",
    amountPence: 1300,
    recurring: true,
    successUrl: "https://example.com/success",
    cancelUrl: "https://example.com/cancel",
  });

  assert.equal(params.mode, "subscription");
  assert.equal(params.line_items[0].price_data.recurring.interval, "month");
  assert.equal(params.metadata.feature, "health_plus");
});

test("normalizes recurring pickup schedules", () => {
  assert.equal(normalizeSchedule("every_2_weeks"), "every_2_weeks");
  assert.equal(normalizeSchedule("every_28_days"), "every_28_days");
  assert.equal(normalizeSchedule("random"), "one_off");
});

test("builds Health+ custody events for operational archive", () => {
  const event = buildCustodyEvent({
    eventType: "pickup_delivered",
    actorType: "rider",
    actorId: "rider_1",
    actorName: "Ayo",
    publicMessage: "Health+ pickup delivered.",
    internalNote: "Delivery completed with custody evidence.",
    statusAfterEvent: "delivered",
    evidenceUrl: "https://example.com/proof.jpg",
  });
  assert.equal(event.eventType, "pickup_delivered");
  assert.equal(event.actorType, "rider");
  assert.equal(event.actorId, "rider_1");
  assert.equal(event.actorName, "Ayo");
  assert.equal(event.statusAfterEvent, "delivered");
  assert.equal(event.evidenceUrl, "https://example.com/proof.jpg");
  assert.equal(typeof event.timestamp, "number");
});

test("admin status updates reject unknown pickup statuses", () => {
  assert.throws(() => buildAdminStatusUpdate("lost"));
  const update = buildAdminStatusUpdate("collected", "driver_1");
  assert.equal(update.status, "collected");
  assert.equal(update.assignedDriverId, "driver_1");
  assert.equal(typeof update.updatedAt, "number");
});
