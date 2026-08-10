/* eslint-disable max-len, require-jsdoc */
"use strict";

const test = require("node:test");
const fs = require("node:fs");
const path = require("node:path");
const {assertFails, assertSucceeds, initializeTestEnvironment} = require("@firebase/rules-unit-testing");
const {doc, getDoc, setDoc, updateDoc, deleteDoc} = require("firebase/firestore");

let env;
test.before(async () => {
  env = await initializeTestEnvironment({projectId: "circum-vertical-rules-test", firestore: {rules: fs.readFileSync(path.join(__dirname, "..", "..", "firestore.rules"), "utf8")}});
});
test.after(() => env.cleanup());
test.beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, "prescriptionPickups", "health-1"), {senderId: "sender", assignedDriverId: "rider", status: "assigned", paymentStatus: "paid", prescriptionNotes: "private"});
    await setDoc(doc(db, "healthPlusProfiles", "profile-1"), {senderId: "sender", deliveryAddressCanonical: {formattedAddress: "Private"}});
    await setDoc(doc(db, "recurringPickupSchedules", "schedule-1"), {senderId: "sender", status: "active"});
    await setDoc(doc(db, "giftPaymentDrafts", "gift-draft"), {senderId: "sender", paymentStatus: "payment_pending"});
    await setDoc(doc(db, "giftCampaignParticipants", "participant-1"), {userId: "sender", status: "active"});
    await setDoc(doc(db, "businessAccounts", "business-1"), {ownerUid: "owner", createdByUserId: "owner", billingEmail: "private@example.com"});
    await setDoc(doc(db, "businessMemberships", "business-1_owner"), {businessId: "business-1", userId: "owner", role: "owner", status: "active"});
    await setDoc(doc(db, "businessMemberships", "business-1_viewer"), {businessId: "business-1", userId: "viewer", role: "viewer", status: "active"});
    await setDoc(doc(db, "businessJoinRequests", "join-1"), {businessId: "business-1", userId: "applicant", email: "applicant@example.com", status: "pending"});
  });
});

test("Health owners cannot bypass backend lifecycle, profile or recurrence authority", async () => {
  const db = env.authenticatedContext("sender").firestore();
  await assertSucceeds(getDoc(doc(db, "prescriptionPickups", "health-1")));
  await assertFails(updateDoc(doc(db, "prescriptionPickups", "health-1"), {status: "delivered"}));
  await assertFails(deleteDoc(doc(db, "prescriptionPickups", "health-1")));
  await assertFails(updateDoc(doc(db, "healthPlusProfiles", "profile-1"), {deliveryAddressCanonical: {formattedAddress: "Forged"}}));
  await assertFails(updateDoc(doc(db, "recurringPickupSchedules", "schedule-1"), {status: "cancelled"}));
});

test("Assigned Health Riders cannot read or mutate the mixed-authority pickup", async () => {
  const db = env.authenticatedContext("rider").firestore();
  await assertFails(getDoc(doc(db, "prescriptionPickups", "health-1")));
  await assertFails(updateDoc(doc(db, "prescriptionPickups", "health-1"), {status: "collected"}));
});

test("Gift clients cannot create authoritative drafts or mutate participants", async () => {
  const db = env.authenticatedContext("sender").firestore();
  await assertFails(setDoc(doc(db, "giftPaymentDrafts", "forged"), {senderId: "sender", paymentStatus: "payment_pending", grossBudget: 50}));
  await assertFails(updateDoc(doc(db, "giftCampaignParticipants", "participant-1"), {status: "matched"}));
});

test("ordinary Business members cannot read the mixed-authority account document", async () => {
  await assertSucceeds(getDoc(doc(env.authenticatedContext("owner").firestore(), "businessAccounts", "business-1")));
  await assertFails(getDoc(doc(env.authenticatedContext("viewer").firestore(), "businessAccounts", "business-1")));
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), "businessAccounts", "business-1")));
});

test("Business access requests are private to applicants and backend projections", async () => {
  await assertSucceeds(getDoc(doc(env.authenticatedContext("applicant").firestore(), "businessJoinRequests", "join-1")));
  await assertFails(getDoc(doc(env.authenticatedContext("viewer").firestore(), "businessJoinRequests", "join-1")));
  await assertFails(getDoc(doc(env.authenticatedContext("owner").firestore(), "businessJoinRequests", "join-1")));
});
