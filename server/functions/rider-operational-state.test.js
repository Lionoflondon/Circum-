/* eslint-disable max-len */
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const core = require("./rider-presence-core");

function healthy(now = 1000000) {
  return {onlineIntent: true, isOnline: true, availabilityStatus: "available", connectionStatus: "connected", busy: false, lastHeartbeatAt: now, currentLocation: {latitude: 51.5, longitude: -0.1, accuracyMeters: 10, updatedAt: now}};
}

const ready = {approvalStatus: "approved", verificationStatus: "approved", vehicleApproved: true};

test("stress: ten thousand identical recalculations settle without a semantic patch", () => {
  const now = 1000000;
  const desired = core.computeRiderOperationalState({profile: ready, presence: healthy(now), now});
  const stored = {...healthy(now), ...desired};
  for (let i = 0; i < 10000; i++) assert.deepEqual(core.semanticPatch(stored, desired), {});
});

test("concurrent calculations are deterministic and founder-isolated", async () => {
  const now = 1000000;
  const results = await Promise.all(Array.from({length: 200}, () => Promise.resolve(core.computeRiderOperationalState({profile: ready, presence: healthy(now), now}))));
  for (const result of results) assert.deepEqual(result, results[0]);
  const presenceSource = fs.readFileSync(path.join(__dirname, "rider-presence.js"), "utf8");
  assert.doesNotMatch(presenceSource, /awardFounding|awardRecognition|foundingRider/);
});

test("online readiness, offline, stale GPS and terminal policies remain distinct", () => {
  const now = 1000000;
  assert.equal(core.computeRiderOperationalState({profile: ready, presence: healthy(now), now}).dispatchEligible, true);
  assert.equal(core.computeRiderOperationalState({profile: ready, presence: {...healthy(now), onlineIntent: false, isOnline: false}, now}).dispatchReason, "offline");
  assert.equal(core.computeRiderOperationalState({profile: ready, presence: {...healthy(now), lastHeartbeatAt: now - core.STALE_HEARTBEAT_MS - 1}, now}).dispatchReason, "presence_stale");
  assert.equal(core.computeRiderOperationalState({profile: {...ready, isClosed: true}, presence: healthy(now), now}).dispatchReason, "account_blocked");
});
