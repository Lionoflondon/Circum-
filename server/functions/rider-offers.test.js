const test = require("node:test");
const assert = require("node:assert/strict");
const {projection} = require("./rider-offers");

test("offer projection preserves safe canonical schedule and service level", () => {
  const projected = projection("scheduled-express", {
    deliveryTime: {
      type: "scheduled",
      scheduledAt: "2026-10-01T09:00:00Z",
      scheduledDate: "2026-10-01",
      scheduledWindow: "Morning",
      customWindowStart: "09:00",
      customWindowEnd: "12:00",
      summary: "Thursday morning",
      privateNote: "must not be projected",
    },
    serviceLevel: "Express",
    scheduledAt: "2026-10-01T09:00:00Z",
  }, 1800000000000);

  assert.equal(projected.serviceLevel, "Express");
  assert.equal(projected.isScheduled, true);
  assert.deepEqual(projected.deliveryTime, {
    type: "scheduled",
    scheduledAt: "2026-10-01T09:00:00Z",
    scheduledDate: "2026-10-01",
    scheduledWindow: "Morning",
    customWindowStart: "09:00",
    customWindowEnd: "12:00",
    summary: "Thursday morning",
  });
});

test("offer projection uses the canonical default service level", () => {
  assert.equal(projection("standard", {}, 1800000000000).serviceLevel, "Standard");
});
