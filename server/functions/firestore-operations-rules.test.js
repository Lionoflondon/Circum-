/* eslint-disable max-len, require-jsdoc */
"use strict";

const test = require("node:test");
const fs = require("node:fs");
const path = require("node:path");
const {assertFails, assertSucceeds, initializeTestEnvironment} = require("@firebase/rules-unit-testing");
const {doc, getDoc, setDoc, updateDoc} = require("firebase/firestore");

let env;
test.before(async () => {
  env = await initializeTestEnvironment({projectId: "circum-operations-rules-test", firestore: {rules: fs.readFileSync(path.join(__dirname, "..", "..", "firestore.rules"), "utf8")}});
});
test.after(() => env.cleanup());
test.beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, "deliveryRequests", "delivery-1"), {senderId: "sender-1", status: "completed"});
    await setDoc(doc(db, "deliveryRequests", "delivery-1", "timeline", "event-1"), {deliveryId: "delivery-1", eventType: "Completed", immutable: true});
    await setDoc(doc(db, "operationalIncidents", "incident-1"), {deliveryId: "delivery-1", status: "OPEN"});
    await setDoc(doc(db, "deliveryOperationalState", "delivery-1"), {deliveryId: "delivery-1", active: false});
  });
});

test("only Admin can read operational timeline and incident projections", async () => {
  const admin = env.authenticatedContext("admin-1", {adminRole: "operations_admin"}).firestore();
  const sender = env.authenticatedContext("sender-1").firestore();
  await assertSucceeds(getDoc(doc(admin, "deliveryRequests", "delivery-1", "timeline", "event-1")));
  await assertSucceeds(getDoc(doc(admin, "operationalIncidents", "incident-1")));
  await assertSucceeds(getDoc(doc(admin, "deliveryOperationalState", "delivery-1")));
  await assertFails(getDoc(doc(sender, "deliveryRequests", "delivery-1", "timeline", "event-1")));
  await assertFails(getDoc(doc(sender, "operationalIncidents", "incident-1")));
});

test("no client, including Admin, can mutate immutable operations records", async () => {
  const admin = env.authenticatedContext("admin-1", {adminRole: "super_admin"}).firestore();
  await assertFails(updateDoc(doc(admin, "deliveryRequests", "delivery-1", "timeline", "event-1"), {eventType: "Forged"}));
  await assertFails(updateDoc(doc(admin, "operationalIncidents", "incident-1"), {status: "RESOLVED"}));
  await assertFails(setDoc(doc(admin, "deliveryOperationalState", "forged"), {active: true}));
});
