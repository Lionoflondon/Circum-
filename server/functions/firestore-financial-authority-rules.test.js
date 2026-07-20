/* eslint-disable max-len */
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const rules = fs.readFileSync(
    path.join(__dirname, "..", "..", "firestore.rules"),
    "utf8",
);
const index = fs.readFileSync(path.join(__dirname, "index.js"), "utf8");
const websiteApp = fs.readFileSync(
    path.join(__dirname, "..", "..", "lib", "website", "shared", "circum_website_app.dart"),
    "utf8",
);

test("deliveryRequests reserves payment and lifecycle fields for backend/admin authority", () => {
  assert.match(rules, /function protectedDeliveryFields\(\)/);
  for (const field of [
    "paymentStatus",
    "stripePaymentIntentId",
    "deliveryStage",
    "deliveryStatus",
    "status",
    "driverPayout",
    "completedAt",
    "pinVerified",
    "auditTrail",
  ]) {
    assert.match(rules, new RegExp(`'${field}'`));
  }
  assert.match(
      rules,
      /function isOwnDeliveryUpdate\(\)[\s\S]*affectedKeys\(\)\.hasAny\(protectedDeliveryFields\(\)\)/,
  );
  assert.match(
      rules,
      /function isSafeDeliveryCreate\(\)[\s\S]*keys\(\)\.hasAny\(protectedFinancialCreateFields\(\)\)/,
  );
});

test("assigned riders can only make non-authoritative offer preference updates directly", () => {
  assert.match(
      rules,
      /function isAssignedRiderUpdate\(\)[\s\S]*affectedKeys\(\)\.hasOnly\(\[[\s\S]*'rejectedByRiders'[\s\S]*'ignoredByRiders'[\s\S]*'updatedAt'/,
  );
  assert.doesNotMatch(
      rules,
      /function isAssignedRiderUpdate\(\)[\s\S]*'deliveryStage'/,
  );
});

test("rider earnings, wallet ledger, payout requests, and bank data are not client-writable", () => {
  assert.match(
      rules,
      /match \/riderEarnings\/\{riderId\}[\s\S]*allow create, update: if isAdmin\(\);/,
  );
  assert.match(
      rules,
      /match \/riderWalletTransactions\/\{transactionId\}[\s\S]*allow create: if isAdmin\(\);/,
  );
  assert.match(
      rules,
      /match \/payoutRequests\/\{requestId\}[\s\S]*allow create: if isAdmin\(\);/,
  );
  assert.match(
      rules,
      /match \/riderBankAccounts\/\{riderId\}[\s\S]*allow read: if isAdmin\(\);[\s\S]*allow create, update: if isAdmin\(\);/,
  );
});

test("rider self updates are field allowlisted and cannot alter admin authority", () => {
  assert.match(rules, /function riderAdminOnlyFields\(\)/);
  assert.match(rules, /function riderSelfWritableFields\(\)/);
  assert.match(rules, /function isSafeRiderSelfCreate\(driverId\)/);
  assert.match(rules, /function isSafeRiderSelfUpdate\(driverId\)/);
  for (const field of [
    "approvalStatus",
    "verificationStatus",
    "role",
    "roles",
    "riderRank",
    "trustPoints",
    "availableBalance",
    "stripeConnectAccountId",
  ]) {
    assert.match(rules, new RegExp(`'${field}'`));
  }
  assert.match(
      rules,
      /match \/riders\/\{driverId\}[\s\S]*allow create: if isDriverManager\(\) \|\| isSafeRiderSelfCreate\(driverId\);[\s\S]*allow update: if isDriverManager\(\) \|\| isSafeRiderSelfUpdate\(driverId\);/,
  );
});

test("Rider withdrawal requests are routed through the backend callable", () => {
  assert.match(index, /exports\.requestRiderWithdrawal = riderConnect\.requestRiderWithdrawal\(\);/);
  assert.match(websiteApp, /httpsCallable\('requestRiderWithdrawal'\)/);
  assert.doesNotMatch(websiteApp, /collection\('payoutRequests'\)\.doc\(\)[\s\S]*batch\.set\(requestRef/);
  assert.doesNotMatch(websiteApp, /collection\('riderBankAccounts'\)\.doc\(user\.uid\)/);
});
