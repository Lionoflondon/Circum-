const assert = require("node:assert/strict");
const test = require("node:test");
const {
  HEALTH_PLUS_MINIMUM_PENCE,
  calculateHealthPlusAmountPence,
  normalizeSchedule,
  buildHealthPlusCheckoutParams,
  buildAdminStatusUpdate,
} = require("./health-plus-core");

test("creates a Health+ checkout amount with the £11 minimum", () => {
  assert.equal(calculateHealthPlusAmountPence({
    baseFarePence: 600,
    distanceFarePence: 200,
    weightSurchargePence: 0,
    serviceFeePence: 120,
  }), HEALTH_PLUS_MINIMUM_PENCE);
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
