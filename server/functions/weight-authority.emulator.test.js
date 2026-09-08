"use strict";
const {test, before, after, mock} = require("node:test");
const assert = require("node:assert/strict");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const {getStorage} = require("firebase-admin/storage");
const endpoints = require("./delivery-adjustments");
let app; let db;
const rider = {auth: {uid: "rider"}, app: {appId: "test"}};
const sender = {auth: {uid: "sender"}, app: {appId: "test"}};
const admin = {auth: {uid: "support", token: {role: "support_agent"}}, app: {appId: "test"}};
before(() => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST);
  app = initializeApp({projectId: "demo-weight-authority", storageBucket: "demo-weight-authority.appspot.com"});
  db = getFirestore(); db.settings({ignoreUndefinedProperties: true});
  // Storage transport is stubbed here; evidence ownership validation remains real.
  mock.method(getStorage(), "bucket", () => ({name: "demo-weight-authority.appspot.com", file: (path) => ({getMetadata: async () => [{contentType: "image/jpeg", size: "100", metadata: {deliveryId: path.split("/")[1], uploadedBy: "rider", evidenceType: "weight_discrepancy"}}]})}));
});
after(async () => {
mock.restoreAll(); if (app) await deleteApp(app);
});
async function fixture(id) {
  await db.doc(`deliveryRequests/${id}`).set({senderId: "sender", assignedRiderId: "rider", status: "accepted", weightKg: 1, packageDescription: "Books", price: 1, distanceMiles: 10, vehicleType: "car"});
  return {requestId: id, reason: "weight_exceeded", observedWeightKg: 10, revisedQuote: 0.01, additionalAmount: 0.01,
    evidencePhotos: [`https://firebasestorage.googleapis.com/v0/b/demo-weight-authority.appspot.com/o/${encodeURIComponent(`delivery_weight_evidence/${id}/discrepancy/1.jpg`)}`]};
}
test("alias-only assigned Rider report, trusted review, Sender decision; price is server-derived", async () => {
  const data = await fixture("valid");
  await assert.rejects(endpoints.reportLoadDiscrepancy.run(data, {}), {code: "unauthenticated"});
  await assert.rejects(endpoints.reportLoadDiscrepancy.run(data, sender), {code: "permission-denied"});
  const report = await endpoints.reportLoadDiscrepancy.run(data, rider);
  assert.ok(report.additionalAmount > 0.01);
  const a = (await db.doc(`deliveryAdjustments/${report.adjustmentId}`).get()).data();
  assert.equal(a.riderId, "rider"); assert.equal(a.adminDecision, "pending");
  await assert.rejects(endpoints.reportLoadDiscrepancy.run(data, rider));
  assert.equal((await db.collection("deliveryAdjustments").where("bookingId", "==", "valid").get()).size, 1);
  const review = {adjustmentId: report.adjustmentId, decision: "approve", revisedQuote: 0.01};
  await assert.rejects(endpoints.reviewDeliveryAdjustment.run(review, rider), {code: "permission-denied"});
  await endpoints.reviewDeliveryAdjustment.run(review, admin);
  assert.equal((await db.doc("deliveryRequests/valid").get()).data().status, "awaiting_sender_adjustment");
  assert.equal((await db.doc(`deliveryAdjustments/${report.adjustmentId}`).get()).data().additionalAmount, report.additionalAmount);
  await assert.rejects(endpoints.cancelAdjustedCollection.run({adjustmentId: report.adjustmentId}, rider), {code: "permission-denied"});
  await endpoints.cancelAdjustedCollection.run({adjustmentId: report.adjustmentId}, sender);
  assert.equal((await db.doc(`deliveryAdjustments/${report.adjustmentId}`).get()).data().status, "cancelled_by_sender");
});
test("foreign delivery, mismatched aliases and custody reject discrepancy writes", async () => {
  const data = await fixture("deny");
  await assert.rejects(endpoints.reportLoadDiscrepancy.run({...data, requestId: "missing"}, rider), {code: "not-found"});
  for (const patch of [{riderId: "other"}, {riderId: "rider", status: "collected"}]) {
    await db.doc("deliveryRequests/deny").update(patch);
    await assert.rejects(endpoints.reportLoadDiscrepancy.run(data, rider));
  }
  assert.equal((await db.collection("deliveryAdjustments").where("bookingId", "==", "deny").get()).size, 0);
});
