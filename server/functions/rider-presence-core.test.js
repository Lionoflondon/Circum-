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
    currentLocation: {latitude: 51.5, longitude: -0.1, updatedAt: Date.now()},
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
    currentLocation: {latitude: 51.5, longitude: -0.1, updatedAt: Date.now()},
  };
  assert.equal(core.canGoOnline(profile), false);
  assert.equal(core.blockedReason(profile), "Vehicle verification required.");
  assert.equal(core.canReceiveDispatch({profile, presence}), false);
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
    currentLocation: {latitude: 51.5, longitude: -0.1, updatedAt: Date.now()},
  };
  assert.equal(core.canReceiveDispatch({profile, presence}), false);
  assert.equal(core.connectionStatusForPresence({presence}), "lost");
  assert.equal(presence.isOnline, true);
});

test("stale location blocks dispatch without making rider offline", () => {
  const now = Date.now();
  const profile = {
    onboardingStatus: "approved",
    vehicleStatus: "approved",
  };
  const presence = {
    isOnline: true,
    availabilityStatus: "available",
    busy: false,
    lastHeartbeatAt: now,
    currentLocation: {
      latitude: 51.5,
      longitude: -0.1,
      updatedAt: now - core.STALE_LOCATION_MS - 1,
    },
  };
  assert.equal(core.canReceiveDispatch({profile, presence, now}), false);
  assert.equal(core.connectionStatusForPresence({presence, now}), "connected");
  assert.equal(presence.isOnline, true);
});

test("connection lost status blocks dispatch while preserving online intent", () => {
  const now = Date.now();
  const profile = {
    onboardingStatus: "approved",
    vehicleStatus: "approved",
  };
  const presence = {
    isOnline: true,
    availabilityStatus: "available",
    connectionStatus: "lost",
    busy: false,
    lastHeartbeatAt: now,
    currentLocation: {latitude: 51.5, longitude: -0.1, updatedAt: now},
  };
  assert.equal(core.canReceiveDispatch({profile, presence, now}), false);
  assert.equal(presence.isOnline, true);
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
