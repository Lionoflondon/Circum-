/* eslint-disable max-len */
const test = require("node:test");
const assert = require("node:assert/strict");

process.env.FIREBASE_CONFIG = JSON.stringify({projectId: "demo-rider-online-intent"});
process.env.GCLOUD_PROJECT = "demo-rider-online-intent";

const admin = require("firebase-admin");
if (!admin.apps.length) admin.initializeApp({projectId: process.env.GCLOUD_PROJECT});
const db = admin.firestore();
const presenceApi = require("./rider-presence");
const {getOffers} = require("./rider-offers");
const acceptRideRequests = require("./accept-ride-requests");

const now = () => Date.now();
const ctx = (uid) => ({auth: {uid, token: {email: `${uid}@example.test`}}});
const location = () => ({latitude: 51.5, longitude: -0.1, accuracyMeters: 10, permission: "always", gpsStatus: "active", capturedAt: now()});
const approved = {approvalStatus: "approved", verificationStatus: "approved", vehicleApproved: true, vehicleType: "car", vehicleRegistration: "AB12 CDE", onboardingStatus: "approved"};
const runId = `${Date.now()}-${process.pid}`;

async function seedRider(uid, profile = approved) {
  await db.doc(`riders/${uid}`).set({riderId: uid, ...profile});
  await db.doc(`riderProfiles/${uid}`).set({riderId: uid, ...profile});
}

async function assertNoOffers(uid) {
  const result = await getOffers({}, {auth: {uid}});
  assert.deepEqual(result.nearestRequests, []);
  assert.equal(result.eligible, false);
}

test("intent is accepted but offers and acceptance remain denied for every readiness failure", async () => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST, "Firestore emulator required");
  const cases = [
    ["unapproved", {...approved, approvalStatus: "pending", verificationStatus: "pending", onboardingStatus: "pending"}, location(), "approval_required"],
    ["vehicle", {...approved, vehicleApproved: false}, location(), "vehicle_required"],
    ["no-location", approved, null, "location_required"],
    ["unhealthy-gps", approved, {...location(), accuracyMeters: 500}, "gps_unhealthy"],
  ];
  for (const [uid, profile, fix, reason] of cases) {
    await seedRider(uid, profile);
    const result = await presenceApi.goOnline.run(fix ? {location: fix} : {}, ctx(uid));
    assert.equal(result.onlineIntent, true);
    assert.equal(result.dispatchEligible, false);
    assert.equal(result.reason, reason);
    await assertNoOffers(uid);
    await assert.rejects(acceptRideRequests.run({requestId: "missing-offer"}, ctx(uid)), (error) => error.code === "failed-precondition");
  }
});

test("stale presence excludes offers and independently denies acceptance", async () => {
  const uid = `stale-rider-${runId}`;
  await seedRider(uid);
  await db.doc(`riderPresence/${uid}`).set({riderId: uid, onlineIntent: true, isOnline: true, presenceState: "stale", availabilityStatus: "available", connectionStatus: "stale", dispatchEligible: false, lastHeartbeatAt: now() - 180000, currentLocation: location()});
  await assertNoOffers(uid);
  await assert.rejects(acceptRideRequests.run({requestId: "missing-offer"}, ctx(uid)), (error) => error.code === "failed-precondition");
});

test("healthy heartbeat and readiness changes recover eligibility; terminal suspension forces offline", async () => {
  const uid = `recovery-rider-${runId}`;
  await seedRider(uid, {...approved, approvalStatus: "pending", verificationStatus: "pending", vehicleApproved: false});
  await presenceApi.goOnline.run({location: location()}, ctx(uid));
  await db.doc(`riderProfiles/${uid}`).set(approved, {merge: true});
  await db.doc(`riders/${uid}`).set(approved, {merge: true});
  await presenceApi._test.applyRiderOperationalState(uid, "test-readiness", db);
  let stored = (await db.doc(`riderPresence/${uid}`).get()).data();
  assert.equal(stored.onlineIntent, true);
  assert.equal(stored.dispatchEligible, true);

  await db.doc(`riderProfiles/${uid}`).set({accountStatus: "suspended"}, {merge: true});
  await presenceApi._test.applyRiderOperationalState(uid, "test-terminal", db);
  stored = (await db.doc(`riderPresence/${uid}`).get()).data();
  assert.equal(stored.onlineIntent, false);
  assert.equal(stored.isOnline, false);
  assert.equal(stored.dispatchEligible, false);
});

test("fully eligible Rider receives an offer and acceptance revalidates then succeeds", async () => {
  const uid = `eligible-rider-${runId}`;
  const deliveryId = `eligible-delivery-${runId}`;
  await seedRider(uid);
  const online = await presenceApi.goOnline.run({location: location()}, ctx(uid));
  assert.equal(online.dispatchEligible, true);
  await db.doc(`deliveryRequests/${deliveryId}`).set({
    requestId: deliveryId,
    senderId: "sender-1",
    status: "requested",
    matchingStatus: "available",
    dispatchStatus: "requested",
    paymentStatus: "paid",
    packageDescription: "Documents",
    weightKg: 0.3,
    vehicleType: "car",
    pickupPosition: {geopoint: {latitude: 51.5, longitude: -0.1}},
    createdAt: now(),
    offerExpiresAt: now() + 300000,
  });
  const offers = await getOffers({}, {auth: {uid}});
  assert.equal(offers.eligible, true);
  assert.equal(offers.nearestRequests.some((offer) => offer.deliveryId === deliveryId), true);
  const accepted = await acceptRideRequests.run({requestId: deliveryId}, ctx(uid));
  assert.equal(accepted.status, "accepted");
  assert.equal((await db.doc(`deliveryRequests/${deliveryId}`).get()).data().assignedRiderId, uid);
});
