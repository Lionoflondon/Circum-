"use strict";

const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue, Timestamp} = require("firebase-admin/firestore");
const {riderCallable} = require("./rider-app-check");
const {FOUNDER_RIDER_UID} = require("./founder-rider-access");

const PURPOSE = "google_play_review";
const ACCOUNT_TYPE = "demo_account";
const REVIEWER_TTL_MS = 90 * 24 * 60 * 60 * 1000;
const FIXTURE_TTL_MS = 30 * 24 * 60 * 60 * 1000;

function authUid(context) {
  if (!context.auth || !context.auth.uid) {
    throw new functions.https.HttpsError("unauthenticated", "Sign in first.");
  }
  return context.auth.uid;
}

function assertFounder(context) {
  if (authUid(context) !== FOUNDER_RIDER_UID) {
    throw new functions.https.HttpsError("permission-denied", "Founder authority is required.");
  }
}

function assertReviewData(data) {
  if (!data || data.accountType !== ACCOUNT_TYPE || data.purpose !== PURPOSE) {
    throw new functions.https.HttpsError("invalid-argument", "Only Google Play demo review accounts are supported.");
  }
}

async function activeDesignation(db, uid, now = Date.now()) {
  const snap = await db.collection("founderTestAccounts").doc(uid).get();
  if (!snap.exists) return null;
  const value = snap.data() || {};
  const expiresAt = value.expiresAt && value.expiresAt.toMillis ? value.expiresAt.toMillis() : 0;
  if (value.enabled !== true || value.accountType !== ACCOUNT_TYPE || value.purpose !== PURPOSE || value.revokedAt || expiresAt <= now) return null;
  return value;
}

async function audit(db, action, actorUid, reviewerUid, fixtureId, expiresAt, result) {
  await db.collection("founderReviewAudit").add({
    action,
    actorUid,
    reviewerUid,
    fixtureId: fixtureId || null,
    purpose: PURPOSE,
    expiresAt,
    result,
    createdAt: FieldValue.serverTimestamp(),
  });
}

function designateReviewAccount() {
  return riderCallable(async (data, context) => {
    assertFounder(context);
    assertReviewData(data);
    const reviewerUid = `${data.reviewerUid || ""}`.trim();
    if (!reviewerUid || reviewerUid === FOUNDER_RIDER_UID) throw new functions.https.HttpsError("invalid-argument", "A separate reviewer account is required.");
    const db = getFirestore();
    const expiresAt = Timestamp.fromMillis(Date.now() + REVIEWER_TTL_MS);
    await db.collection("founderTestAccounts").doc(reviewerUid).set({
      reviewerUid,
      accountType: ACCOUNT_TYPE,
      purpose: PURPOSE,
      enabled: true,
      createdBy: context.auth.uid,
      createdAt: FieldValue.serverTimestamp(),
      expiresAt,
      revokedAt: null,
    });
    await audit(db, "designate_reviewer", context.auth.uid, reviewerUid, null, expiresAt, "allowed");
    return {reviewerUid, accountType: ACCOUNT_TYPE, purpose: PURPOSE, expiresAt: expiresAt.toMillis()};
  });
}

function createReviewFixture() {
  return riderCallable(async (data, context) => {
    assertFounder(context);
    const reviewerUid = `${data && data.reviewerUid || ""}`.trim();
    const db = getFirestore();
    const designation = await activeDesignation(db, reviewerUid);
    if (!designation) throw new functions.https.HttpsError("failed-precondition", "Reviewer designation is inactive or expired.");
    const now = Date.now();
    const expiresAt = Timestamp.fromMillis(Math.min(now + FIXTURE_TTL_MS, designation.expiresAt.toMillis()));
    const ref = db.collection("reviewDeliveryFixtures").doc();
    await ref.set({
      fixtureId: ref.id,
      reviewerUid,
      purpose: PURPOSE,
      state: "active",
      createdBy: context.auth.uid,
      createdAt: FieldValue.serverTimestamp(),
      expiresAt,
      syntheticRoute: {
        pickupLabel: "CIRCUM Review Pickup",
        dropoffLabel: "CIRCUM Review Drop-off",
        pickup: {latitude: 51.5074, longitude: -0.1278},
        dropoff: {latitude: 51.5155, longitude: -0.0922},
      },
    });
    await audit(db, "create_fixture", context.auth.uid, reviewerUid, ref.id, expiresAt, "allowed");
    return {fixtureId: ref.id, expiresAt: expiresAt.toMillis(), state: "active"};
  });
}

function revokeReviewAccount() {
  return riderCallable(async (data, context) => {
    assertFounder(context);
    const reviewerUid = `${data && data.reviewerUid || ""}`.trim();
    if (!reviewerUid || reviewerUid === FOUNDER_RIDER_UID) throw new functions.https.HttpsError("invalid-argument", "A reviewer account is required.");
    const db = getFirestore();
    const ref = db.collection("founderTestAccounts").doc(reviewerUid);
    const snap = await ref.get();
    if (!snap.exists) throw new functions.https.HttpsError("not-found", "Reviewer designation was not found.");
    await ref.update({enabled: false, revokedAt: FieldValue.serverTimestamp()});
    await db.collection("reviewDeliveryFixtures").where("reviewerUid", "==", reviewerUid).where("state", "==", "active").get().then(async (fixtures) => {
      const batch = db.batch();
      fixtures.docs.forEach((doc) => batch.update(doc.ref, {state: "revoked", revokedAt: FieldValue.serverTimestamp()}));
      if (!fixtures.empty) await batch.commit();
    });
    await audit(db, "revoke_reviewer", context.auth.uid, reviewerUid, null, null, "allowed");
    return {reviewerUid, enabled: false};
  });
}

function getReviewFixture() {
  return riderCallable(async (data, context) => {
    const reviewerUid = authUid(context);
    const db = getFirestore();
    const designation = await activeDesignation(db, reviewerUid);
    const query = db.collection("reviewDeliveryFixtures").where("reviewerUid", "==", reviewerUid).where("state", "==", "active").limit(10);
    const snapshots = (await query.get()).docs;
    const snap = snapshots.find((candidate) => candidate.exists && candidate.data().reviewerUid === reviewerUid);
    const fixture = snap && snap.exists ? snap.data() : null;
    const fixtureId = snap ? snap.id : null;
    const expiresAt = fixture && fixture.expiresAt && fixture.expiresAt.toMillis ? fixture.expiresAt.toMillis() : 0;
    if (!designation || !fixture || fixture.reviewerUid !== reviewerUid || fixture.purpose !== PURPOSE || fixture.state !== "active" || expiresAt <= Date.now()) {
      await audit(db, "read_fixture", context.auth.uid, reviewerUid, fixtureId || null, fixture && fixture.expiresAt || null, "denied");
      throw new functions.https.HttpsError("permission-denied", "Review fixture is unavailable.");
    }
    await audit(db, "read_fixture", context.auth.uid, reviewerUid, fixtureId, fixture.expiresAt, "allowed");
    return {fixtureId, expiresAt, state: fixture.state, syntheticRoute: fixture.syntheticRoute};
  });
}

function updateReviewFixtureLocation() {
  return riderCallable(async (data, context) => {
    const reviewerUid = authUid(context);
    const fixtureId = `${data && data.fixtureId || ""}`.trim();
    const latitude = Number(data && data.latitude);
    const longitude = Number(data && data.longitude);
    if (!fixtureId || !Number.isFinite(latitude) || !Number.isFinite(longitude)) throw new functions.https.HttpsError("invalid-argument", "A valid fixture location is required.");
    const db = getFirestore();
    const designation = await activeDesignation(db, reviewerUid);
    const ref = db.collection("reviewDeliveryFixtures").doc(fixtureId);
    const snap = await ref.get();
    const fixture = snap.exists ? snap.data() : null;
    const expiresAt = fixture && fixture.expiresAt && fixture.expiresAt.toMillis ? fixture.expiresAt.toMillis() : 0;
    if (!designation || !fixture || fixture.reviewerUid !== reviewerUid || fixture.purpose !== PURPOSE || fixture.state !== "active" || expiresAt <= Date.now()) throw new functions.https.HttpsError("permission-denied", "Review fixture is unavailable.");
    await ref.update({lastLocation: {latitude, longitude, accuracyMeters: Number(data.accuracyMeters || 0), recordedAt: FieldValue.serverTimestamp()}});
    await audit(db, "update_fixture_location", context.auth.uid, reviewerUid, fixtureId, fixture.expiresAt, "allowed");
    return {fixtureId, state: "active"};
  });
}

module.exports = {
  designateReviewAccount,
  createReviewFixture,
  getReviewFixture,
  updateReviewFixtureLocation,
  revokeReviewAccount,
  _private: {
    activeDesignation,
    assertFounder,
    PURPOSE,
    ACCOUNT_TYPE,
    REVIEWER_TTL_MS,
    FIXTURE_TTL_MS,
  },
};
