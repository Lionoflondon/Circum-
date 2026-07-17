/* eslint-disable max-len */
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const rules = fs.readFileSync(
    path.join(__dirname, "..", "..", "firestore.rules"),
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

test("Firestore rules restrict rider private writes to verification.rider", () => {
  assert.match(rules, /function isAssignedRiderPrivateCreate\(\)[\s\S]*request\.resource\.data\.verification\.keys\(\)\.hasOnly\(\['rider'\]\)/);
  assert.match(rules, /function isAssignedRiderPrivateUpdate\(\)[\s\S]*request\.resource\.data\.verification\.keys\(\)\.hasOnly\(\['rider'\]\)/);
  assert.doesNotMatch(rules, /isAssignedRiderUpdate\(\)[\s\S]*changedKeys\(\)\.hasOnly\(\['iris'/);
});

test("Firestore rules keep referrals admin-only", () => {
  assert.match(rules, /match \/irisReferrals\/\{referralId\}[\s\S]*allow read, write: if isAdmin\(\);/);
});

test("Firestore rules reserve rider rank changes for driver managers", () => {
  assert.match(
      rules,
      /match \/riderProfiles\/\{driverId\}[\s\S]*allow update: if isDriverManager\(\)/,
  );
  assert.match(
      rules,
      /changedKeys\(\)\.hasAny\(\[[\s\S]*'rank'[\s\S]*'riderRank'[\s\S]*'rankUpdatedBy'/,
  );
});
