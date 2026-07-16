/* eslint-disable max-len */
const test = require("node:test");
const assert = require("node:assert/strict");
const core = require("./stale-delivery-core");

const now = Date.parse("2026-07-15T12:00:00Z");

test("stale recoverable delivery releases Rider availability lock", () => {
  const result = core.evaluateDeliveryLock({
    status: "recoverable_incomplete",
    updatedAt: "2026-07-15T08:00:00Z",
    paymentStatus: "paid",
  }, {now});
  assert.deepEqual(result, {
    block: false,
    repair: true,
    archive: true,
    reason: "stale_recoverable_delivery",
  });
});

test("genuine active delivery still blocks offline", () => {
  const result = core.evaluateDeliveryLock({
    status: "navigating_to_pickup",
    updatedAt: "2026-07-15T11:58:00Z",
  }, {now});
  assert.equal(result.block, true);
  assert.equal(result.reason, "active_navigating_to_pickup");
});

test("old accepted delivery remains locked and enters Admin review", () => {
  const result = core.evaluateDeliveryLock({
    status: "accepted",
    updatedAt: "2026-07-14T20:00:00Z",
  }, {now});
  assert.equal(result.block, true);
  assert.equal(result.repair, false);
  assert.equal(result.review, true);
  assert.equal(result.reason, "stale_accepted_requires_review");
});

test("future scheduled delivery is not expired", () => {
  const result = core.evaluateDeliveryLock({
    status: "accepted",
    scheduledAt: "2026-07-16T10:00:00Z",
    updatedAt: "2026-07-14T10:00:00Z",
  }, {now});
  assert.equal(result.block, true);
  assert.equal(result.reason, "scheduled_window_active");
});

test("picked-up delivery is never auto-cleared", () => {
  for (const delivery of [
    {status: "collected", updatedAt: "2026-07-01T00:00:00Z"},
    {status: "recoverable_incomplete", collectedAt: "2026-07-01T00:00:00Z"},
  ]) {
    const result = core.evaluateDeliveryLock(delivery, {now});
    assert.equal(result.block, true);
    assert.equal(result.reason, "parcel_collected");
  }
});

test("missing stale activeDeliveryId reference can be repaired", () => {
  assert.deepEqual(core.evaluateDeliveryLock(null, {now, exists: false}), {
    block: false,
    repair: true,
    archive: false,
    reason: "delivery_missing",
  });
});

test("waiting and support-held deliveries remain locked", () => {
  assert.equal(core.evaluateDeliveryLock({status: "waiting"}, {now}).block, true);
  assert.equal(core.evaluateDeliveryLock({status: "accepted", supportHold: true}, {now}).block, true);
});
