const assert = require("node:assert/strict");
const test = require("node:test");
const {
  HEALTH_PLUS_MINIMUM_PENCE,
  calculateHealthPlusAmountPence,
  normalizeSchedule,
  buildHealthPlusCheckoutParams,
  buildAdminStatusUpdate,
  buildHealthPlusPlanFields,
  buildCustodyEvent,
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

test("builds launch Health+ plans and usage counters", () => {
  const core = buildHealthPlusPlanFields("core", {usedDeliveriesThisCycle: 1});
  assert.equal(core.monthlyPrice, 15);
  assert.equal(core.includedDeliveries, 2);
  assert.equal(core.remainingDeliveriesThisCycle, 1);
  assert.equal(core.overageRate, 7.5);
  assert.equal(core.isVanguard, true);
  assert.equal(core.trustPoints, 6);

  const priority = buildHealthPlusPlanFields("priority");
  assert.equal(priority.monthlyPrice, 25);
  assert.equal(priority.includedDeliveries, 4);
  assert.equal(priority.overageRate, 6.25);

  const family = buildHealthPlusPlanFields("family");
  assert.equal(family.monthlyPrice, 40);
  assert.equal(family.remainingDeliveriesThisCycle, null);

  const custom = buildHealthPlusPlanFields("custom", {
    monthlyPrice: 75,
    customIncludedDeliveries: 6,
    customOverageRate: 5,
  });
  assert.equal(custom.monthlyPrice, 75);
  assert.equal(custom.includedDeliveries, 6);
  assert.equal(custom.customOverageRate, 5);
});

test("custody archive entries require a public-safe message", () => {
  const event = buildCustodyEvent({
    eventType: "prescription_collected",
    publicMessage: "Your prescription has been collected.",
    statusAfterEvent: "collected",
    actorType: "rider",
  });
  assert.equal(event.actorType, "rider");
  assert.equal(event.internalNote, null);
  assert.throws(() => buildCustodyEvent({eventType: "collected"}));
});
