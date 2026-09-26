const test = require("node:test");
const assert = require("node:assert/strict");
const core = require("./gift-recurring-core");

test("recurring frequency is explicit and maps to Stripe billing intervals", () => {
  assert.equal(core.normalizeFrequency("one_off"), "one_time");
  assert.deepEqual(core.intervalFor("monthly"), {interval: "month", interval_count: 1, label: "Monthly"});
  assert.deepEqual(core.intervalFor("quarterly"), {interval: "month", interval_count: 4, label: "Every 4 months"});
  assert.equal(core.isRecurringFrequency("one_time"), false);
});

test("series and renewal identities are deterministic", () => {
  assert.equal(core.seriesIdForGift("gift-1"), core.seriesIdForGift("gift-1"));
  assert.notEqual(core.seriesIdForGift("gift-1"), core.seriesIdForGift("gift-2"));
  assert.equal(core.renewalIdForInvoice("sub-1", "in-1"), core.renewalIdForInvoice("sub-1", "in-1"));
  assert.notEqual(core.renewalGiftIdForInvoice("sub-1", "in-1"), core.renewalGiftIdForInvoice("sub-1", "in-2"));
});

test("delivery pattern preserves the original day and never schedules in the past", () => {
  const pattern = core.buildDeliveryPattern("2026-01-15T12:00:00Z", {timeWindow: "afternoon"});
  const result = core.deliveryDateForPeriod({
    pattern,
    periodStart: "2026-02-01T00:00:00Z",
    periodEnd: "2026-03-01T00:00:00Z",
    now: "2026-02-02T00:00:00Z",
  });
  assert.equal(result.status, "scheduled");
  assert.equal(result.date, "2026-02-15T12:00:00.000Z");
  assert.equal(result.timeWindow, "afternoon");
});

test("an impossible day-of-month is action-required, never silently clamped", () => {
  const pattern = core.buildDeliveryPattern("2026-01-31T12:00:00Z");
  const result = core.deliveryDateForPeriod({
    pattern,
    periodStart: "2026-02-01T00:00:00Z",
    periodEnd: "2026-03-01T00:00:00Z",
    now: "2026-02-02T00:00:00Z",
  });
  assert.equal(result.status, "action_required");
  assert.equal(result.reason, "delivery_day_not_present_in_period");
});

test("successful renewal only accepts paid invoice state", () => {
  assert.equal(core.successfulInvoice({status: "paid"}), true);
  assert.equal(core.successfulInvoice({status: "open", paid: false}), false);
  assert.equal(core.subscriptionState("active", true), "cancellation_pending");
  assert.equal(core.subscriptionState("canceled"), "ended");
});

test("next renewal advances by the actual Stripe interval and preserves a safe month boundary", () => {
  assert.equal(
      new Date(core.nextRenewalAt({from: "2026-01-31T12:00:00Z", frequency: "monthly"})).toISOString(),
      "2026-02-28T12:00:00.000Z",
  );
  assert.equal(
      new Date(core.nextRenewalAt({from: "2026-01-15T12:00:00Z", frequency: "quarterly"})).toISOString(),
      "2026-05-15T12:00:00.000Z",
  );
});
