/* eslint-disable max-len */
"use strict";

const test = require("node:test");
const fs = require("node:fs");
const path = require("node:path");
const {assertFails, assertSucceeds, initializeTestEnvironment} = require("@firebase/rules-unit-testing");
const {doc, getDoc, setDoc, updateDoc, Timestamp} = require("firebase/firestore");

const projectId = "circum-scheduled-delivery-rules-test";
let testEnv;

test.before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId,
    firestore: {
      rules: fs.readFileSync(path.join(__dirname, "..", "..", "firestore.rules"), "utf8"),
    },
  });
});

test.after(async () => testEnv.cleanup());
test.beforeEach(async () => testEnv.clearFirestore());

async function seedScheduledGift() {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "deliveryRequests", "gift-1"), {
      deliveryId: "gift-1",
      requestId: "gift-1",
      senderId: "sender-1",
      productType: "gift",
      fulfilmentMode: "scheduled",
      fulfilmentStrategy: "scheduled_delivery",
      scheduledAt: Timestamp.fromDate(new Date("2099-08-14T12:00:00Z")),
      status: "scheduled",
      deliveryStatus: "scheduled",
      deliveryStage: "scheduled",
      dispatchStatus: "held",
      matchingStatus: "held",
      riderId: "rider-1",
      assignedRiderId: "rider-1",
    });
  });
}

async function seedHealthPickup() {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "prescriptionPickups", "health-1"), {
      pickupId: "health-1",
      senderId: "sender-1",
      userId: "sender-1",
      status: "scheduled",
      paymentStatus: "paid",
      healthPlusCharge: 100,
      deliveryCharge: 20,
      logisticsValue: 20,
      riderEarning: 13,
      platformShare: 7,
      riderSettlementAuthority: "canonical_health_plus_delivery_pricing_v1",
    });
  });
}

test("Sender cannot forge schedule strategy activation or Rider reservation", async () => {
  await seedScheduledGift();
  const db = testEnv.authenticatedContext("sender-1").firestore();
  for (const patch of [
    {fulfilmentStrategy: "open_dispatch"},
    {scheduledAt: Timestamp.fromDate(new Date("2020-01-01T00:00:00Z"))},
    {status: "requested", dispatchStatus: "requested", matchingStatus: "available"},
    {riderId: "rider-2", assignedRiderId: "rider-2"},
  ]) {
    await assertFails(updateDoc(doc(db, "deliveryRequests", "gift-1"), patch));
  }
});

test("Rider cannot self-assign or start a future scheduled delivery directly", async () => {
  await seedScheduledGift();
  const db = testEnv.authenticatedContext("rider-1").firestore();
  await assertFails(updateDoc(doc(db, "deliveryRequests", "gift-1"), {
    status: "navigating_to_pickup",
    deliveryStatus: "navigating_to_pickup",
    deliveryStage: "navigating_to_pickup",
  }));
  await assertFails(updateDoc(doc(db, "deliveryRequests", "gift-1"), {
    assignedRiderId: "rider-2",
  }));
});

test("reserved Rider can restore own scheduled job while another Rider cannot read it", async () => {
  await seedScheduledGift();
  const assigned = testEnv.authenticatedContext("rider-1").firestore();
  const other = testEnv.authenticatedContext("rider-2").firestore();
  await assertSucceeds(getDoc(doc(assigned, "deliveryRequests", "gift-1")));
  await assertFails(getDoc(doc(other, "deliveryRequests", "gift-1")));
});

test("anonymous users cannot read or mutate scheduled jobs", async () => {
  await seedScheduledGift();
  const db = testEnv.unauthenticatedContext().firestore();
  await assertFails(getDoc(doc(db, "deliveryRequests", "gift-1")));
  await assertFails(updateDoc(doc(db, "deliveryRequests", "gift-1"), {status: "requested"}));
});

test("Health+ owners cannot forge financial lifecycle assignment or TP authority", async () => {
  await seedHealthPickup();
  const db = testEnv.authenticatedContext("sender-1").firestore();
  for (const patch of [
    {healthPlusCharge: 1},
    {paymentStatus: "failed"},
    {deliveryCharge: 99},
    {logisticsValue: 99},
    {riderEarning: 65},
    {platformShare: 35},
    {riderSettlementAuthority: "client_override"},
    {trustPoints: 600},
    {trustPointsAwarded: 600},
    {assignedRiderId: "rider-1"},
    {status: "delivered", completedAt: Timestamp.fromDate(new Date("2026-08-14T12:00:00Z"))},
  ]) {
    await assertFails(updateDoc(doc(db, "prescriptionPickups", "health-1"), patch));
  }
  await assertSucceeds(updateDoc(doc(db, "prescriptionPickups", "health-1"), {
    notes: "Please use the side entrance.",
  }));
});
