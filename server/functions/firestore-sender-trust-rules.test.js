/* eslint-disable max-len, require-jsdoc */
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require("@firebase/rules-unit-testing");
const {
  collection,
  collectionGroup,
  deleteDoc,
  doc,
  getDocs,
  query,
  setDoc,
  updateDoc,
  where,
} = require("firebase/firestore");

const projectId = "circum-rules-sender-trust-test";
const rules = fs.readFileSync(
    path.join(__dirname, "..", "..", "firestore.rules"),
    "utf8",
);
const profileSource = fs.readFileSync(
    path.join(__dirname, "..", "..", "lib", "app", "sender_mobile", "sender_mobile_profile.dart"),
    "utf8",
);

let testEnv;

async function seedTrustEvent(id, data) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "senderTrustEvents", id), {
      userId: "sender-1",
      eventType: "system_baseline_sync",
      pointsChange: 1,
      source: "system",
      createdAt: new Date("2026-07-31T12:00:00Z"),
      ...data,
    });
  });
}

function trustQuery(db, uid = "sender-1") {
  return getDocs(query(
      collection(db, "senderTrustEvents"),
      where("userId", "==", uid),
  ));
}

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
  await seedTrustEvent("event-sender-1", {userId: "sender-1"});
  await seedTrustEvent("event-sender-2", {userId: "sender-2"});
});

test("senderTrustEvents rule is least privilege and matches the profile query", () => {
  assert.match(rules, /function canReadSenderTrustEvent\(\)/);
  assert.match(rules, /match \/senderTrustEvents\/\{eventId\}/);
  assert.match(
      rules,
      /resource\.data\.userId == request\.auth\.uid/,
  );
  assert.match(
      rules,
      /match \/\{path=\*\*\}\/senderTrustEvents\/\{eventId\}/,
  );
  assert.match(rules, /allow create, update, delete: if false;/);
  assert.match(profileSource, /collection\('senderTrustEvents'\)[\s\S]*where\('userId', isEqualTo: user\.uid\)/);
});

test("owner can read their own sender trust history with the production query", async () => {
  const db = testEnv.authenticatedContext("sender-1").firestore();
  await assertSucceeds(trustQuery(db, "sender-1"));
});

test("another authenticated user cannot read a sender's trust history", async () => {
  const db = testEnv.authenticatedContext("sender-2").firestore();
  await assertFails(trustQuery(db, "sender-1"));
});

test("anonymous users cannot read sender trust history", async () => {
  const db = testEnv.unauthenticatedContext().firestore();
  await assertFails(trustQuery(db, "sender-1"));
});

test("clients cannot create, update, or delete sender trust events", async () => {
  const db = testEnv.authenticatedContext("sender-1").firestore();
  const eventRef = doc(db, "senderTrustEvents", "event-sender-1");
  await assertFails(setDoc(doc(db, "senderTrustEvents", "client-created"), {
    userId: "sender-1",
    eventType: "client_created",
  }));
  await assertFails(updateDoc(eventRef, {pointsChange: 999}));
  await assertFails(deleteDoc(eventRef));
});

test("unfiltered collection queries cannot leak another sender's trust history", async () => {
  const db = testEnv.authenticatedContext("sender-1").firestore();
  await assertFails(getDocs(collection(db, "senderTrustEvents")));
});

test("collection group queries remain secure and require owner constraints", async () => {
  const ownerDb = testEnv.authenticatedContext("sender-1").firestore();
  const otherDb = testEnv.authenticatedContext("sender-2").firestore();
  await assertSucceeds(getDocs(query(
      collectionGroup(ownerDb, "senderTrustEvents"),
      where("userId", "==", "sender-1"),
  )));
  await assertFails(getDocs(query(
      collectionGroup(otherDb, "senderTrustEvents"),
      where("userId", "==", "sender-1"),
  )));
});
