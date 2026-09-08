"use strict";
const {test, before, after} = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const {initializeTestEnvironment, assertFails, assertSucceeds} = require("@firebase/rules-unit-testing");
const {doc, getDoc} = require("firebase/firestore");
const {requestRiderCancellation} = require("./rider-cancellation");
const {ASSIGNMENT_FIELDS} = require("./delivery-assignment");
let app; let db; let env;
before(async () => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST);
  app = initializeApp({projectId: "demo-rider-release"}); db = getFirestore(); db.settings({ignoreUndefinedProperties: true});
  env = await initializeTestEnvironment({projectId: "demo-rider-release", firestore: {rules: fs.readFileSync(`${__dirname}/../../firestore.rules`, "utf8")}});
  await env.clearFirestore();
});
after(async () => {
  if (env) await env.cleanup(); if (app) await deleteApp(app);
});
const ctx = {auth: {uid: "rider", token: {role: "rider"}}, app: {appId: "test"}};
async function fixture(id, patch = {}) {
  await db.doc(`deliveryRequests/${id}`).set({status: "accepted", assignedRiderId: "rider", senderId: "sender", paymentStatus: "paid", price: 20, rothAppliedAmount: 7, stripePaymentIntentId: "pi_unchanged", ...patch});
  await db.doc(`chats/${id}`).set({participants: ["rider", "sender"], participantRoles: {rider: "rider", sender: "sender"}, assignedRiderId: "rider"});
  for (const c of ["riders", "riderProfiles", "riderPresence"]) await db.doc(`${c}/rider`).set({activeDeliveryId: id, isOnline: true});
}
const release = (id, context = ctx) => requestRiderCancellation.run({deliveryId: id, reason: "cannot_complete", idempotencyKey: `${id}:assignment`}, context);
test("concurrent release clears aliases and access, preserves payment and records one impact", async () => {
  const id = "all-aliases"; await fixture(id, Object.fromEntries(ASSIGNMENT_FIELDS.map((f) => [f, "rider"])));
  const beforeClient = env.authenticatedContext("rider", {role: "rider", adminRole: "rider"}).firestore();
  await assertSucceeds(getDoc(doc(beforeClient, `deliveryRequests/${id}`)));
  await assertSucceeds(getDoc(doc(beforeClient, `chats/${id}`)));
  const results = await Promise.all(Array.from({length: 8}, () => release(id)));
  assert.equal(new Set(results.map((r) => r.eventId)).size, 1);
  const d = (await db.doc(`deliveryRequests/${id}`).get()).data();
  for (const f of ASSIGNMENT_FIELDS) assert.equal(d[f], undefined);
  assert.equal(d.status, "requested"); assert.equal(d.paymentStatus, "paid"); assert.equal(d.price, 20); assert.equal(d.rothAppliedAmount, 7); assert.equal(d.stripePaymentIntentId, "pi_unchanged");
  assert.equal((await db.collection("riderOperationalAudit").where("deliveryId", "==", id).get()).size, 1);
  assert.equal((await db.collection("notifications").where("data.deliveryId", "==", id).get()).size, 2);
  const client = env.authenticatedContext("rider", {role: "rider", adminRole: "rider"}).firestore();
  await assertFails(getDoc(doc(client, `deliveryRequests/${id}`)));
  await assertFails(getDoc(doc(client, `chats/${id}`)));
  await db.doc(`deliveryRequests/${id}`).update({riderId: "new-rider", assignedRiderId: "new-rider", status: "accepted"});
  await release(id);
  assert.equal((await db.doc(`deliveryRequests/${id}`).get()).data().assignedRiderId, "new-rider");
});
test("custody, terminal, conflicting aliases and Sender cancellation fail closed", async () => {
  for (const [i, patch] of [{status: "collected"}, {status: "in_transit"}, {status: "delivered"}, {status: "pickup_verified"}, {status: "waiting", collectedAt: 1}, {riderId: "other"}, {cancellationSettlementStatus: "pending_reconciliation"}].entries()) {
    const id = `deny-${i}`; await fixture(id, patch);
    await assert.rejects(release(id));
    assert.equal((await db.doc(`deliveryRequests/${id}`).get()).data().assignedRiderId, "rider");
  }
});
test("missing auth and foreign rider cannot release", async () => {
  await fixture("auth");
  await assert.rejects(release("auth", {}), {code: "unauthenticated"});
  await assert.rejects(release("auth", {auth: {uid: "stranger"}}), {code: "permission-denied"});
});

async function readyRider(uid) {
  await db.doc(`riders/${uid}`).set({approvalStatus: "approved", vehicleApproved: true, vehicleType: "car"});
  await db.doc(`riderProfiles/${uid}`).set({approvalStatus: "approved", vehicleApproved: true, vehicleType: "car"});
  await db.doc(`riderPresence/${uid}`).set({isOnline: true, dispatchEligible: true, availabilityStatus: "available", lastHeartbeatAt: Date.now(), currentLocation: {latitude: 51.5, longitude: -0.1, accuracyMeters: 5, updatedAt: Date.now()}});
}
test("release races real acceptance and old lifecycle loses authority", async () => {
  const accept = require("./accept-ride-requests");
  const tracking = require("./delivery-tracking");
  for (let seed = 0; seed < 10; seed++) {
    const id = `accept-race-${seed}`; const next = `next-${seed}`;
    await fixture(id, {requestId: id, packageDescription: "Books", weight: "1 kg", weightKg: 1, distanceMiles: 2, vehicleType: "car"});
    await readyRider(next);
    const results = await Promise.allSettled([release(id), accept.run({requestId: id}, {auth: {uid: next}, app: {appId: "test"}})]);
    assert.equal(results[0].status, "fulfilled");
    if (results[1].status === "rejected") await accept.run({requestId: id}, {auth: {uid: next}, app: {appId: "test"}});
    const d = (await db.doc(`deliveryRequests/${id}`).get()).data();
    assert.equal(d.assignedRiderId, next); assert.equal(d.paymentStatus, "paid");
    assert.equal(d.stripePaymentIntentId, "pi_unchanged");
    await assert.rejects(tracking.updateDeliveryTrackingStatus.run({deliveryId: id, action: "start_heading_to_pickup"}, ctx), {code: "permission-denied"});
    await release(id);
    assert.equal((await db.doc(`deliveryRequests/${id}`).get()).data().assignedRiderId, next);
    assert.equal((await db.collection("riderOperationalAudit").where("deliveryId", "==", id).get()).size, 1);
  }
});

test("Sender cancellation races release without reopening settled delivery or duplicating refund", async () => {
  const policy = require("./delivery-policy");
  for (let seed = 0; seed < 10; seed++) {
    const id = `sender-race-${seed}`; const session = `${id}-session`;
    await fixture(id, {state: "accepted", paymentSessionId: session});
    await db.doc(`senderPaymentSessions/${session}`).set({userId: "sender", userEmail: "sender@example.com", amountDue: 20, remainingAmount: 20, rothAppliedAmount: 0, currency: "GBP", paymentStatus: "paid", stripePaymentIntentId: "pi_unchanged", deliveryId: id});
    const sender = {auth: {uid: "sender", token: {email: "sender@example.com"}}, app: {appId: "test"}};
    const refunds = new Map();
    const stripe = {paymentIntents: {retrieve: async () => ({id: "pi_unchanged", amount: 2000, amount_received: 2000, currency: "gbp", status: "succeeded", metadata: {userId: "sender", paymentSessionId: session}})}, refunds: {
      list: async () => ({data: [...refunds.values()], has_more: false}),
      create: async (data, options) => {
        if (!refunds.has(options.idempotencyKey)) refunds.set(options.idempotencyKey, {id: `refund-${seed}`, amount: data.amount, status: "succeeded"});
        return refunds.get(options.idempotencyKey);
      },
    }};
    const quote = await policy.previewSenderCancellation.run({deliveryId: id}, sender);
    const results = await Promise.allSettled([release(id), policy.requestSenderCancellation(stripe).run({deliveryId: id, quoteToken: quote.quoteToken}, sender)]);
    for (const result of results) if (result.status === "rejected") assert.ok(["failed-precondition", "permission-denied"].includes(result.reason.code), result.reason.stack);
    const d = (await db.doc(`deliveryRequests/${id}`).get()).data();
    if (d.cancellationSettlementStatus) {
      assert.equal(d.cancellationSettlementStatus, "settled");
      assert.notEqual(d.status, "requested");
      await assert.rejects(release(id));
    } else {
      assert.equal(d.status, "requested"); assert.equal(d.paymentStatus, "paid");
    }
    assert.ok(refunds.size <= 1);
    assert.ok((await db.collection("riderOperationalAudit").where("deliveryId", "==", id).get()).size <= 1);
  }
});

test("offer generation racing release produces one safe projection and stale access stays denied", async () => {
  const offers = require("./rider-offers");
  const id = "rematch-projection"; const uid = "projection-rider";
  await fixture(id, {createdAt: Date.now(), pickupPosition: {geopoint: {latitude: 51.5, longitude: -0.1}}, packageDescription: "Books", weight: "1 kg", distanceMiles: 2, vehicleType: "car"});
  await readyRider(uid);
  const caller = {auth: {uid}, app: {appId: "test"}};
  const results = await Promise.allSettled([release(id), offers.getOffers({}, caller)]);
  for (const result of results) assert.equal(result.status, "fulfilled", result.reason && result.reason.stack);
  const visible = await offers.getOffers({}, caller);
  assert.equal(visible.nearestRequests.filter((offer) => offer.id === id || offer.requestId === id || offer.deliveryId === id).length, 1);
  assert.equal((await db.collection(`riderOfferProjections/${uid}/offers`).get()).docs.filter((d) => d.id === id).length, 1);
  assert.equal((await db.collection("deliveryTimeline").where("deliveryId", "==", id).get()).size, 1);
  await release(id);
  assert.equal((await db.collection("deliveryTimeline").where("deliveryId", "==", id).get()).size, 1);
});

test("release archives old IRIS acknowledgement and replacement Rider confirms independently", async () => {
  const iris = require("./rider-iris-acknowledgement");
  const id = "iris-rematch";
  await fixture(id, {status: "arrived_at_pickup"});
  await iris.confirmRiderIrisAssessment.run({deliveryId: id}, ctx);
  const result = await release(id);
  assert.equal((await db.doc(`riderIrisAcknowledgements/${id}`).get()).exists, false);
  assert.equal((await db.doc(`deliveryRequests/${id}`).get()).data().riderIrisAcknowledgement, undefined);
  const archived = (await db.doc(`deliveryPolicyEvents/rider_release_${result.eventId}`).get()).data();
  assert.equal(archived.priorIrisAcknowledgement.riderId, "rider");
  await db.doc(`deliveryRequests/${id}`).update({assignedRiderId: "replacement", status: "arrived_at_pickup", deliveryStage: "arrived_at_pickup"});
  await assert.rejects(iris.confirmRiderIrisAssessment.run({deliveryId: id}, ctx), {code: "permission-denied"});
  const next = await iris.confirmRiderIrisAssessment.run({deliveryId: id}, {auth: {uid: "replacement"}});
  assert.equal(next.duplicate, false); assert.equal(next.acknowledgement.riderId, "replacement");
});
