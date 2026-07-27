/* eslint-disable max-len */
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const rules = fs.readFileSync(
    path.join(__dirname, "..", "..", "firestore.rules"),
    "utf8",
);
const sendPackage = fs.readFileSync(
    path.join(__dirname, "send-package.js"),
    "utf8",
);

test("Firestore rules expose irisPrivate to admins only for reads", () => {
  assert.match(rules, /match \/irisPrivate\/\{requestId\}/);
  assert.match(rules, /allow read: if isAdmin\(\);/);
});

test("Firestore rules prevent senders from mutating public Iris", () => {
  assert.match(rules, /function isOwnDeliveryUpdate\(\)[\s\S]*affectedKeys\(\)\.hasAny\(\['iris'\]\)/);
  assert.match(rules, /match \/webSenderRequests\/\{requestId\}[\s\S]*changedKeys\(\)\.hasAny\(\['iris'\]\)/);
});

test("Firestore rules reject create-time Iris injection from clients", () => {
  assert.match(rules, /function isSafeDeliveryCreate\(\)[\s\S]*!request\.resource\.data\.keys\(\)\.hasAny\(\['iris'\]\)/);
  assert.match(rules, /match \/webSenderRequests\/\{requestId\}[\s\S]*allow create: if isAdmin\(\) \|\| \(\s*isCreatingOwnDelivery\(\) &&\s*!request\.resource\.data\.keys\(\)\.hasAny\(\['iris'\]\)\s*\);/);
});

test("Firestore rules restrict rider private writes to verification.rider", () => {
  assert.match(rules, /function isAssignedRiderPrivateCreate\(\)[\s\S]*request\.resource\.data\.verification\.keys\(\)\.hasOnly\(\['rider'\]\)/);
  assert.match(rules, /function isAssignedRiderPrivateUpdate\(\)[\s\S]*request\.resource\.data\.verification\.keys\(\)\.hasOnly\(\['rider'\]\)/);
  assert.doesNotMatch(rules, /isAssignedRiderUpdate\(\)[\s\S]*changedKeys\(\)\.hasOnly\(\['iris'/);
});

test("Firestore rules keep referrals admin-only", () => {
  assert.match(rules, /match \/irisReferrals\/\{referralId\}[\s\S]*allow read, write: if isAdmin\(\);/);
});

test("Firestore rules expose IRIS learning review collections to admins", () => {
  assert.match(rules, /match \/irisLearningCases\/\{caseId\}[\s\S]*allow read, create, update: if isAdmin\(\);/);
  assert.match(rules, /match \/iris_learning_review_candidates\/\{candidateId\}[\s\S]*allow read, update: if isAdmin\(\);[\s\S]*allow create: if false;/);
  assert.match(rules, /match \/irisCanonicalObjects\/\{objectId\}[\s\S]*allow read, create, update: if isAdmin\(\);/);
});

test("IRIS dispatch callable requires delivery owner or admin", () => {
  assert.match(sendPackage, /const \{hasAdminClaim\} = require\("\.\/admin-auth"\)/);
  assert.match(sendPackage, /function senderOwnsRequest\(delivery, uid\)/);
  assert.match(sendPackage, /!senderOwnsRequest\(deliveryRequest\[0\], uid\)/);
  assert.match(sendPackage, /!hasAdminClaim\(context\.auth\.token \|\| \{\}\)/);
  assert.match(sendPackage, /Only the Sender or an administrator can dispatch this delivery/);
  assert.match(sendPackage, /e instanceof functions\.https\.HttpsError/);
});

test("IRIS dispatch records audit when server recomputation blocks dispatch", () => {
  assert.match(sendPackage, /dispatchComplianceDecision\(deliveryRequest\[0\]\)/);
  assert.match(sendPackage, /actionType: "iris_dispatch_blocked"/);
  assert.match(sendPackage, /storedIrisMismatch: dispatchDecision\.storedIrisMismatch === true/);
});

test("legacy sendPackage request lookup remains bounded", () => {
  assert.match(
      sendPackage,
      /collection\("deliveryRequests"\) \.where\("requestId", "==", requestId\)\.limit\(1\)\.get\(\)/,
  );
});

test("Firestore rules reserve rider authority changes for driver managers", () => {
  assert.match(
      rules,
      /match \/riderProfiles\/\{driverId\}[\s\S]*allow create: if isDriverManager\(\) \|\| isSafeRiderSelfCreate\(driverId\);[\s\S]*allow update: if isDriverManager\(\) \|\| isSafeRiderSelfUpdate\(driverId\);/,
  );
  assert.match(
      rules,
      /function riderAdminOnlyFields\(\)[\s\S]*'approvalStatus'[\s\S]*'verificationStatus'[\s\S]*'driverStatus'[\s\S]*'rank'[\s\S]*'riderRank'/,
  );
});
