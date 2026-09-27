/* eslint-disable max-len, require-jsdoc */
"use strict";

const functions = require("firebase-functions/v1");
const {FieldValue, GeoPoint, Timestamp} = require("firebase-admin/firestore");
const lifecycle = require("./delivery-lifecycle-core");

const ROOT = "qaSpecialFlowFixtures";
const fail = (message, code = "failed-precondition") => {
  throw new functions.https.HttpsError(code, message);
};
const qaConfig = (env) => require("./qa-lifecycle")._test.config(env);

function isPublicQaDelivery(delivery = {}) {
  return delivery.isSyntheticQa === true &&
    delivery.qaPublic === true &&
    delivery.qaNamespace === ROOT &&
    typeof delivery.qaFixtureId === "string" &&
    delivery.realDispatch === false &&
    delivery.suppressExternalSideEffects === true &&
    delivery.excludeFromSettlement === true &&
    delivery.excludeFromPayout === true;
}

function requireQaAttestation(context) {
  if (!context || !context.auth || !context.auth.uid) fail("Authenticated QA attestation is required.", "unauthenticated");
  if (!context.app) fail("Authenticated QA attestation is required.", "unauthenticated");
  return context.auth.uid;
}

function assertActiveFixture(fixture, lists, uid, now = Date.now()) {
  if (!fixture || fixture.isSyntheticQa !== true || fixture.archived === true || fixture.closing === true ||
      !lists.operators.includes(fixture.qaCreatedBy) || !lists.senders.includes(fixture.senderId) ||
      !lists.riders.includes(fixture.riderId) || fixture.riderId !== uid ||
      !fixture.expiresAt || fixture.expiresAt.toMillis() <= now) {
    fail("QA fixture is unavailable.", "permission-denied");
  }
}

async function activeFixtureForRider(db, context, env = process.env) {
  const uid = requireQaAttestation(context);
  if (env.QA_LIFECYCLE_ENABLED !== "true") return null;
  const lists = qaConfig(env);
  if (!lists.riders.includes(uid)) return null;
  const snapshot = await db.collection(ROOT).where("riderId", "==", uid).limit(10).get();
  const current = snapshot.docs.map((doc) => ({id: doc.id, ...doc.data()}))
    .find((fixture) => fixture.archived !== true && fixture.closing !== true &&
      fixture.isSyntheticQa === true && fixture.expiresAt && fixture.expiresAt.toMillis() > Date.now());
  if (!current) return null;
  assertActiveFixture(current, lists, uid);
  return {uid, lists, fixture: current};
}

async function authorizePublicDelivery(db, context, deliveryId, env = process.env, {allowUnassigned = false} = {}) {
  const direct = await db.collection("deliveryRequests").doc(deliveryId).get();
  if (!direct.exists || !isPublicQaDelivery(direct.data())) return null;
  const uid = requireQaAttestation(context);
  const delivery = direct.data();
  const lists = qaConfig(env);
  if (!lists.riders.includes(uid) || (!allowUnassigned && delivery.riderId !== uid)) fail("QA delivery access is not permitted.", "permission-denied");
  const fixtureSnapshot = await db.collection(ROOT).doc(delivery.qaFixtureId).get();
  const fixture = fixtureSnapshot.exists ? {id: fixtureSnapshot.id, ...fixtureSnapshot.data()} : null;
  assertActiveFixture(fixture, lists, uid);
  if (fixture.publicDeliveryId !== deliveryId) fail("QA delivery provenance is invalid.", "permission-denied");
  return {delivery, fixture, lists, uid, ref: direct.ref};
}

function publicDeliveryId(fixtureId) {
  return `qa_public_${fixtureId}`;
}

async function createPublicDelivery({db, fixture, actorUid}) {
  if (!fixture || fixture.isSyntheticQa !== true || actorUid !== fixture.senderId) fail("QA Sender operator required.", "permission-denied");
  const id = fixture.publicDeliveryId || publicDeliveryId(fixture.id);
  const ref = db.collection("deliveryRequests").doc(id);
  const now = Timestamp.now();
  await db.runTransaction(async (tx) => {
    const existing = await tx.get(ref);
    if (existing.exists) {
      if (!isPublicQaDelivery(existing.data()) || existing.data().qaFixtureId !== fixture.id) fail("QA delivery provenance is invalid.");
      return;
    }
    tx.create(ref, {
      requestId: id,
      bookingId: id,
      senderId: fixture.senderId,
      userId: fixture.senderId,
      customerId: fixture.senderId,
      riderId: null,
      status: "requested",
      deliveryStatus: "requested",
      deliveryStage: "requested",
      matchingStatus: "available",
      dispatchStatus: "requested",
      paymentStatus: "paid",
      currency: "GBP",
      amountPence: 2000,
      riderEarning: 13,
      riderEligibleFare: 20,
      riderPayoutCalculationVersion: "qa_fixture_v1",
      pickupLocality: "QA pickup locality",
      dropoffLocality: "QA drop-off locality",
      pickupDetails: {locality: "QA pickup locality"},
      dropoffDetails: {locality: "QA drop-off locality"},
      pickupPosition: {geopoint: new GeoPoint(51.5074, -0.1278)},
      routeDistanceMetres: 2400,
      routeDurationSeconds: 720,
      packageDescription: "QA parcel",
      normalizedItemName: "QA parcel",
      declaredWeightKg: 1,
      vehicleRequirement: "car",
      vehicleType: "car",
      deliveryTime: {type: "asap", summary: "ASAP"},
      isSyntheticQa: true,
      qaPublic: true,
      qaNamespace: ROOT,
      qaFixtureId: fixture.id,
      qaLifecycleFixtureId: fixture.lifecycleFixtureId,
      qaCreatedBy: fixture.qaCreatedBy,
      qaCreatedAt: fixture.qaCreatedAt,
      realDispatch: false,
      suppressExternalSideEffects: true,
      excludeFromAnalytics: true,
      excludeFromSettlement: true,
      excludeFromPayout: true,
      excludeFromCustomerNotifications: true,
      offerExpiresAt: Timestamp.fromMillis(now.toMillis() + 15 * 60 * 1000),
      expiresAt: Timestamp.fromMillis(now.toMillis() + 15 * 60 * 1000),
      createdAt: now,
      updatedAt: now,
    });
    tx.create(db.collection(ROOT).doc(fixture.id).collection("qaPublicSecrets").doc(id), {
      qaFixtureId: fixture.id,
      deliveryId: id,
      collectionPin: "2468",
      deliveryPin: "8642",
      createdAt: now,
      isSyntheticQa: true,
    });
    tx.update(db.collection(ROOT).doc(fixture.id), {publicDeliveryId: id, publicDeliveryCreatedAt: now});
  });
  return {deliveryId: id, qaOnly: true, realDispatch: false};
}

async function getPublicOffer({db, access, projection}) {
  const id = access.fixture.publicDeliveryId;
  if (!id) return {riderId: access.uid, nearestRequests: [], eligible: true, qaOnly: true};
  const snapshot = await db.collection("deliveryRequests").doc(id).get();
  if (!snapshot.exists || !isPublicQaDelivery(snapshot.data())) return {riderId: access.uid, nearestRequests: [], eligible: true, qaOnly: true};
  const delivery = snapshot.data();
  const expiry = delivery.offerExpiresAt && typeof delivery.offerExpiresAt.toMillis === "function" ? delivery.offerExpiresAt.toMillis() : Number(delivery.offerExpiresAt || 0);
  if (expiry <= Date.now() || delivery.riderId || !["requested", "pending", "broadcast", "broadcasted", "awaiting_rider", "finding_rider"].includes(`${delivery.status || ""}`.toLowerCase())) {
    return {riderId: access.uid, nearestRequests: [], eligible: true, qaOnly: true};
  }
  return {riderId: access.uid, nearestRequests: [projection(snapshot.id, delivery, Math.min(expiry, Date.now() + 45000))], expiresAt: Math.min(expiry, Date.now() + 45000), eligible: true, qaOnly: true};
}

async function accept({db, context, deliveryId, env = process.env}) {
  const access = await authorizePublicDelivery(db, context, deliveryId, env, {allowUnassigned: true});
  if (!access) return null;
  const result = await db.runTransaction(async (tx) => {
    const snap = await tx.get(access.ref);
    const delivery = snap.data() || {};
    if (!isPublicQaDelivery(delivery) || delivery.qaFixtureId !== access.fixture.id) fail("QA delivery provenance is invalid.", "permission-denied");
    if (delivery.riderId === access.uid && ["accepted", "assigned", "navigating_to_pickup", "arrived_at_pickup", "pickup_verified", "collected", "navigating_to_dropoff", "arrived_at_dropoff", "delivered", "completed"].includes(`${delivery.status || ""}`.toLowerCase())) return {idempotent: true, delivery};
    if (delivery.riderId && delivery.riderId !== access.uid) throw new functions.https.HttpsError("already-exists", "Delivery request has already been accepted.");
    if (delivery.status !== "requested") fail("Delivery request is no longer open for acceptance.");
    const rider = (await tx.get(db.collection("riders").doc(access.uid))).data() || {};
    const display = `${rider.fullName || rider.name || rider.displayName || rider.email || "QA Rider"}`.trim();
    tx.set(access.ref, {
      status: "accepted", deliveryStatus: "accepted", deliveryStage: "accepted", matchingStatus: "accepted", dispatchStatus: "accepted",
      riderId: access.uid, assignedRiderId: access.uid, assignedDriverId: access.uid,
      riderName: display, driverName: display, courierName: display,
      driverVehicle: rider.vehicleType || "car", acceptedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    tx.set(db.collection("chats").doc(delivery.requestId || deliveryId), {
      threadId: delivery.requestId || deliveryId, bookingId: delivery.requestId || deliveryId, requestId: delivery.requestId || deliveryId,
      participants: [access.uid, access.fixture.senderId], participantRoles: {[access.uid]: "rider", [access.fixture.senderId]: "sender"},
      assignedRiderId: access.uid, noExternalNotification: true, isSyntheticQa: true, qaFixtureId: access.fixture.id, updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    tx.create(db.collection(ROOT).doc(access.fixture.id).collection("qaPublicAudit").doc(`${deliveryId}_accepted`), {
      action: "accept", deliveryId, riderId: access.uid, isSyntheticQa: true, at: FieldValue.serverTimestamp(),
    });
    return {idempotent: false, delivery};
  });
  return {status: "accepted", requestId: deliveryId, riderId: access.uid, senderNotified: false, idempotent: result.idempotent, qaOnly: true};
}

function transitionPatch(action, nextStatus, riderId) {
  const patch = {status: nextStatus, deliveryStatus: nextStatus, deliveryStage: nextStatus, lastRiderAction: action, lastRiderActionAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()};
  if (nextStatus === "navigating_to_pickup") patch.headingToPickupAt = FieldValue.serverTimestamp();
  if (nextStatus === "arrived_at_pickup") patch.pickupArrivedAt = FieldValue.serverTimestamp();
  if (nextStatus === "pickup_verified") {
    patch.collectionPinVerified = true;
    patch.collectionPinVerifiedAt = FieldValue.serverTimestamp();
    patch.collectionPinVerifiedBy = riderId;
  }
  if (nextStatus === "collected") patch.collectedAt = FieldValue.serverTimestamp();
  if (nextStatus === "navigating_to_dropoff") patch.inTransitAt = FieldValue.serverTimestamp();
  if (nextStatus === "arrived_at_dropoff") patch.dropoffArrivedAt = FieldValue.serverTimestamp();
  if (nextStatus === "delivered") {
    patch.deliveryPinVerified = true;
    patch.deliveryPinVerifiedAt = FieldValue.serverTimestamp();
    patch.deliveryPinVerifiedBy = riderId;
    patch.deliveredAt = FieldValue.serverTimestamp();
    patch.completedAt = FieldValue.serverTimestamp();
  }
  return patch;
}

async function transition({db, context, deliveryId, action, pin, env = process.env}) {
  const access = await authorizePublicDelivery(db, context, deliveryId, env);
  if (!access) return null;
  const nextStatus = lifecycle.statusForRiderAction(action);
  if (!nextStatus) fail("Unsupported rider tracking action.", "invalid-argument");
  const result = await db.runTransaction(async (tx) => {
    const snap = await tx.get(access.ref); const delivery = snap.data() || {};
    if (delivery.riderId !== access.uid) fail("Only the assigned QA Rider can update this delivery.", "permission-denied");
    const current = lifecycle.normalizeLifecycleStatus(delivery.status || delivery.deliveryStatus || "requested");
    if (current === nextStatus || nextStatus === "delivered" && current === "completed") return {status: current, idempotent: true};
    if (!lifecycle.canTransitionDeliveryStatus(current, nextStatus)) fail(`Cannot move delivery from ${current} to ${nextStatus}.`);
    const secretRef = db.collection(ROOT).doc(access.fixture.id).collection("qaPublicSecrets").doc(deliveryId);
    const secretSnap = await tx.get(secretRef); const secret = secretSnap.data() || {};
    if (action === "verify_collection_pin" || action === "verify_receiver_pin") {
      const expected = action === "verify_collection_pin" ? secret.collectionPin : secret.deliveryPin;
      if (`${pin || ""}` !== expected) fail("QA PIN is incorrect.");
      tx.set(secretRef, {lastVerifiedStage: action === "verify_collection_pin" ? "pickup" : "dropoff", updatedAt: FieldValue.serverTimestamp()}, {merge: true});
    }
    tx.set(access.ref, transitionPatch(action, nextStatus, access.uid), {merge: true});
    tx.set(db.collection("activeDeliveries").doc(deliveryId), {deliveryId, requestId: delivery.requestId || deliveryId, riderId: access.uid, status: nextStatus, isSyntheticQa: true, qaFixtureId: access.fixture.id, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
    tx.create(db.collection(ROOT).doc(access.fixture.id).collection("qaPublicAudit").doc(`${deliveryId}_${action}`), {action, deliveryId, riderId: access.uid, nextStatus, isSyntheticQa: true, at: FieldValue.serverTimestamp()});
    return {status: nextStatus, idempotent: false};
  });
  return {deliveryId, requestId: deliveryId, status: result.status, senderTrackingState: lifecycle.senderTrackingStateForBackendStatus(result.status), idempotent: result.idempotent, qaOnly: true};
}

async function arrive({db, context, deliveryId, phase, env = process.env}) {
  const access = await authorizePublicDelivery(db, context, deliveryId, env);
  if (!access) return null;
  const action = phase === "dropoff" ? "arrived_at_dropoff" : "arrived_at_pickup";
  return transition({db, context, deliveryId, action, env});
}

async function liveLocation({db, context, deliveryId, location, trackingStatus, env = process.env}) {
  const access = await authorizePublicDelivery(db, context, deliveryId, env);
  if (!access) return null;
  const lat = Number(location && (location.latitude ?? location.lat)); const lng = Number(location && (location.longitude ?? location.lng));
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) fail("A valid location is required.", "invalid-argument");
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(access.ref); const delivery = snap.data() || {};
    if (delivery.riderId !== access.uid) fail("Only the assigned QA Rider can update this delivery.", "permission-denied");
    const current = lifecycle.normalizeLifecycleStatus(delivery.status || delivery.deliveryStatus || "requested");
    if (["completed", "delivered", "cancelled", "canceled"].includes(current)) fail("Live tracking is not active for this delivery.");
    tx.set(access.ref.collection("tracking").doc("liveLocation"), {deliveryId, riderId: access.uid, latitude: lat, longitude: lng, status: trackingStatus || current, isSyntheticQa: true, qaFixtureId: access.fixture.id, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
    tx.set(db.collection("activeDeliveries").doc(deliveryId), {deliveryId, requestId: delivery.requestId || deliveryId, riderId: access.uid, status: current, riderLiveLocation: {latitude: lat, longitude: lng, updatedAt: FieldValue.serverTimestamp()}, isSyntheticQa: true, qaFixtureId: access.fixture.id, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
  });
  return {success: true, deliveryId, trackingHealth: {fresh: true, source: "qaPublicDelivery"}, qaOnly: true};
}

async function cleanup({db, fixture}) {
  const id = fixture && fixture.publicDeliveryId;
  if (!id) return {deleted: false};
  const ref = db.collection("deliveryRequests").doc(id); const snap = await ref.get();
  if (snap.exists && isPublicQaDelivery(snap.data()) && snap.data().qaFixtureId === fixture.id) {
    for (const path of [`deliveryRequests/${id}`, `deliveryRequestsPrivate/${id}`, `activeDeliveries/${id}`, `chats/${id}`]) await db.doc(path).delete().catch(() => {});
  }
  return {deleted: true, deliveryId: id};
}

module.exports = {ROOT, isPublicQaDelivery, activeFixtureForRider, authorizePublicDelivery, createPublicDelivery, getPublicOffer, accept, transition, arrive, liveLocation, cleanup, publicDeliveryId};
