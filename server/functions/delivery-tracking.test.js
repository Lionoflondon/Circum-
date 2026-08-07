/* eslint-disable max-len */
"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const deliveryTracking = require("./delivery-tracking")._private;
const deliveryTrackingModule = require("./delivery-tracking");

function fakeFirestore(seed) {
  const documents = new Map(Object.entries(seed));
  const documentRef = (path) => ({
    id: path.split("/").at(-1),
    path,
    collection: (name) => collectionRef(`${path}/${name}`),
  });
  const collectionRef = (path) => ({
    doc: (id) => documentRef(`${path}/${id}`),
    where: () => ({limit: () => ({path: `${path}/__query__`})}),
  });
  const snapshot = (ref) => ({
    id: ref.id,
    exists: documents.has(ref.path),
    data: () => documents.get(ref.path),
  });
  return {
    collection: collectionRef,
    runTransaction: async (callback) => callback({
      get: async (ref) => snapshot(ref),
      set: (ref, value, options = {}) => {
        const current = documents.get(ref.path) || {};
        documents.set(ref.path, options.merge ? {...current, ...value} : value);
      },
      create: (ref, value) => {
        if (documents.has(ref.path)) throw new Error(`Document already exists: ${ref.path}`);
        documents.set(ref.path, value);
      },
    }),
    read: (path) => documents.get(path),
    write: (path, value) => documents.set(path, value),
  };
}

test("collection PIN verification patch updates backend tracking fields", () => {
  const patch = deliveryTracking.patchForTransition({
    action: "verify_collection_pin",
    nextStatus: "pickup_verified",
    riderId: "rider-1",
  });
  assert.equal(patch.status, "pickup_verified");
  assert.equal(patch.collectionPinVerified, true);
  assert.equal(patch.collectionPinVerifiedBy, "rider-1");
  assert.equal(Object.prototype.hasOwnProperty.call(patch, "deliveryPin"), false);
  assert.equal(Object.prototype.hasOwnProperty.call(patch, "collectionPin"), false);
});

test("canonical completion callable is exported separately from general transitions", () => {
  assert.equal(typeof deliveryTrackingModule.completeDelivery, "function");
  assert.equal(typeof deliveryTrackingModule.updateDeliveryTrackingStatus, "function");
  assert.match(
      require("fs").readFileSync(require.resolve("./delivery-tracking"), "utf8"),
      /completeDelivery = functions\.https\.onCall/,
  );
});

test("receiver PIN verification patch delivers without exposing PIN values", () => {
  const patch = deliveryTracking.patchForTransition({
    action: "verify_receiver_pin",
    nextStatus: "delivered",
    riderId: "rider-1",
    pinVerified: true,
  });
  assert.equal(patch.status, "delivered");
  assert.equal(patch.deliveryPinVerified, true);
  assert.equal(patch.deliveryPinVerifiedBy, "rider-1");
  assert.equal(Object.prototype.hasOwnProperty.call(patch, "deliveryPin"), false);
  assert.equal(Object.prototype.hasOwnProperty.call(patch, "receiverPin"), false);
});

test("rider location patch preserves live GPS contract", () => {
  const patch = deliveryTracking.liveLocationPatch({
    latitude: 51.5074,
    longitude: -0.1278,
    heading: 122,
  });
  assert.equal(patch.riderLiveLocation.latitude, 51.5074);
  assert.equal(patch.riderLiveLocation.longitude, -0.1278);
  assert.equal(patch.riderLiveLocation.heading, 122);
  assert.equal(patch.riderLiveLocation.geopoint.latitude, 51.5074);
  assert.equal(patch.riderLiveLocation.geopoint.longitude, -0.1278);
  assert.equal(Object.prototype.hasOwnProperty.call(patch, "locationHistory"), false);
  assert.equal(Object.prototype.hasOwnProperty.call(patch, "riderLocation"), false);
});

test("rider live location writes are throttled for low Firestore cost", () => {
  const now = 60000;
  const previous = {
    riderLiveLocation: {
      latitude: 51.5074,
      longitude: -0.1278,
      heading: 90,
      updatedAt: now - 9000,
    },
  };
  const nearby = deliveryTracking.liveLocationPatch({
    latitude: 51.50745,
    longitude: -0.12785,
    heading: 92,
  });
  assert.equal(
      deliveryTracking.shouldWriteLiveLocation(previous, nearby, now),
      false,
  );

  const moved = deliveryTracking.liveLocationPatch({
    latitude: 51.508,
    longitude: -0.1278,
    heading: 92,
  });
  assert.equal(
      deliveryTracking.shouldWriteLiveLocation(previous, moved, now + 10000),
      true,
  );

  const stationary = deliveryTracking.liveLocationPatch({
    latitude: 51.50741,
    longitude: -0.12781,
    heading: 92,
  });
  assert.equal(
      deliveryTracking.shouldWriteLiveLocation(previous, stationary, now + 31000),
      true,
  );
});

test("live location callable validation normalizes trusted GPS fixes", () => {
  const location = deliveryTracking.validatedLiveLocation({
    latitude: 51.5074,
    longitude: -0.1278,
    accuracyMeters: 18,
    heading: 122,
    speed: 5,
    clientRecordedAt: 12345,
    backgroundCapable: true,
    queueDepth: 2,
  });
  assert.equal(location.latitude, 51.5074);
  assert.equal(location.longitude, -0.1278);
  assert.equal(location.accuracy, 18);
  assert.equal(location.gpsSignalQuality, "high");
  assert.equal(location.backgroundCapable, true);
  assert.equal(location.queueDepth, 2);
});

test("live location callable validation rejects invalid or unreliable fixes", () => {
  assert.throws(
      () => deliveryTracking.validatedLiveLocation({latitude: 200, longitude: 0, accuracyMeters: 10}),
      /valid rider location/,
  );
  assert.throws(
      () => deliveryTracking.validatedLiveLocation({latitude: 51, longitude: 0, accuracyMeters: 300}),
      /GPS accuracy/,
  );
  const mocked = deliveryTracking.validatedLiveLocation({
    latitude: 51,
    longitude: 0,
    accuracyMeters: 10,
    mocked: true,
  });
  assert.equal(mocked.mocked, true);
});

test("PIN lookup uses private Vanguard document fields only", () => {
  assert.equal(deliveryTracking.expectedPin({pickupPin: "123456"}, "verify_collection_pin"), "123456");
  assert.equal(deliveryTracking.expectedPin({
    vanguardProtection: {deliveryPin: "654321"},
  }, "verify_receiver_pin"), "654321");
  assert.equal(deliveryTracking.expectedPin({}, "verify_collection_pin"), "");
});

test("Vanguard PIN actions require private PIN authority", () => {
  assert.equal(deliveryTracking.pinAuthorityRequired(
      {vanguardProtocolEnabled: true},
      "verify_collection_pin",
  ), true);
  assert.equal(deliveryTracking.pinAuthorityRequired(
      {vanguardProtection: {enabled: true}},
      "verify_receiver_pin",
  ), true);
  assert.equal(deliveryTracking.pinAuthorityRequired(
      {vanguardProtocolEnabled: true},
      "navigate_to_pickup",
  ), false);
  assert.equal(deliveryTracking.pinAuthorityRequired(
      {},
      "verify_collection_pin",
  ), false);
});

test("pickup verification policy separates standard and protected deliveries", () => {
  assert.equal(deliveryTracking.pickupVerificationRequired({}), true);
  assert.equal(deliveryTracking.pickupVerificationRequired({vanguardProtocolEnabled: false}), false);
  assert.equal(deliveryTracking.pickupVerificationRequired({verificationRequired: false}), false);
  assert.equal(deliveryTracking.pickupVerificationRequired({verificationRequired: true}), true);
  assert.equal(deliveryTracking.pickupVerificationRequired({
    verificationRequired: false,
    isGift: true,
  }), false);
  assert.equal(deliveryTracking.pickupVerificationRequired({requiresVanguard: true}), true);
  assert.equal(deliveryTracking.pickupVerificationRequired({serviceType: "health_plus"}), true);
  assert.equal(deliveryTracking.pickupVerificationRequired({isGift: true}), true);
});

test("backend-authored IRIS completion policy controls every protected action", () => {
  const ordinary = {
    vanguardProtocolEnabled: false,
    iris: {verification: {
      recipientPinRequired: false,
      photoEvidenceRequired: false,
      handoverEvidenceRequired: false,
    }},
  };
  assert.deepEqual(deliveryTracking.effectiveCompletionPolicy(ordinary), {
    pickupVerificationRequired: false,
    receiverVerificationRequired: false,
    handoverEvidenceRequired: false,
    authoritative: true,
  });

  const protectedDelivery = {
    iris: {verification: {
      pickupVerificationRequired: true,
      recipientPinRequired: true,
      handoverEvidenceRequired: true,
    }},
  };
  assert.deepEqual(deliveryTracking.effectiveCompletionPolicy(protectedDelivery), {
    pickupVerificationRequired: true,
    receiverVerificationRequired: true,
    handoverEvidenceRequired: true,
    authoritative: true,
  });
});

test("product matrix composes base policy with Vanguard monotonically", () => {
  const ordinary = {
    vanguardProtocolEnabled: false,
    iris: {verification: {
      pickupVerificationRequired: false,
      recipientPinRequired: false,
      handoverEvidenceRequired: false,
    }},
  };
  const matrix = [
    ["Standard", ordinary, false, false, false],
    ["Standard + Vanguard", {...ordinary, requiresVanguard: true}, true, true, true],
    ["Business", {...ordinary, serviceType: "business"}, false, false, false],
    ["Business + Vanguard", {...ordinary, serviceType: "business", requiresVanguard: true}, true, true, true],
    ["Health+", {...ordinary, serviceType: "health_plus"}, false, false, false],
    ["Health+ + Vanguard", {...ordinary, serviceType: "health_plus", requiresVanguard: true}, true, true, true],
    ["Gift", {...ordinary, serviceType: "gift"}, false, false, false],
    ["Gift + Vanguard", {...ordinary, serviceType: "gift", requiresVanguard: true}, true, true, true],
  ];
  for (const [label, delivery, pickup, receiver, evidence] of matrix) {
    assert.deepEqual(deliveryTracking.effectiveCompletionPolicy(delivery), {
      pickupVerificationRequired: pickup,
      receiverVerificationRequired: receiver,
      handoverEvidenceRequired: evidence,
      authoritative: true,
    }, label);
  }
});

test("Vanguard cannot be weakened by client-shaped false policy fields", () => {
  const policy = deliveryTracking.effectiveCompletionPolicy({
    requiresVanguard: true,
    iris: {verification: {
      pickupVerificationRequired: false,
      recipientPinRequired: false,
      handoverEvidenceRequired: false,
    }},
  });
  assert.deepEqual(policy, {
    pickupVerificationRequired: true,
    receiverVerificationRequired: true,
    handoverEvidenceRequired: true,
    authoritative: true,
  });
});

test("ambiguous delivery policy fails closed", () => {
  assert.equal(deliveryTracking.effectiveCompletionPolicy({}).pickupVerificationRequired, true);
  assert.equal(deliveryTracking.effectiveCompletionPolicy({}).receiverVerificationRequired, true);
  assert.equal(deliveryTracking.effectiveCompletionPolicy({}).handoverEvidenceRequired, true);
});

test("authoritative handler policy permits only standard direct collection", () => {
  assert.equal(deliveryTracking.canApplyDeliveryTransition(
      {vanguardProtocolEnabled: false}, "arrived_at_pickup", "collected", "confirm_collected",
  ), true);
  assert.equal(deliveryTracking.canApplyDeliveryTransition(
      {}, "arrived_at_pickup", "collected", "confirm_collected",
  ), false);
  assert.equal(deliveryTracking.canApplyDeliveryTransition(
      {verificationRequired: true}, "arrived_at_pickup", "collected", "confirm_collected",
  ), false);
  assert.equal(deliveryTracking.canApplyDeliveryTransition(
      {requiresVanguard: true}, "arrived_at_pickup", "collected", "confirm_collected",
  ), false);
  assert.equal(deliveryTracking.canApplyDeliveryTransition(
      {}, "arrived_at_pickup", "delivered", "complete_delivery",
  ), false);
});

test("ordinary completion is PIN-less while protected completion remains gated", () => {
  assert.equal(deliveryTracking.deliveryPinRequired({vanguardProtocolEnabled: false}), false);
  assert.equal(deliveryTracking.deliveryPinRequired({pinRequired: true}), true);
  assert.equal(deliveryTracking.deliveryPinRequired({requiresVanguard: true}), true);
  assert.equal(deliveryTracking.deliveryPinRequired({serviceType: "health_plus"}), true);
  assert.equal(deliveryTracking.canApplyDeliveryTransition(
      {vanguardProtocolEnabled: false}, "arrived_at_dropoff", "delivered", "complete_delivery",
  ), true);
  assert.equal(deliveryTracking.canApplyDeliveryTransition(
      {requiresVanguard: true}, "arrived_at_dropoff", "delivered", "complete_delivery",
  ), false);
});

test("confirm_collected persists the canonical standard pickup transition", async () => {
  const db = fakeFirestore({
    "deliveryRequests/delivery-1": {
      requestId: "delivery-1",
      riderId: "rider-1",
      status: "arrived_at_pickup",
      vanguardProtocolEnabled: false,
    },
    "riders/rider-1": {accountState: "approved"},
  });

  const result = await deliveryTracking.updateDeliveryTrackingStatusHandler(
      {deliveryId: "delivery-1", action: "confirm_collected"},
      {auth: {uid: "rider-1", token: {}}},
      db,
  );

  assert.equal(result.status, "collected");
  assert.equal(result.senderTrackingState, "pickup_complete");
  assert.equal(db.read("deliveryRequests/delivery-1").status, "collected");
  assert.equal(db.read("deliveryRequests/delivery-1").deliveryStatus, "collected");
  assert.equal(db.read("deliveryRequests/delivery-1").deliveryStage, "collected");
  assert.equal(db.read("deliveryRequests/delivery-1").lastRiderAction, "confirm_collected");
  assert.ok(db.read("deliveryRequests/delivery-1").collectedAt);
});

test("confirm_collected cannot bypass protected pickup verification", async () => {
  const db = fakeFirestore({
    "deliveryRequests/delivery-1": {
      requestId: "delivery-1",
      riderId: "rider-1",
      status: "arrived_at_pickup",
      verificationRequired: true,
    },
    "riders/rider-1": {accountState: "approved"},
  });

  await assert.rejects(
      deliveryTracking.updateDeliveryTrackingStatusHandler(
          {deliveryId: "delivery-1", action: "confirm_collected"},
          {auth: {uid: "rider-1", token: {}}},
          db,
      ),
      /Cannot move delivery from arrived_at_pickup to collected/,
  );
  assert.equal(db.read("deliveryRequests/delivery-1").status, "arrived_at_pickup");
});

test("real tracking handler completes the standard lifecycle without PIN actions", async () => {
  const db = fakeFirestore({
    "deliveryRequests/delivery-1": {
      requestId: "delivery-1",
      riderId: "rider-1",
      senderId: "sender-1",
      status: "requested",
      riderEarning: 8.5,
      vanguardProtocolEnabled: false,
    },
    "riders/rider-1": {accountState: "approved"},
    "deliveryEvidence/delivery-1": {
      verifiedPhotoCount: 1,
      latestPhotoPath: "deliveryEvidence/delivery-1/handover/photo-1.jpg",
    },
  });
  const deliveryPath = "deliveryRequests/delivery-1";
  db.write(deliveryPath, {...db.read(deliveryPath), status: "accepted"});
  const actions = [
    "start_heading_to_pickup",
    "arrived_at_pickup",
    "confirm_collected",
    "start_delivery",
    "near_dropoff",
    "complete_delivery",
  ];
  const statuses = [];
  const senderStates = [];

  for (const action of actions) {
    const result = action === "complete_delivery" ?
      await deliveryTracking.completeDeliveryHandler(
          {
            deliveryId: "delivery-1",
            evidence: {evidenceId: "evidence-1", recipientConfirmed: true},
          },
          {auth: {uid: "rider-1", token: {}}},
          db,
      ) :
      await deliveryTracking.updateDeliveryTrackingStatusHandler(
          {deliveryId: "delivery-1", action},
          {auth: {uid: "rider-1", token: {}}},
          db,
      );
    statuses.push(result.status);
    senderStates.push(result.senderTrackingState);
  }

  assert.deepEqual(statuses, [
    "navigating_to_pickup",
    "arrived_at_pickup",
    "collected",
    "navigating_to_dropoff",
    "arrived_at_dropoff",
    "delivered",
  ]);
  assert.deepEqual(senderStates, [
    "rider_en_route_to_pickup",
    "rider_arrived_at_pickup",
    "pickup_complete",
    "in_transit",
    "rider_arriving_at_dropoff",
    "delivered",
  ]);
  assert.equal(db.read(deliveryPath).status, "delivered");
  assert.equal(db.read(deliveryPath).deliveryStatus, "delivered");
  assert.equal(db.read(deliveryPath).deliveryStage, "delivered");
  assert.equal(db.read(deliveryPath).lastRiderAction, "complete_delivery");
  assert.equal(db.read(deliveryPath).handoverEvidence.recipientConfirmed, true);
  assert.equal(db.read(deliveryPath).pickupEvidence, undefined);
  assert.equal(db.read(deliveryPath).deliveryPinVerified, undefined);
  assert.equal(
      db.read("platformEvents/delivery_completed_delivery-1").eventType,
      "DeliveryCompleted",
  );
});

test("canonical completion rejects a missing PIN for protected deliveries", async () => {
  const db = fakeFirestore({
    "deliveryRequests/delivery-1": {
      requestId: "delivery-1",
      riderId: "rider-1",
      status: "arrived_at_dropoff",
      requiresVanguard: true,
    },
    "riders/rider-1": {accountState: "approved"},
    "deliveryEvidence/delivery-1": {verifiedPhotoCount: 1},
  });

  await assert.rejects(
      deliveryTracking.completeDeliveryHandler(
          {deliveryId: "delivery-1", evidence: {evidenceId: "evidence-1"}},
          {auth: {uid: "rider-1", token: {}}},
          db,
      ),
      /Cannot move delivery from arrived_at_dropoff to delivered/,
  );
  assert.equal(db.read("deliveryRequests/delivery-1").status, "arrived_at_dropoff");
});

test("public verification patches never expose or clear PIN secrets", () => {
  const collectionPatch = deliveryTracking.patchForTransition({
    action: "verify_collection_pin",
    nextStatus: "pickup_verified",
    riderId: "rider-1",
  });
  const deliveryPatch = deliveryTracking.patchForTransition({
    action: "verify_receiver_pin",
    nextStatus: "delivered",
    riderId: "rider-1",
    pinVerified: true,
  });
  for (const patch of [collectionPatch, deliveryPatch]) {
    assert.equal(Object.prototype.hasOwnProperty.call(patch, "collectionPin"), false);
    assert.equal(Object.prototype.hasOwnProperty.call(patch, "pickupPin"), false);
    assert.equal(Object.prototype.hasOwnProperty.call(patch, "deliveryPin"), false);
    assert.equal(Object.prototype.hasOwnProperty.call(patch, "receiverPin"), false);
    assert.equal(Object.prototype.hasOwnProperty.call(patch, "dropoffPin"), false);
    assert.equal(Object.prototype.hasOwnProperty.call(patch, "vanguardProtection"), false);
    assert.equal(Object.prototype.hasOwnProperty.call(patch, "collectionPinAttemptCount"), false);
    assert.equal(Object.prototype.hasOwnProperty.call(patch, "deliveryPinAttemptCount"), false);
  }
});

test("blocked rider account states cannot transition deliveries", () => {
  assert.throws(
      () => deliveryTracking.assertRiderOperational({accountState: "frozen"}),
      /cannot perform delivery actions/,
  );
  assert.doesNotThrow(
      () => deliveryTracking.assertRiderOperational({accountState: "approved"}),
  );
});

test("a rider cannot update another rider's delivery", () => {
  assert.throws(
      () => deliveryTracking.assertRiderOwnsDelivery(
          {riderId: "assigned-rider"},
          "different-rider",
      ),
      /Only the assigned rider/,
  );
  assert.doesNotThrow(
      () => deliveryTracking.assertRiderOwnsDelivery(
          {riderId: "assigned-rider"},
          "assigned-rider",
      ),
  );
});

test("required pickup evidence blocks incomplete verification", () => {
  assert.equal(deliveryTracking.evidenceRequirements(
      {verificationRequired: true},
      "verify_collection_pin",
      {photoUrl: "secure-ref", conditionConfirmed: true},
  ).valid, false);
  assert.equal(deliveryTracking.evidenceRequirements(
      {verificationRequired: true},
      "verify_collection_pin",
      {
        photoUrl: "secure-ref",
        conditionConfirmed: true,
        riderDeclarationAccepted: true,
      },
  ).valid, true);
});

test("settlement values reuse canonical earnings and highest trust category", () => {
  assert.deepEqual(deliveryTracking.settlementValues({
    riderEarning: 12.345,
    isScheduled: true,
    requiresVanguard: true,
  }), {amount: 12.35, deliveryAmount: 12.35, tip: 0, waiting: 0, adjustment: 0, trustPoints: 5});
  assert.equal(deliveryTracking.highestTrustAward({isHealthPlus: true, requiresVanguard: true}), 6);
  assert.equal(deliveryTracking.highestTrustAward({isGift: true, isBusiness: true}), 5);
  assert.equal(deliveryTracking.highestTrustAward({}), 1);
});

test("delivered transitions persist the canonical trust award even on retry", () => {
  assert.equal(deliveryTracking.highestTrustAward({requiresVanguard: true}), 4);
  assert.equal(deliveryTracking.settlementValues({requiresVanguard: true}).trustPoints, 4);
});

test("canonical rider rank follows backend trust thresholds", () => {
  assert.equal(deliveryTracking.canonicalRiderRankForTrust(0), "agent");
  assert.equal(deliveryTracking.canonicalRiderRankForTrust(99), "agent");
  assert.equal(deliveryTracking.canonicalRiderRankForTrust(100), "sentinel");
  assert.equal(deliveryTracking.canonicalRiderRankForTrust(300), "warden");
  assert.equal(deliveryTracking.canonicalRiderRankForTrust(700), "knight");
  assert.equal(deliveryTracking.canonicalRiderRankForTrust(1500), "veteran");
});

test("trust award patch writes backend-owned rank unless manually overridden", () => {
  const patch = deliveryTracking.riderTrustRankPatch({trustPoints: 99}, 1);
  assert.equal(patch.riderRank, "sentinel");
  assert.equal(patch.rank, "sentinel");
  assert.equal(patch.rankSource, "trust_points");

  const overridePatch = deliveryTracking.riderTrustRankPatch({
    trustPoints: 0,
    riderRank: "veteran",
    rankOverride: true,
  }, 6);
  assert.equal(Object.prototype.hasOwnProperty.call(overridePatch, "riderRank"), false);
  assert.equal(Object.prototype.hasOwnProperty.call(overridePatch, "rank"), false);
});
