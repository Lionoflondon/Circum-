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

test("Founder purge expires only stale unaccepted open deliveries", () => {
  const now = new Date("2026-07-08T09:00:00.000Z");
  assert.equal(cleanup.canFounderPurgeDelivery({
    status: "searching",
    dispatchStatus: "broadcast",
    matchingStatus: "available",
    createdAt: "2026-07-07T08:00:00.000Z",
    founderTest: true,
  }, now), true);
  assert.equal(cleanup.canFounderPurgeDelivery({
    status: "pending",
    createdAt: "2026-07-07T08:00:00.000Z",
  }, now), true);
  assert.equal(cleanup.canFounderPurgeDelivery({
    status: "pending",
    createdAt: "2026-07-08T08:30:00.000Z",
  }, now), false);
});

test("Founder purge protects active assigned disputed and terminal deliveries", () => {
  const now = new Date("2026-07-08T09:00:00.000Z");
  assert.equal(cleanup.canFounderPurgeDelivery({
    status: "accepted",
    createdAt: "2026-07-01T09:00:00.000Z",
  }, now), false);
  assert.equal(cleanup.canFounderPurgeDelivery({
    status: "searching",
    riderId: "rider-1",
    createdAt: "2026-07-01T09:00:00.000Z",
  }, now), false);
  assert.equal(cleanup.canFounderPurgeDelivery({
    status: "broadcast",
    disputeOpen: true,
    createdAt: "2026-07-01T09:00:00.000Z",
  }, now), false);
  assert.equal(cleanup.canFounderPurgeDelivery({
    status: "completed",
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

test("Founder purge patch expires delivery and releases queue visibility", () => {
  const patch = cleanup.founderPurgePatch({
    founderUid: "founder-1",
    reason: "Clear stale Founder E2E delivery before certification.",
    now: new Date("2026-07-08T09:00:00.000Z"),
  });

  assert.equal(patch.status, "expired");
  assert.equal(patch.matchingStatus, "expired");
  assert.equal(patch.dispatchStatus, "expired");
  assert.equal(patch.broadcastBlocked, true);
  assert.equal(patch.active, false);
  assert.equal(patch.removedFromActiveQueues, true);
  assert.equal(patch.founderPipelinePurged, true);
  assert.equal(patch.founderPipelinePurgedBy, "founder-1");
});

test("Founder purge callable is exported and Founder-authorized", () => {
  const source = require("node:fs").readFileSync(require("node:path").join(__dirname, "delivery-cleanup.js"), "utf8");
  const index = require("node:fs").readFileSync(require("node:path").join(__dirname, "index.js"), "utf8");

  assert.match(source, /function purgeFounderTestPipeline\(\)/);
  assert.match(source, /assertFounder\(context\)/);
  assert.match(source, /founderAuthorityAudit/);
  assert.match(source, /adminAuditLogs/);
  assert.match(index, /exports\.purgeFounderTestPipeline = deliveryCleanup\.purgeFounderTestPipeline\(\)/);
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
