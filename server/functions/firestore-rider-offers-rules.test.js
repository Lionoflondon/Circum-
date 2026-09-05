/* eslint-disable max-len, require-jsdoc */
const {test, before, beforeEach, after} = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require("@firebase/rules-unit-testing");
const {
  doc,
  getDoc,
  getDocs,
  collection,
  query,
  where,
  setDoc,
} = require("firebase/firestore");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore, GeoPoint, Timestamp} = require("firebase-admin/firestore");
const {getOffers} = require("./rider-offers");
let app;
let db;
let env;
before(async () => {
  const projectId = "demo-rider-offer-authority";
  env = await initializeTestEnvironment({
    projectId,
    firestore: {
      rules: fs.readFileSync(`${__dirname}/../../firestore.rules`, "utf8"),
    },
  });
  app = initializeApp({projectId});
  db = getFirestore();
});
after(async () => {
  await env.cleanup();
  await deleteApp(app);
});
const ctx = (uid) => ({auth: {uid, token: {}}, app: {appId: "test"}});
const client = (uid) => env.authenticatedContext(uid).firestore();
async function seedRider(uid, patch = {}) {
  const profile = {
    approvalStatus: "approved",
    riderStatus: "active",
    vehicleApproved: true,
    vehicleType: "car",
    ...patch,
  };
  await db.doc(`riderProfiles/${uid}`).set(profile);
  await db.doc(`riders/${uid}`).set(profile);
  await db.doc(`riderPresence/${uid}`).set({
    isOnline: true,
    availabilityStatus: "available",
    dispatchEligible: true,
    lastHeartbeatAt: Date.now(),
    currentLocation: {
      latitude: 51.5,
      longitude: -0.1,
      accuracyMeters: 10,
      updatedAt: Date.now(),
    },
    gpsStatus: "active",
  });
}
beforeEach(async () => {
  await env.clearFirestore();
  await seedRider("a");
  await seedRider("b");
  await db.doc("deliveryRequests/job").set({
    requestId: "job",
    senderId: "sender",
    status: "requested",
    paymentStatus: "paid",
    matchingStatus: "available",
    dispatchStatus: "requested",
    vehicleRequirement: "car",
    packageDescription: "book",
    weight: "1 kg",
    riderEarning: 6,
    pickupPosition: {geopoint: new GeoPoint(51.5, -0.1)},
    pickupDetails: {
      locality: "London",
      address: "Private full address",
      name: "Private Sender",
    },
    dropoffDetails: {locality: "Camden"},
    stripePaymentIntentId: "payment-secret",
    rothAmount: 7,
    giftStorySenderVoiceNoteUrl: "private-voice",
  });
});
test("eligible Rider receives only a server projection and cannot query canonical available jobs", async () => {
  const response = await getOffers({}, ctx("a"), db);
  assert.equal(response.nearestRequests.length, 1);
  const p = response.nearestRequests[0];
  assert.equal(p.riderEarning, 6);
  assert.equal(p.pickupLocality, "London");
  assert.doesNotMatch(
    JSON.stringify(p),
    /payment-secret|private-voice|Private Sender|Private full address|rothAmount|senderId/,
  );
  await assertSucceeds(
    getDoc(doc(client("a"), "riderOfferProjections/a/offers/job")),
  );
  await assertFails(getDoc(doc(client("a"), "deliveryRequests/job")));
  await assertFails(
    getDocs(
      query(
        collection(client("a"), "deliveryRequests"),
        where("status", "==", "requested"),
      ),
    ),
  );
  await assertFails(
    getDoc(doc(client("b"), "riderOfferProjections/a/offers/job")),
  );
  await assertFails(
    getDoc(doc(client("a"), "riderOfferAuthorizations/a/jobs/job")),
  );
  await assertFails(
    setDoc(doc(client("a"), "riderOfferProjections/a/offers/fake"), p),
  );
});
test("wrong vehicle and missing required capability receive no projection", async () => {
  await db.doc("deliveryRequests/job").update({vehicleRequirement: "van"});
  assert.equal((await getOffers({}, ctx("a"), db)).nearestRequests.length, 0);
  await db.doc("deliveryRequests/job").update({vehicleRequirement: "car"});
  await db
    .doc("irisPrivate/job")
    .set({internal: {riderMatching: {requiresTwoPerson: true}}});
  assert.equal((await getOffers({}, ctx("a"), db)).nearestRequests.length, 0);
});
test("offline, stale GPS/presence, suspension and unapproved riders cannot receive offers", async () => {
  for (const mutation of [
    {isOnline: false},
    {lastHeartbeatAt: Date.now() - 180000},
    {dispatchEligible: false},
    {
      currentLocation: {
        latitude: 51.5,
        longitude: -0.1,
        accuracyMeters: 10,
        updatedAt: Date.now() - 180000,
      },
    },
  ]) {
    await seedRider("a");
    await db.doc("riderPresence/a").update(mutation);
    assert.equal((await getOffers({}, ctx("a"), db)).nearestRequests.length, 0);
  }
  for (const mutation of [
    {isSuspended: true},
    {approvalStatus: "pending", riderStatus: "pending", vehicleApproved: false},
  ]) {
    await seedRider("a", mutation);
    assert.equal((await getOffers({}, ctx("a"), db)).nearestRequests.length, 0);
  }
});
test("existing projection loses read permission immediately when eligibility changes", async () => {
  await getOffers({}, ctx("a"), db);
  const p = doc(client("a"), "riderOfferProjections/a/offers/job");
  await assertSucceeds(getDoc(p));
  await db.doc("riderPresence/a").update({isOnline: false});
  await assertFails(getDoc(p));
  await seedRider("a");
  await getOffers({}, ctx("a"), db);
  await db.doc("riderProfiles/a").update({vehicleType: "motorbike"});
  await assertFails(getDoc(p));
  await seedRider("a");
  await getOffers({}, ctx("a"), db);
  await db
    .doc("riderOfferProjections/a/offers/job")
    .update({expiresAt: Timestamp.fromMillis(1)});
  await assertFails(getDoc(p));
});
test("unpaid, unavailable or incompatible active deliveries do not produce offers", async () => {
  await db.doc("deliveryRequests/job").update({paymentStatus: "pending"});
  assert.equal((await getOffers({}, ctx("a"), db)).nearestRequests.length, 0);
  await db.doc("deliveryRequests/job").update({paymentStatus: "paid"});
  await db
    .doc("deliveryRequests/active")
    .set({riderId: "a", status: "accepted"});
  assert.equal((await getOffers({}, ctx("a"), db)).nearestRequests.length, 0);
});
test("two Rider acceptance race has one winner, winner-only chat and immediate loser access revocation", async () => {
  await Promise.all([getOffers({}, ctx("a"), db), getOffers({}, ctx("b"), db)]);
  const accept = require("./accept-ride-requests");
  const outcomes = await Promise.allSettled([
    accept.run({requestId: "job"}, ctx("a")),
    accept.run({requestId: "job"}, ctx("b")),
  ]);
  assert.equal(outcomes.filter((x) => x.status === "fulfilled").length, 1);
  const winner = outcomes[0].status === "fulfilled" ? "a" : "b";
  const loser = winner === "a" ? "b" : "a";
  assert.equal(
    (await db.doc("deliveryRequests/job").get()).data().riderId,
    winner,
  );
  await assertSucceeds(getDoc(doc(client(winner), "deliveryRequests/job")));
  await assertFails(getDoc(doc(client(loser), "deliveryRequests/job")));
  await assertFails(
    getDoc(doc(client(loser), `riderOfferProjections/${loser}/offers/job`)),
  );
  await assertSucceeds(getDoc(doc(client(winner), "chats/job")));
  await assertFails(getDoc(doc(client(loser), "chats/job")));
  assert.equal((await getOffers({}, ctx(loser), db)).nearestRequests.length, 0);
  assert.equal(
    (await db.doc(`riderOfferProjections/${loser}/offers/job`).get()).exists,
    false,
  );
});

test("canonical assignedRiderId-only deliveries remain readable only to that Rider", async () => {
  await db.doc("deliveryRequests/assigned-alias").set({assignedRiderId: "a", status: "accepted", senderId: "sender"});
  await assertSucceeds(getDoc(doc(client("a"), "deliveryRequests/assigned-alias")));
  await assertFails(getDoc(doc(client("b"), "deliveryRequests/assigned-alias")));
});
