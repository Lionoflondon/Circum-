/* eslint-disable max-len, require-jsdoc */
const {test, before, after} = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {initializeTestEnvironment, assertFails, assertSucceeds} = require("@firebase/rules-unit-testing");
const {doc, setDoc, getDoc, updateDoc, deleteDoc} = require("firebase/firestore");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const health = require("./health-plus");
const collections = ["prescriptionPickups", "healthPlusProfiles", "recurringPickupSchedules", "healthPlusUsageEvents", "healthPlusNotifications"];
let env; let app; let db;
before(async () => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST, "Emulator required");
  const projectId = "demo-health-authority";
  app = initializeApp({projectId}); db = getFirestore(); db.settings({ignoreUndefinedProperties: true});
  env = await initializeTestEnvironment({projectId, firestore: {rules: fs.readFileSync(path.join(__dirname, "../../firestore.rules"), "utf8")}});
  for (const collection of collections) {
    await db.doc(`${collection}/existing`).set({senderId: "owner", userId: "owner", businessId: "business", riderId: "assigned-rider", status: "scheduled"});
  }
  await db.doc("businessAccounts/business").set({ownerUid: "business-owner", createdByUserId: "business-owner", teamMemberIds: []});
});
after(async () => {
 if (env) await env.cleanup(); if (app) await deleteApp(app);
});

test("customers cannot forge Health+ records or edit pricing, payment, plan, lifecycle, usage or dispatch authority", async () => {
  const client = env.authenticatedContext("owner").firestore();
  for (const collection of collections) {
    await assertFails(setDoc(doc(client, collection, "forged"), {senderId: "owner", userId: "owner", status: "active"}));
    const ref = doc(client, collection, "existing");
    for (const patch of [
      {pricingInputs: {distanceMiles: 0.1, medicationWeightKg: 0.1}},
      {paymentStatus: "paid"}, {subscriptionPlan: "priority"}, {status: "completed"},
      {usedDeliveriesThisCycle: 0}, {remainingDeliveriesThisCycle: 999},
      {riderId: "attacker"}, {dispatchStatus: "assigned"}, {trustPoints: 999},
    ]) await assertFails(updateDoc(ref, patch));
    await assertFails(setDoc(ref, {senderId: "owner", status: "active"}));
    await assertFails(deleteDoc(ref));
  }
});

test("existing owner, business and assigned-rider reads remain intact and cross-customer access stays denied", async () => {
  for (const collection of collections) {
    await assertSucceeds(getDoc(doc(env.authenticatedContext("owner").firestore(), collection, "existing")));
    await assertFails(getDoc(doc(env.authenticatedContext("stranger").firestore(), collection, "existing")));
    await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), collection, "existing")));
  }
  for (const uid of ["business-owner", "assigned-rider"]) {
    const ref = doc(env.authenticatedContext(uid).firestore(), "prescriptionPickups", "existing");
    await assertSucceeds(getDoc(ref));
    await assertFails(updateDoc(ref, {status: "completed"}));
  }
});

test("Operations Admin writes remain available and usage events remain append-only", async () => {
  const admin = env.authenticatedContext("admin", {adminRole: "operations_admin"}).firestore();
  for (const collection of collections) {
    await assertSucceeds(setDoc(doc(admin, collection, "admin-created"), {senderId: "owner", status: "scheduled"}));
    if (collection === "healthPlusUsageEvents") {
      await assertFails(updateDoc(doc(admin, collection, "admin-created"), {status: "rewritten"}));
    } else {
      await assertSucceeds(updateDoc(doc(admin, collection, "admin-created"), {status: "updated"}));
    }
  }
});

test("legitimate create and schedule controls work through backend callables with idempotency and ownership", async (t) => {
  process.env.GOOGLE_MAPS_DIRECTIONS_API_KEY = "emulator-test";
  t.mock.method(global, "fetch", async () => ({ok: true, json: async () => ({status: "OK", routes: [{legs: [{distance: {value: 3218.688}}]}]})}));
  const context = {auth: {uid: "booking-owner", token: {email: "booking-owner@example.invalid"}}};
  const input = {consentConfirmed: true, fullName: "Sender", phoneNumber: "+447700900001", pharmacyAddress: "Pharmacy", deliveryAddress: "Home", preferredPickupTime: "10:00", frequency: "weekly", subscriptionPlan: "core", pricingInputs: {distanceMiles: 2, medicationWeightKg: 1}, idempotencyKey: "health-authority-booking"};
  const booking = await health.createHealthPlusBooking.run(input, context);
  const replay = await health.createHealthPlusBooking.run(input, context);
  assert.equal(replay.pickupId, booking.pickupId);
  assert.equal(replay.idempotent, true);
  const forged = await health.createHealthPlusBooking.run({...input, idempotencyKey: "forged-distance", pricingInputs: {distanceMiles: 0.01, medicationWeightKg: 1}}, context);
  assert.equal((await db.doc(`prescriptionPickups/${forged.pickupId}`).get()).data().amountPence,
    (await db.doc(`prescriptionPickups/${booking.pickupId}`).get()).data().amountPence);
  await health.updateSenderHealthPlusBooking.run({action: "pause_schedule", scheduleId: booking.scheduleId, idempotencyKey: "owner-pause"}, context);
  assert.equal((await db.doc(`recurringPickupSchedules/${booking.scheduleId}`).get()).data().paused, true);
  await assert.rejects(health.updateSenderHealthPlusBooking.run({action: "resume_schedule", scheduleId: booking.scheduleId, idempotencyKey: "stranger-resume"}, {auth: {uid: "stranger", token: {}}}), /not found/);
});
