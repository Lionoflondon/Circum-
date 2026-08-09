/* eslint-disable max-len */
"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {getNearbyRequestsHandler} = require("./get-avaliable-requests")._private;

const now = Date.now();
const eligibleRider = {
  dispatchEligible: true,
  approvalStatus: "approved",
  verificationStatus: "verified",
  onboardingStatus: "approved",
  documentsVerified: true,
  vehicleVerified: true,
  accountStatus: "active",
  vehicleType: "car",
};
const healthyPresence = {
  riderId: "rider-1",
  isOnline: true,
  availabilityStatus: "available",
  busy: false,
  dispatchEligible: true,
  lastHeartbeatAt: now - 1000,
  gpsStatus: "active",
  currentLocation: {
    latitude: 51.5,
    longitude: -0.12,
    accuracyMeters: 10,
    updatedAt: now - 1000,
  },
};

function snapshot(exists, value = {}) {
  return {exists, data: () => value};
}

function fakeDb(records = {}) {
  return {
    collection(name) {
      return {
        doc(id) {
          return {
            get: async () => records[name] && records[name][id] ?
              snapshot(true, records[name][id]) : snapshot(false),
          };
        },
      };
    },
  };
}

function dependencies(records, candidateDocs = []) {
  return {
    db: fakeDb(records),
    assignedRiderJobDocs: async () => [],
    candidateRequestDocs: async () => candidateDocs,
  };
}

test("anonymous Website Rider projection request is denied", async () => {
  await assert.rejects(
      getNearbyRequestsHandler({}, {}, dependencies({})),
      (error) => error.code === "unauthenticated",
  );
});

test("authenticated customer without a Rider account is denied", async () => {
  await assert.rejects(
      getNearbyRequestsHandler({}, {auth: {uid: "customer-1"}}, dependencies({})),
      (error) => error.code === "permission-denied",
  );
});

test("eligible Rider is allowed to use the secure projection", async () => {
  const result = await getNearbyRequestsHandler({}, {auth: {uid: "rider-1"}}, dependencies({
    riders: {"rider-1": eligibleRider},
    riderProfiles: {"rider-1": eligibleRider},
    riderPresence: {"rider-1": healthyPresence},
  }));
  assert.deepEqual(result, {nearestRequests: [], activeJobs: [], completedJobs: []});
});

test("unapproved Rider is denied", async () => {
  await assert.rejects(
      getNearbyRequestsHandler({}, {auth: {uid: "rider-1"}}, dependencies({
        riders: {"rider-1": {...eligibleRider, approvalStatus: "pending"}},
        riderProfiles: {"rider-1": {...eligibleRider, approvalStatus: "pending"}},
        riderPresence: {"rider-1": healthyPresence},
      })),
      (error) => error.code === "permission-denied",
  );
});

for (const [name, presencePatch] of [
  ["offline Rider", {isOnline: false}],
  ["stale-heartbeat Rider", {lastHeartbeatAt: now - 300000}],
  ["busy Rider", {busy: true}],
]) {
  test(`${name} receives no offers`, async () => {
    let candidateScanCalled = false;
    const deps = dependencies({
      riders: {"rider-1": eligibleRider},
      riderProfiles: {"rider-1": eligibleRider},
      riderPresence: {"rider-1": {...healthyPresence, ...presencePatch}},
    });
    deps.candidateRequestDocs = async () => {
      candidateScanCalled = true;
      return [];
    };
    const result = await getNearbyRequestsHandler({}, {auth: {uid: "rider-1"}}, deps);
    assert.deepEqual(result.nearestRequests, []);
    assert.equal(candidateScanCalled, false);
  });
}
