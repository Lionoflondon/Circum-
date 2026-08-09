/* eslint-disable max-len, require-jsdoc */
const test = require("node:test");
const fs = require("node:fs");
const path = require("node:path");
const {assertFails, assertSucceeds, initializeTestEnvironment} = require("@firebase/rules-unit-testing");
const {doc, getDoc, setDoc, updateDoc} = require("firebase/firestore");

let env;
test.before(async () => {
  env = await initializeTestEnvironment({
    projectId: "circum-dispatch-read-rules-test",
    firestore: {rules: fs.readFileSync(path.join(__dirname, "..", "..", "firestore.rules"), "utf8")},
  });
});
test.after(() => env.cleanup());
test.beforeEach(() => env.clearFirestore());

async function seed(profile, delivery = {status: "requested"}) {
  await env.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "riderProfiles", "rider-1"), profile);
    await setDoc(doc(context.firestore(), "deliveryRequests", "job-1"), delivery);
  });
}

const approved = {
  dispatchEligible: true,
  approvalStatus: "approved",
  verificationStatus: "approved",
  onboardingStatus: "approved",
  vehicleVerified: true,
  documentsVerified: true,
  accountStatus: "active",
};

test("approved Rider cannot directly read an available delivery document", async () => {
  await seed(approved);
  await assertFails(getDoc(doc(env.authenticatedContext("rider-1").firestore(), "deliveryRequests", "job-1")));
});

test("assigned Rider cannot bypass the projection to read payment fields", async () => {
  await seed(approved, {
    status: "accepted",
    riderId: "rider-1",
    stripePaymentIntentId: "pi_private",
    paymentStatus: "paid",
  });
  await assertFails(getDoc(doc(env.authenticatedContext("rider-1").firestore(), "deliveryRequests", "job-1")));
});

test("authenticated customer cannot pretend to be a Rider", async () => {
  await seed(approved);
  await assertFails(getDoc(doc(env.authenticatedContext("customer-1").firestore(), "deliveryRequests", "job-1")));
});

test("Rider cannot modify an unassigned offer document", async () => {
  await seed(approved);
  await assertFails(updateDoc(
      doc(env.authenticatedContext("rider-1").firestore(), "deliveryRequests", "job-1"),
      {matchingStatus: "accepted"},
  ));
});

test("admin can still read available jobs", async () => {
  await seed({...approved, dispatchEligible: false});
  await assertSucceeds(getDoc(doc(env.authenticatedContext("admin-1", {adminRole: "super_admin"}).firestore(), "deliveryRequests", "job-1")));
});

test("founder Rider claim cannot bypass the secure projection", async () => {
  await seed({...approved, dispatchEligible: false});
  await env.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(
        context.firestore(),
        "riderProfiles",
        "T2eV6PQucdUKmwSipEn2NAn4N9z1",
    ), {...approved, dispatchEligible: false});
  });
  await assertFails(getDoc(doc(env.authenticatedContext(
      "T2eV6PQucdUKmwSipEn2NAn4N9z1",
      {founderRider: true},
  ).firestore(), "deliveryRequests", "job-1")));
  await assertFails(getDoc(doc(env.authenticatedContext(
      "not-the-founder",
      {founderRider: true},
  ).firestore(), "deliveryRequests", "job-1")));
});

test("delivery owner retains Sender read access", async () => {
  await seed(approved, {status: "requested", senderId: "sender-1"});
  await assertSucceeds(getDoc(doc(env.authenticatedContext("sender-1").firestore(), "deliveryRequests", "job-1")));
});
