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
    await setDoc(doc(db, "riderReliabilityAdjustments", "adjustment-1"), {riderId: "rider-1", immutable: true});
    await setDoc(doc(db, "marketplaceRiskFlags", "flag-1"), {riderId: "rider-1", status: "OPEN"});
    await setDoc(doc(db, "irisVisualShadowResults", "analysis-1"), {analysisId: "analysis-1", mode: "SHADOW"});
    await setDoc(doc(db, "irisVisualModelState", "current"), {mode: "SHADOW", enabled: true});
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
  await assertSucceeds(getDoc(doc(admin, "riderReliabilityAdjustments", "adjustment-1")));
  await assertSucceeds(getDoc(doc(admin, "marketplaceRiskFlags", "flag-1")));
  await assertFails(getDoc(doc(sender, "marketplaceRiskFlags", "flag-1")));
});

test("no client, including Admin, can mutate immutable operations records", async () => {
  const admin = env.authenticatedContext("admin-1", {adminRole: "super_admin"}).firestore();
  await assertFails(updateDoc(doc(admin, "deliveryRequests", "delivery-1", "timeline", "event-1"), {eventType: "Forged"}));
  await assertFails(updateDoc(doc(admin, "operationalIncidents", "incident-1"), {status: "RESOLVED"}));
  await assertFails(setDoc(doc(admin, "deliveryOperationalState", "forged"), {active: true}));
  await assertFails(updateDoc(doc(admin, "riderReliabilityAdjustments", "adjustment-1"), {points: 100}));
  await assertFails(updateDoc(doc(admin, "marketplaceRiskFlags", "flag-1"), {status: "DISMISSED"}));
  await assertFails(updateDoc(doc(admin, "irisVisualShadowResults", "analysis-1"), {affectsPricing: true}));
  await assertFails(updateDoc(doc(admin, "irisVisualModelState", "current"), {mode: "PROMOTED"}));
});

test("visual shadow evidence is Admin-readable but never client-writable", async () => {
  const admin = env.authenticatedContext("admin-1", {adminRole: "operations_admin"}).firestore();
  const sender = env.authenticatedContext("sender-1").firestore();
  await assertSucceeds(getDoc(doc(admin, "irisVisualShadowResults", "analysis-1")));
  await assertFails(getDoc(doc(sender, "irisVisualShadowResults", "analysis-1")));
  await assertFails(setDoc(doc(sender, "irisVisualShadowResults", "forged"), {affectsPricing: true}));
});
