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
  assert.equal(pricing.amountPence, 2119);
  assert.equal(pricing.distanceFarePence, 1200);
  assert.equal(pricing.priorityFeePence, 299);
});

test("Health+ pricing applies plan and weight policy", () => {
  const pricing = calculateAuthoritativeHealthPlusPricing({
    distanceMiles: 4.8,
    medicationWeightKg: 12,
    subscriptionPlan: "family",
    frequency: "weekly",
  });
  assert.equal(pricing.baseFarePence, 500);
  assert.equal(pricing.distanceFarePence, 720);
  assert.equal(pricing.weightSurchargePence, 700);
  assert.equal(pricing.familySupportFeePence, 399);
  assert.equal(pricing.recurringDiscountPence, 150);
  assert.equal(pricing.amountPence, 2289);
});

test("missing authoritative Health+ pricing inputs fail safely", () => {
  assert.throws(
      () => calculateAuthoritativeHealthPlusPricing({
        subscriptionPlan: "priority",
        frequency: "one_off",
      }),
      /route distance and medication weight are required/,
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

test("admin status updates reject unknown pickup statuses", () => {
  assert.throws(() => buildAdminStatusUpdate("lost"));
  const update = buildAdminStatusUpdate("collected", "driver_1");
  assert.equal(update.status, "collected");
  assert.equal(update.assignedDriverId, "driver_1");
  assert.equal(typeof update.updatedAt, "number");
});
