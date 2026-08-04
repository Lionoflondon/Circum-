/* eslint-disable max-len, require-jsdoc */
const test = require("node:test");
const fs = require("node:fs");
const path = require("node:path");
const {assertFails, assertSucceeds, initializeTestEnvironment} = require("@firebase/rules-unit-testing");
const {doc, getDoc, setDoc} = require("firebase/firestore");

let env;
test.before(async () => {
  env = await initializeTestEnvironment({
    projectId: "circum-dispatch-read-rules-test",
    firestore: {rules: fs.readFileSync(path.join(__dirname, "..", "..", "firestore.rules"), "utf8")},
  });
});
test.after(() => env.cleanup());
test.beforeEach(() => env.clearFirestore());

async function seed(profile) {
  await env.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "riderProfiles", "rider-1"), profile);
    await setDoc(doc(context.firestore(), "deliveryRequests", "job-1"), {status: "requested"});
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

test("approved rider can read available jobs", async () => {
  await seed(approved);
  await assertSucceeds(getDoc(doc(env.authenticatedContext("rider-1").firestore(), "deliveryRequests", "job-1")));
});

for (const [name, patch] of [
  ["pending rider", {approvalStatus: "pending"}],
  ["suspended rider", {accountStatus: "suspended"}],
  ["incomplete rider", {dispatchEligible: false, onboardingStatus: "application_submitted"}],
]) {
  test(`${name} cannot read available jobs`, async () => {
    await seed({...approved, ...patch});
    await assertFails(getDoc(doc(env.authenticatedContext("rider-1").firestore(), "deliveryRequests", "job-1")));
  });
}

test("admin can still read available jobs", async () => {
  await seed({...approved, dispatchEligible: false});
  await assertSucceeds(getDoc(doc(env.authenticatedContext("admin-1", {adminRole: "super_admin"}).firestore(), "deliveryRequests", "job-1")));
});

test("configured founder Rider claim can read jobs without granting impostors", async () => {
  await seed({...approved, dispatchEligible: false});
  await env.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(
        context.firestore(),
        "riderProfiles",
        "T2eV6PQucdUKmwSipEn2NAn4N9z1",
    ), {...approved, dispatchEligible: false});
  });
  await assertSucceeds(getDoc(doc(env.authenticatedContext(
      "T2eV6PQucdUKmwSipEn2NAn4N9z1",
      {founderRider: true},
  ).firestore(), "deliveryRequests", "job-1")));
  await assertFails(getDoc(doc(env.authenticatedContext(
      "not-the-founder",
      {founderRider: true},
  ).firestore(), "deliveryRequests", "job-1")));
});

test("configured founder Rider cannot bypass account suspension", async () => {
  await seed({...approved, dispatchEligible: false, accountStatus: "suspended"});
  await env.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(
        context.firestore(),
        "riderProfiles",
        "T2eV6PQucdUKmwSipEn2NAn4N9z1",
    ), {...approved, dispatchEligible: false, accountStatus: "suspended"});
  });
  await assertFails(getDoc(doc(env.authenticatedContext(
      "T2eV6PQucdUKmwSipEn2NAn4N9z1",
      {founderRider: true},
  ).firestore(), "deliveryRequests", "job-1")));
});
