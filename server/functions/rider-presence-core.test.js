const test = require("node:test");
const assert = require("node:assert/strict");
const core = require("./rider-presence-core");

test("approved rider receives dispatch only when online and available", () => {
  const profile = {
    onboardingStatus: "approved",
    vehicleStatus: "approved",
  };
  const presence = {
    isOnline: true,
    availabilityStatus: "available",
    busy: false,
    lastHeartbeatAt: Date.now(),
  };
  assert.equal(core.canGoOnline(profile), true);
  assert.equal(core.canReceiveDispatch({profile, presence}), true);
});

test("unverified vehicle blocks online and dispatch", () => {
  const profile = {
    onboardingStatus: "approved",
    vehicleStatus: "pending",
  };
  const presence = {
    isOnline: true,
    availabilityStatus: "available",
    lastHeartbeatAt: Date.now(),
  };
  assert.equal(core.canGoOnline(profile), false);
  assert.equal(core.blockedReason(profile), "Vehicle verification required.");
  assert.equal(core.canReceiveDispatch({profile, presence}), false);
});

test("founder claim bypasses readiness while normal rider remains blocked", () => {
  const incomplete = {onboardingStatus: "in_progress", vehicleStatus: "pending"};
  assert.equal(core.blockedReasonForAccess(incomplete, true), "");
  assert.equal(core.blockedReasonForAccess(incomplete, false), "Rider approval required.");
});

test("stale heartbeat blocks dispatch", () => {
  const profile = {
    onboardingStatus: "approved",
    vehicleStatus: "approved",
  };
  const presence = {
    isOnline: true,
    availabilityStatus: "available",
    busy: false,
    lastHeartbeatAt: Date.now() - core.STALE_HEARTBEAT_MS - 1,
  };
  assert.equal(core.canReceiveDispatch({profile, presence}), false);
});

test("delivery write marks rider busy, then available", () => {
  assert.equal(
      core.nextPresenceOnDelivery({
        before: {status: "requested"},
        after: {status: "accepted", riderId: "rider-1"},
        riderId: "rider-1",
      }),
      "busy",
  );
  assert.equal(
      core.nextPresenceOnDelivery({
        before: {status: "navigating_to_dropoff", riderId: "rider-1"},
        after: {status: "delivered", riderId: "rider-1"},
        riderId: "rider-1",
      }),
      "available",
  );
});
