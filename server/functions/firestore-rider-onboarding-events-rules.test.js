/* eslint-disable max-len, require-jsdoc */
const test = require("node:test");
const fs = require("node:fs");
const path = require("node:path");
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require("@firebase/rules-unit-testing");
const {doc, getDoc, setDoc} = require("firebase/firestore");

const projectId = "circum-rules-rider-onboarding-events-test";
const rules = fs.readFileSync(
    path.join(__dirname, "..", "..", "firestore.rules"),
    "utf8",
);

let testEnv;

test.before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId,
    firestore: {rules},
  });
});

test.after(async () => {
  await testEnv.cleanup();
});

test.beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "riderProfiles", "rider-a"), {
      riderId: "rider-a",
    });
  });
});

test("Rider cannot forge an onboarding event for another Rider", async () => {
  const db = testEnv.authenticatedContext("rider-a").firestore();
  await assertFails(setDoc(doc(db, "riderOnboardingEvents", "forged-b"), {
    riderId: "rider-b",
    eventType: "application_approved",
    status: "approved",
  }));
});

test("Rider cannot write privileged or arbitrary onboarding audit data", async () => {
  const db = testEnv.authenticatedContext("rider-a").firestore();
  await assertFails(setDoc(doc(db, "riderOnboardingEvents", "privileged"), {
    riderId: "rider-a",
    approvalStatus: "approved",
    dispatchEligible: true,
    actorRole: "super_admin",
    createdAt: new Date(),
    arbitraryMetadata: {authority: "forged"},
  }));
});

test("ordinary Rider cannot create even a benign-looking audit event", async () => {
  const db = testEnv.authenticatedContext("rider-a").firestore();
  await assertFails(setDoc(doc(db, "riderOnboardingEvents", "benign"), {
    riderId: "rider-a",
    eventType: "profile_started",
  }));
});

test("backend can create an event and Admin can read it", async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await assertSucceeds(setDoc(
        doc(context.firestore(), "riderOnboardingEvents", "backend-event"),
        {
          riderId: "rider-a",
          eventType: "profile_started",
          createdAt: new Date(),
        },
    ));
  });
  const adminDb = testEnv.authenticatedContext("admin", {
    role: "operations_admin",
  }).firestore();
  await assertSucceeds(getDoc(
      doc(adminDb, "riderOnboardingEvents", "backend-event"),
  ));
});
