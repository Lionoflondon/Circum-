/* eslint-disable max-len */
"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

const emulator = !!process.env.FIRESTORE_EMULATOR_HOST;

test("double Rider acceptance converges to exactly one backend assignment", {skip: !emulator}, async () => {
  const {db, clear, wrappedAccept} = await lifecycleHarness("double-acceptance");
  await clear();
  await seedDispatchableDelivery(db, "delivery-double-acceptance");
  await seedRider(db, "rider-a");
  await seedRider(db, "rider-b");

  const results = await Promise.allSettled([
    wrappedAccept({requestId: "delivery-double-acceptance"}, authContext("rider-a")),
    wrappedAccept({requestId: "delivery-double-acceptance"}, authContext("rider-b")),
  ]);

  const successes = results.filter((result) => result.status === "fulfilled");
  const failures = results.filter((result) => result.status === "rejected");
  assert.equal(successes.length, 1);
  assert.equal(failures.length, 1);

  const delivery = (await db.collection("deliveryRequests").doc("delivery-double-acceptance").get()).data();
  const winner = successes[0].value.riderId;
  const loser = winner === "rider-a" ? "rider-b" : "rider-a";
  assert.equal(delivery.assignedRiderId, winner);
  assert.equal(delivery.riderId, winner);
  assert.equal(delivery.status, "accepted");
  assert.notEqual(delivery.assignedRiderId, loser);

  await assert.rejects(
      () => wrappedAccept({requestId: "delivery-double-acceptance"}, authContext(loser)),
      /already accepted|already been accepted|already assigned|no longer available/i,
  );
});

test("Sender cancellation racing Rider acceptance leaves one canonical outcome", {skip: !emulator}, async () => {
  const {db, clear, wrappedAccept, wrappedCancel} = await lifecycleHarness("cancel-vs-accept");
  await clear();
  await seedDispatchableDelivery(db, "delivery-cancel-accept");
  await seedRider(db, "rider-a");

  const results = await Promise.allSettled([
    wrappedAccept({requestId: "delivery-cancel-accept"}, authContext("rider-a")),
    wrappedCancel({
      deliveryId: "delivery-cancel-accept",
      idempotencyKey: "cancel-vs-accept",
      reason: "Sender changed plans",
    }, authContext("sender-1")),
  ]);
  assert.equal(results.length, 2);

  const delivery = (await db.collection("deliveryRequests").doc("delivery-cancel-accept").get()).data();
  const accepted = delivery.status === "accepted";
  const cancelled = delivery.status === "cancelled_by_sender";
  assert.equal(accepted || cancelled, true);
  assert.equal(accepted && cancelled, false);
  if (cancelled) {
    assert.notEqual(delivery.dispatchStatus, "accepted");
    assert.equal(delivery.broadcastBlocked, true);
  }
  if (accepted) {
    assert.equal(delivery.assignedRiderId, "rider-a");
    assert.notEqual(delivery.dispatchStatus, "cancelled");
  }
});

test("Sender cancellation is rejected after collection has started", {skip: !emulator}, async () => {
  const {db, clear, wrappedCancel} = await lifecycleHarness("cancel-vs-completion");
  await clear();
  await seedDispatchableDelivery(db, "delivery-cancel-complete", {
    status: "arrived_at_dropoff",
    state: "arrived_at_dropoff",
    deliveryStatus: "arrived_at_dropoff",
    deliveryStage: "arrived_at_dropoff",
    riderId: "rider-a",
    assignedRiderId: "rider-a",
  });

  const result = await wrappedCancel({
    deliveryId: "delivery-cancel-complete",
    idempotencyKey: "cancel-vs-completion",
    reason: "Late sender cancellation",
  }, authContext("sender-1"));
  const delivery = (await db.collection("deliveryRequests").doc("delivery-cancel-complete").get()).data();
  assert.equal(result.success, false);
  assert.equal(delivery.status, "arrived_at_dropoff");
  assert.equal(delivery.cancelledAt, undefined);
});

async function lifecycleHarness(suffix) {
  stubEligibilityModules();
  const admin = require("firebase-admin");
  const functionsTest = require("firebase-functions-test")({
    projectId: `circum-lifecycle-${suffix}`,
  });
  if (!admin.apps.length) {
    admin.initializeApp({projectId: `circum-lifecycle-${suffix}`});
  }
  const db = admin.firestore();
  const acceptRideRequests = require("./accept-ride-requests");
  const deliveryPolicy = require("./delivery-policy");
  return {
    db,
    clear: async () => {
      const collections = await db.listCollections();
      await Promise.all(collections.map((collection) => deleteCollection(collection)));
    },
    wrappedAccept: functionsTest.wrap(acceptRideRequests),
    wrappedCancel: functionsTest.wrap(deliveryPolicy.requestSenderCancellation),
  };
}

function stubEligibilityModules() {
  require.cache[require.resolve("./iris-core")] = {
    exports: {
      isDispatchable: () => true,
      riderCanViewDispatch: () => true,
      riderDispatchEligibilityReason: () => "eligible",
      riderMatchesIris: () => true,
    },
  };
  require.cache[require.resolve("./vehicle-dispatch")] = {
    exports: {
      riderVehicleMatchesRequest: () => true,
    },
  };
  require.cache[require.resolve("./rider-vehicle-snapshot")] = {
    exports: {
      buildRiderVehicleSnapshot: () => ({type: "bike", registration: "TEST"}),
    },
  };
  require.cache[require.resolve("./founder-authority")] = {
    exports: {
      loadFounderTestAccount: async () => null,
    },
  };
  require.cache[require.resolve("./communication-engine")] = {
    exports: {
      emitNotification: async () => ({ok: true}),
    },
  };
}

function authContext(uid) {
  return {auth: {uid}, app: {appId: "test-app"}};
}

async function seedDispatchableDelivery(db, deliveryId, overrides = {}) {
  await db.collection("deliveryRequests").doc(deliveryId).set({
    requestId: deliveryId,
    senderId: "sender-1",
    userId: "sender-1",
    status: "requested",
    state: "requested",
    deliveryStatus: "requested",
    deliveryStage: "requested",
    matchingStatus: "requested",
    dispatchStatus: "requested",
    paymentStatus: "paid",
    price: 18.79,
    ...overrides,
  });
}

async function seedRider(db, riderId) {
  const rider = {
    uid: riderId,
    name: riderId,
    approvalStatus: "approved",
    verificationStatus: "approved",
    dispatchEligible: true,
    accountStatus: "active",
    vehicleType: "bike",
  };
  await db.collection("riders").doc(riderId).set(rider);
  await db.collection("riderProfiles").doc(riderId).set(rider);
}

async function deleteCollection(collectionRef) {
  const snapshot = await collectionRef.limit(100).get();
  await Promise.all(snapshot.docs.map((doc) => doc.ref.delete()));
  if (snapshot.size === 100) {
    await deleteCollection(collectionRef);
  }
}
