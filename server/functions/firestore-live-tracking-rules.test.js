/* eslint-disable max-len, require-jsdoc */
const test = require("node:test");
const fs = require("node:fs");
const path = require("node:path");
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require("@firebase/rules-unit-testing");
const {
  doc,
  getDoc,
  setDoc,
  writeBatch,
  serverTimestamp,
  Timestamp,
  GeoPoint,
} = require("firebase/firestore");

const projectId = "circum-rules-live-tracking-test";
let testEnv;

function movingPayload(deliveryId, riderId, overrides = {}) {
  return {
    riderId,
    activeDeliveryId: deliveryId,
    deliveryId,
    latitude: 51.5,
    longitude: -0.1,
    accuracy: 12,
    heading: 90,
    speed: 4,
    status: "navigating_to_pickup",
    trackingStatus: "live",
    deliveryState: "navigating_to_pickup",
    freshness: "fresh",
    clientRecordedAt: Timestamp.fromDate(new Date("2026-07-17T12:00:00Z")),
    updatedAt: serverTimestamp(),
    freshnessUpdatedAt: serverTimestamp(),
    riderLiveLocation: {
      geopoint: new GeoPoint(51.5, -0.1),
      latitude: 51.5,
      longitude: -0.1,
      accuracy: 12,
      heading: 90,
      speed: 4,
      freshness: "fresh",
      deliveryState: "navigating_to_pickup",
      updatedAt: serverTimestamp(),
    },
    ...overrides,
  };
}

function activePayload(deliveryId, riderId, overrides = {}) {
  const moving = movingPayload(deliveryId, riderId);
  return {
    deliveryId,
    riderId,
    status: moving.status,
    deliveryState: moving.deliveryState,
    trackingStatus: "live",
    freshness: "fresh",
    riderLiveLocation: moving.riderLiveLocation,
    updatedAt: serverTimestamp(),
    freshnessUpdatedAt: serverTimestamp(),
    ...overrides,
  };
}

function stoppedPayload(deliveryId, riderId, overrides = {}) {
  return {
    riderId,
    activeDeliveryId: deliveryId,
    deliveryId,
    trackingStatus: "stopped",
    status: "completed",
    deliveryState: "completed",
    freshness: "stopped",
    updatedAt: serverTimestamp(),
    freshnessUpdatedAt: serverTimestamp(),
    ...overrides,
  };
}

async function seedDelivery(deliveryId, data = {}) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "deliveryRequests", deliveryId), {
      senderId: "sender-1",
      riderId: "rider-1",
      status: "accepted",
      deliveryStatus: "accepted",
      deliveryStage: "accepted",
      ...data,
    });
  });
}

async function writeTrackingBatch(db, deliveryId, riderId, tracking, active) {
  const batch = writeBatch(db);
  batch.set(doc(db, "deliveryRequests", deliveryId, "tracking", "liveLocation"), tracking, {merge: true});
  batch.set(doc(db, "activeDeliveries", deliveryId), active, {merge: true});
  return batch.commit();
}

test.before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId,
    firestore: {
      rules: fs.readFileSync(path.join(__dirname, "..", "..", "firestore.rules"), "utf8"),
    },
  });
});

test.after(async () => {
  await testEnv.cleanup();
});

test.beforeEach(async () => {
  await testEnv.clearFirestore();
});

test("assigned Rider can write exact current live tracking batch", async () => {
  const deliveryId = "delivery-1";
  await seedDelivery(deliveryId);
  const db = testEnv.authenticatedContext("rider-1").firestore();
  await assertSucceeds(writeTrackingBatch(
      db,
      deliveryId,
      "rider-1",
      movingPayload(deliveryId, "rider-1"),
      activePayload(deliveryId, "rider-1"),
  ));
});

test("assigned Rider can publish the current stopped tracking batch before terminal backend transition", async () => {
  const deliveryId = "delivery-stop";
  await seedDelivery(deliveryId, {status: "navigating_to_dropoff"});
  const db = testEnv.authenticatedContext("rider-1").firestore();
  const payload = stoppedPayload(deliveryId, "rider-1");
  await assertSucceeds(writeTrackingBatch(db, deliveryId, "rider-1", payload, payload));
});

test("unassigned Rider Sender and wrong embedded IDs cannot write live tracking", async () => {
  const deliveryId = "delivery-denied";
  await seedDelivery(deliveryId);

  const wrongRiderDb = testEnv.authenticatedContext("rider-2").firestore();
  await assertFails(writeTrackingBatch(
      wrongRiderDb,
      deliveryId,
      "rider-2",
      movingPayload(deliveryId, "rider-2"),
      activePayload(deliveryId, "rider-2"),
  ));

  const senderDb = testEnv.authenticatedContext("sender-1").firestore();
  await assertFails(writeTrackingBatch(
      senderDb,
      deliveryId,
      "sender-1",
      movingPayload(deliveryId, "sender-1"),
      activePayload(deliveryId, "sender-1"),
  ));

  const assignedDb = testEnv.authenticatedContext("rider-1").firestore();
  await assertFails(writeTrackingBatch(
      assignedDb,
      deliveryId,
      "rider-1",
      movingPayload(deliveryId, "rider-1", {deliveryId: "other-delivery"}),
      activePayload(deliveryId, "rider-1"),
  ));
});

test("unexpected financial lifecycle or settlement fields are denied in tracking mirrors", async () => {
  const deliveryId = "delivery-extra";
  await seedDelivery(deliveryId);
  const db = testEnv.authenticatedContext("rider-1").firestore();
  await assertFails(writeTrackingBatch(
      db,
      deliveryId,
      "rider-1",
      movingPayload(deliveryId, "rider-1", {paymentStatus: "paid"}),
      activePayload(deliveryId, "rider-1"),
  ));
  await assertFails(writeTrackingBatch(
      db,
      deliveryId,
      "rider-1",
      movingPayload(deliveryId, "rider-1"),
      activePayload(deliveryId, "rider-1", {finalAmount: 1}),
  ));
});

test("client tracking writes are denied after terminal backend state", async () => {
  const deliveryId = "delivery-terminal";
  await seedDelivery(deliveryId, {
    status: "completed",
    deliveryStatus: "completed",
    deliveryStage: "completed",
  });
  const db = testEnv.authenticatedContext("rider-1").firestore();
  await assertFails(writeTrackingBatch(
      db,
      deliveryId,
      "rider-1",
      movingPayload(deliveryId, "rider-1"),
      activePayload(deliveryId, "rider-1"),
  ));
});

test("Rider earnings remain readable by owner but never client writable", async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "riderEarnings", "rider-1"), {
      riderId: "rider-1",
      balance: 42,
    });
  });
  const riderDb = testEnv.authenticatedContext("rider-1").firestore();
  await assertSucceeds(getDoc(doc(riderDb, "riderEarnings", "rider-1")));
  await assertFails(getDoc(doc(riderDb, "riderEarnings", "rider-2")));
  await assertFails(setDoc(doc(riderDb, "riderEarnings", "rider-1"), {
    riderId: "rider-1",
    balance: 999999,
  }, {merge: true}));
  await assertFails(setDoc(doc(riderDb, "riderEarnings", "new-rider"), {
    riderId: "new-rider",
    balance: 1,
  }));
});

test("Rider earnings reconciliation audit records are admin readable and never client writable", async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "riderEarningsReconciliations", "rec-1"), {
      riderId: "rider-1",
      status: "review_required",
    });
  });
  const riderDb = testEnv.authenticatedContext("rider-1").firestore();
  const adminDb = testEnv.authenticatedContext("admin-1", {
    roles: ["finance_admin"],
  }).firestore();
  await assertFails(getDoc(doc(riderDb, "riderEarningsReconciliations", "rec-1")));
  await assertSucceeds(getDoc(doc(adminDb, "riderEarningsReconciliations", "rec-1")));
  await assertFails(setDoc(doc(riderDb, "riderEarningsReconciliations", "rec-2"), {
    riderId: "rider-1",
    status: "reconciled",
  }));
  await assertFails(setDoc(doc(adminDb, "riderEarningsReconciliations", "rec-2"), {
    riderId: "rider-1",
    status: "reconciled",
  }));
});

test("Rider profile self-writes are explicitly allowlisted", async () => {
  const riderDb = testEnv.authenticatedContext("rider-1").firestore();
  await assertSucceeds(setDoc(doc(riderDb, "riders", "rider-1"), {
    uid: "rider-1",
    name: "Rider One",
    email: "rider@example.com",
    phone: "+447700900000",
    status: "offline",
    profileCompletionStatus: "complete",
    onboardingStatus: "profile_complete",
    updatedAt: serverTimestamp(),
  }));
  await assertSucceeds(setDoc(doc(riderDb, "riders", "rider-1"), {
    photoURL: "https://example.com/rider.jpg",
    username: "riderone",
    vehicleType: "bike",
    updatedAt: serverTimestamp(),
  }, {merge: true}));
});

test("Rider profile self-writes cannot alter admin payment or trust authority", async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "riders", "rider-1"), {
      uid: "rider-1",
      name: "Rider One",
      approvalStatus: "pending",
    });
  });
  const riderDb = testEnv.authenticatedContext("rider-1").firestore();
  for (const field of [
    "approvalStatus",
    "verificationStatus",
    "role",
    "roles",
    "driverStatus",
    "riderRank",
    "rank",
    "trustPoints",
    "riderTrustPoints",
    "rating",
    "availableBalance",
    "stripeConnectAccountId",
    "admin",
  ]) {
    await assertFails(setDoc(doc(riderDb, "riders", "rider-1"), {
      [field]: field === "roles" ? ["driver_manager"] : "forged",
      updatedAt: serverTimestamp(),
    }, {merge: true}));
  }
});

test("Rider cannot self-write admin authority on riderProfiles", async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "riderProfiles", "rider-1"), {
      uid: "rider-1",
      name: "Rider One",
      approvalStatus: "pending",
      rank: "agent",
      trustPoints: 0,
    });
  });
  const riderDb = testEnv.authenticatedContext("rider-1").firestore();
  for (const field of [
    "approvalStatus",
    "verificationStatus",
    "role",
    "roles",
    "driverStatus",
    "riderRank",
    "rank",
    "trustPoints",
    "riderTrustPoints",
    "rating",
    "availableBalance",
    "stripeConnectAccountId",
    "admin",
  ]) {
    await assertFails(setDoc(doc(riderDb, "riderProfiles", "rider-1"), {
      [field]: field === "roles" ? ["driver_manager"] : "forged",
      updatedAt: serverTimestamp(),
    }, {merge: true}));
  }
  await assertSucceeds(setDoc(doc(riderDb, "riderProfiles", "rider-1"), {
    phone: "+447700900001",
    vehicleType: "bike",
    updatedAt: serverTimestamp(),
  }, {merge: true}));
});

test("Driver manager can update Rider admin fields", async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "riders", "rider-1"), {
      uid: "rider-1",
      name: "Rider One",
      approvalStatus: "pending",
    });
  });
  const adminDb = testEnv.authenticatedContext("admin-1", {
    roles: ["driver_manager"],
  }).firestore();
  await assertSucceeds(setDoc(doc(adminDb, "riders", "rider-1"), {
    approvalStatus: "approved",
    verificationStatus: "approved",
    driverStatus: "active",
    riderRank: "sentinel",
    trustPoints: 100,
    updatedAt: serverTimestamp(),
  }, {merge: true}));
  await assertSucceeds(setDoc(doc(adminDb, "riderProfiles", "rider-1"), {
    approvalStatus: "approved",
    verificationStatus: "approved",
    driverStatus: "active",
    rank: "sentinel",
    riderRank: "sentinel",
    trustPoints: 100,
    riderTrustPoints: 100,
    updatedAt: serverTimestamp(),
  }, {merge: true}));
});

test("Sender profile self-writes cannot escalate roles", async () => {
  const senderDb = testEnv.authenticatedContext("sender-1").firestore();
  await assertSucceeds(setDoc(doc(senderDb, "users", "sender-1"), {
    uid: "sender-1",
    email: "sender@example.com",
    role: "user",
    userType: "sender",
    updatedAt: serverTimestamp(),
  }));
  await assertFails(setDoc(doc(senderDb, "users", "sender-1"), {
    role: "admin",
    updatedAt: serverTimestamp(),
  }, {merge: true}));
  await assertFails(setDoc(doc(senderDb, "users", "sender-1"), {
    userType: "rider",
    updatedAt: serverTimestamp(),
  }, {merge: true}));
  await assertFails(setDoc(doc(senderDb, "users", "sender-1"), {
    roles: ["super_admin"],
    updatedAt: serverTimestamp(),
  }, {merge: true}));
});

test("Sender and Rider cannot directly mutate authoritative delivery fields", async () => {
  const deliveryId = "delivery-authority";
  await seedDelivery(deliveryId);
  const senderDb = testEnv.authenticatedContext("sender-1").firestore();
  const riderDb = testEnv.authenticatedContext("rider-1").firestore();
  await assertFails(setDoc(doc(senderDb, "deliveryRequests", deliveryId), {
    paymentStatus: "paid",
    stripePaymentIntentId: "pi_fake",
  }, {merge: true}));
  await assertFails(setDoc(doc(senderDb, "deliveryRequests", deliveryId), {
    status: "completed",
    deliveryStage: "completed",
    deliveryStatus: "completed",
  }, {merge: true}));
  await assertFails(setDoc(doc(riderDb, "deliveryRequests", deliveryId), {
    status: "completed",
  }, {merge: true}));
  await assertFails(setDoc(doc(riderDb, "deliveryRequests", deliveryId), {
    trustPointsAwarded: 100,
  }, {merge: true}));
});

test("Sender cannot directly rewrite delivery weight after creation", async () => {
  const deliveryId = "delivery-weight-authority";
  await seedDelivery(deliveryId, {
    senderId: "sender-1",
    userId: "sender-1",
    weightKg: 2,
    finalWeightKg: 2,
    confirmedWeightKg: 2,
  });
  const senderDb = testEnv.authenticatedContext("sender-1").firestore();
  for (const field of ["weightKg", "finalWeightKg", "confirmedWeightKg"]) {
    await assertFails(setDoc(doc(senderDb, "deliveryRequests", deliveryId), {
      [field]: 50,
      updatedAt: serverTimestamp(),
    }, {merge: true}));
  }
  await assertSucceeds(setDoc(doc(senderDb, "deliveryRequests", deliveryId), {
    recipientNotes: "Please use the side entrance.",
    updatedAt: serverTimestamp(),
  }, {merge: true}));
});

test("Sender cannot directly create canonical delivery requests", async () => {
  const senderDb = testEnv.authenticatedContext("sender-1").firestore();
  await assertFails(setDoc(doc(senderDb, "deliveryRequests", "direct-forged-iris"), {
    senderId: "sender-1",
    userId: "sender-1",
    packageDescription: "knife",
    iris: {
      status: "allowed",
      compliance: {status: "allowed"},
      serviceability: {status: "serviceable"},
    },
  }));
  await assertFails(setDoc(doc(senderDb, "deliveryRequests", "direct-no-iris"), {
    senderId: "sender-1",
    userId: "sender-1",
    packageDescription: "book",
  }));
  await assertFails(setDoc(doc(senderDb, "webSenderRequests", "web-forged-iris"), {
    senderId: "sender-1",
    userId: "sender-1",
    packageDescription: "knife",
    iris: {
      status: "allowed",
      compliance: {status: "allowed"},
      serviceability: {status: "serviceable"},
    },
  }));
  await assertSucceeds(setDoc(doc(senderDb, "webSenderRequests", "web-no-iris"), {
    senderId: "sender-1",
    userId: "sender-1",
    packageDescription: "book",
  }));
});

test("Vanguard PIN authority private documents are not client readable or writable", async () => {
  const deliveryId = "delivery-vanguard-private";
  await seedDelivery(deliveryId, {
    vanguardProtocolEnabled: true,
    collectionPinVerified: false,
    deliveryPinVerified: false,
  });
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "deliveryRequestsPrivate", deliveryId), {
      deliveryId,
      senderId: "sender-1",
      riderId: "rider-1",
      collectionPin: "123456",
      deliveryPin: "654321",
      collectionPinAttemptCount: 0,
      deliveryPinAttemptCount: 0,
    });
  });
  const senderDb = testEnv.authenticatedContext("sender-1").firestore();
  const riderDb = testEnv.authenticatedContext("rider-1").firestore();
  await assertSucceeds(getDoc(doc(senderDb, "deliveryRequests", deliveryId)));
  await assertSucceeds(getDoc(doc(riderDb, "deliveryRequests", deliveryId)));
  await assertFails(getDoc(doc(senderDb, "deliveryRequestsPrivate", deliveryId)));
  await assertFails(getDoc(doc(riderDb, "deliveryRequestsPrivate", deliveryId)));
  await assertFails(setDoc(doc(senderDb, "deliveryRequestsPrivate", deliveryId), {
    collectionPin: "111111",
  }, {merge: true}));
  await assertFails(setDoc(doc(riderDb, "deliveryRequestsPrivate", deliveryId), {
    deliveryPinAttemptCount: 0,
  }, {merge: true}));
});
