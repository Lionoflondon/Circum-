/* eslint-disable max-len */
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
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
    currentLocation: {
      latitude: 51.5072,
      longitude: -0.1276,
      accuracyMeters: 18,
      updatedAt: Date.now(),
    },
    gpsStatus: "active",
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
    currentLocation: {
      latitude: 51.5072,
      longitude: -0.1276,
      accuracyMeters: 18,
      updatedAt: Date.now(),
    },
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

test("active founder test designation bypasses approval but not live presence", () => {
  const profile = {
    onboardingStatus: "in_progress",
    vehicleStatus: "pending",
    founderTestAccount: {
      active: true,
      accountType: "internal_tester",
      waivers: ["dispatch_eligibility"],
    },
  };
  const presence = {
    isOnline: true,
    availabilityStatus: "available",
    busy: false,
    lastHeartbeatAt: Date.now(),
    currentLocation: {
      latitude: 51.5072,
      longitude: -0.1276,
      accuracyMeters: 18,
      updatedAt: Date.now(),
    },
  };
  assert.equal(core.canReceiveDispatch({profile, presence}), true);
  assert.equal(core.canReceiveDispatch({
    profile,
    presence: {...presence, lastHeartbeatAt: 0},
  }), false);
  assert.equal(core.canReceiveDispatch({
    profile: {
      ...profile,
      founderTestAccount: {...profile.founderTestAccount, active: false},
    },
    presence,
  }), false);
});

test("founder test designation never bypasses account suspension", () => {
  assert.equal(core.blockedReason({
    riderStatus: "suspended",
    founderTestAccount: {
      active: true,
      accountType: "internal_tester",
      waivers: ["dispatch_eligibility"],
    },
  }), "Account suspended.");
});

test("blocked profile trigger preserves an authorised founder test rider", () => {
  const source = fs.readFileSync(path.join(__dirname, "rider-presence.js"), "utf8");
  assert.match(source, /loadFounderTestAccount\(db, riderId\)/);
  assert.match(source, /if \(founderTestAccount\) profile\.founderTestAccount = founderTestAccount/);
  assert.match(source, /status: "offline"/);
});

test("goOnline never leaks raw internal failures to riders", () => {
  const source = fs.readFileSync(path.join(__dirname, "rider-presence.js"), "utf8");
  const goOnlineStart = source.indexOf("exports.goOnline = functions.https.onCall");
  const goOfflineStart = source.indexOf("exports.goOffline = functions.https.onCall");
  const goOnlineSource = source.slice(goOnlineStart, goOfflineStart);
  assert.match(goOnlineSource, /catch \(error\)/);
  assert.match(goOnlineSource, /error instanceof functions\.https\.HttpsError/);
  assert.match(goOnlineSource, /goOnline unexpected failure/);
  assert.match(goOnlineSource, /We could not switch you online\. Check your connection and try again\./);
  assert.doesNotMatch(goOnlineSource, /throw new functions\.https\.HttpsError\("internal"/);
});

test("online presence clears stale offline status field", () => {
  const source = fs.readFileSync(path.join(__dirname, "rider-presence.js"), "utf8");

  assert.match(source, /status: status === "offline" \? "offline" : "online"/);
  assert.match(source, /availabilityStatus: status/);
  assert.match(source, /status: "online",\s+availabilityStatus: "connection_lost"/);
});

test("goOnline mirrors dispatch availability into riderProfiles", () => {
  const source = fs.readFileSync(path.join(__dirname, "rider-presence.js"), "utf8");
  const goOnlineStart = source.indexOf("exports.goOnline = functions.https.onCall");
  const goOfflineStart = source.indexOf("exports.goOffline = functions.https.onCall");
  const goOnlineSource = source.slice(goOnlineStart, goOfflineStart);
  assert.match(goOnlineSource, /collection\("riderProfiles"\)\.doc\(riderId\)/);
  assert.match(goOnlineSource, /status: "online"/);
  assert.match(goOnlineSource, /availabilityStatus: "available"/);
  assert.match(goOnlineSource, /dispatchEligible: patch\.dispatchEligible === true/);
});

test("heartbeat keeps riderProfiles dispatch state fresh", () => {
  const source = fs.readFileSync(path.join(__dirname, "rider-presence.js"), "utf8");
  const heartbeatStart = source.indexOf("exports.updateRiderPresence = functions.https.onCall");
  const deliveryWriteStart = source.indexOf("exports.onDeliveryPresenceWrite = functions.firestore");
  const heartbeatSource = source.slice(heartbeatStart, deliveryWriteStart);
  assert.match(heartbeatSource, /collection\("riderProfiles"\)\.doc\(riderId\)/);
  assert.match(heartbeatSource, /availabilityStatus: status/);
  assert.match(heartbeatSource, /lastHeartbeatAt: patch\.lastHeartbeatAt/);
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
    currentLocation: {
      latitude: 51.5072,
      longitude: -0.1276,
      accuracyMeters: 18,
      updatedAt: Date.now(),
    },
  };
  assert.equal(core.canReceiveDispatch({profile, presence}), false);
});

test("dispatch requires fresh accurate GPS", () => {
  const profile = {
    onboardingStatus: "approved",
    vehicleStatus: "approved",
  };
  const base = {
    isOnline: true,
    availabilityStatus: "available",
    busy: false,
    lastHeartbeatAt: Date.now(),
  };
  assert.equal(core.canReceiveDispatch({profile, presence: base}), false);
  assert.equal(core.canReceiveDispatch({
    profile,
    presence: {
      ...base,
      currentLocation: {
        latitude: 51.5072,
        longitude: -0.1276,
        accuracyMeters: 20,
        updatedAt: Date.now() - core.STALE_LOCATION_MS - 1,
      },
    },
  }), false);
  assert.equal(core.canReceiveDispatch({
    profile,
    presence: {
      ...base,
      currentLocation: {
        latitude: 51.5072,
        longitude: -0.1276,
        accuracyMeters: core.MAX_DISPATCH_ACCURACY_METERS + 1,
        updatedAt: Date.now(),
      },
    },
  }), false);
  assert.equal(core.canReceiveDispatch({
    profile,
    presence: {
      ...base,
      gpsStatus: "mocked",
      currentLocation: {
        latitude: 51.5072,
        longitude: -0.1276,
        accuracyMeters: 20,
        updatedAt: Date.now(),
      },
    },
  }), false);
  assert.equal(core.canReceiveDispatch({
    profile,
    presence: {
      ...base,
      gpsStatus: "active",
      currentLocation: {
        latitude: 51.5072,
        longitude: -0.1276,
        accuracyMeters: 20,
        updatedAt: Date.now(),
      },
    },
  }), true);
});

test("GPS health returns an explicit rejection reason for each invalid input", () => {
  const now = Date.now();
  const cases = [
    [{}, "NON_FINITE_COORDINATES"],
    [{currentLocation: {latitude: 51.5, longitude: -0.1, accuracyMeters: 0, updatedAt: now}}, "ZERO_ACCURACY"],
    [{currentLocation: {latitude: 51.5, longitude: -0.1, accuracyMeters: 101, updatedAt: now}}, "LOW_ACCURACY"],
    [{currentLocation: {latitude: 51.5, longitude: -0.1, accuracyMeters: 10, updatedAt: now - core.STALE_LOCATION_MS - 1}}, "STALE_LOCATION"],
  ];
  for (const [presence, reason] of cases) {
    const result = core.gpsHealthResult({presence, now});
    assert.equal(result.eligible, false);
    assert.equal(result.reason, reason);
  }
});

test("GPS health exposes the accepted coordinates and age", () => {
  const now = Date.now();
  const result = core.gpsHealthResult({
    now,
    presence: {
      currentLocation: {
        latitude: 51.5072,
        longitude: -0.1276,
        accuracyMeters: 18,
        updatedAt: now - 500,
      },
    },
  });
  assert.equal(result.eligible, true);
  assert.equal(result.reason, "OK");
  assert.equal(result.latitude, 51.5072);
  assert.equal(result.longitude, -0.1276);
  assert.equal(result.accuracy, 18);
  assert.equal(result.ageMs, 500);
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
  assert.equal(
      core.nextPresenceOnDelivery({
        before: {status: "recoverable_incomplete", riderId: "rider-1"},
        after: {status: "archived_stale", riderId: "rider-1"},
        riderId: "rider-1",
      }),
      "available",
  );
});
