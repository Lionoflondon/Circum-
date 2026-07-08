const test = require("node:test");
const assert = require("node:assert/strict");
const cleanup = require("./delivery-cleanup");

test("stale booking older than 24 hours can be archived", () => {
  const eligible = cleanup.canAutoArchiveExpired({
    status: "requested",
    matchingStatus: "available",
    createdAt: "2026-07-01T09:00:00.000Z",
    senderId: "sender-1",
  }, new Date("2026-07-08T09:00:00.000Z"));

  assert.equal(eligible, true);
});

test("active and paid unresolved bookings are protected from archive", () => {
  const now = new Date("2026-07-08T09:00:00.000Z");
  assert.equal(cleanup.canAutoArchiveExpired({
    status: "in_transit",
    createdAt: "2026-07-01T09:00:00.000Z",
  }, now), false);
  assert.equal(cleanup.canAutoArchiveExpired({
    status: "requested",
    paymentStatus: "paid",
    createdAt: "2026-07-01T09:00:00.000Z",
  }, now), false);
  assert.equal(cleanup.canAutoArchiveExpired({
    status: "requested",
    disputeOpen: true,
    createdAt: "2026-07-01T09:00:00.000Z",
  }, now), false);
});

test("archive patch blocks rider queues and preserves audit fields", () => {
  const patch = cleanup.archiveExpiredPatch({
    status: "requested",
    senderId: "sender-1",
  }, new Date("2026-07-08T09:00:00.000Z"));

  assert.equal(patch.status, "archived_expired");
  assert.equal(patch.matchingStatus, "blocked");
  assert.equal(patch.dispatchStatus, "blocked");
  assert.equal(patch.broadcastBlocked, true);
  assert.equal(patch.active, false);
  assert.equal(patch.archived, true);
  assert.equal(patch.systemArchived, true);
  assert.ok(Array.isArray(patch.staleReasons));
});

test("missing canonical fields include account recovery fields", () => {
  const missing = cleanup.missingCanonicalFields({
    status: "requested",
    pickupAddress: "Heathrow Airport",
  });

  assert.ok(missing.includes("sender id"));
  assert.ok(missing.includes("sender email"));
  assert.ok(missing.includes("drop-off address"));
  assert.ok(missing.includes("payment status"));
  assert.ok(missing.includes("tracking URL"));
});
