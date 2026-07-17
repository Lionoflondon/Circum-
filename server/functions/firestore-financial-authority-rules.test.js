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
const webSender = fs.readFileSync(
    path.join(__dirname, "..", "..", "lib", "web_sender_app.dart"),
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
      /function isOwnDeliveryUpdate\(\)[\s\S]*changedKeys\(\)\.hasAny\(protectedDeliveryFields\(\)\)/,
  );
  assert.match(
      rules,
      /function isSafeDeliveryCreate\(\)[\s\S]*keys\(\)\.hasAny\(protectedFinancialCreateFields\(\)\)/,
  );
});

test("assigned riders can only make non-authoritative offer preference updates directly", () => {
  assert.match(
      rules,
      /function isAssignedRiderUpdate\(\)[\s\S]*changedKeys\(\)\.hasOnly\(\[[\s\S]*'rejectedByRiders'[\s\S]*'ignoredByRiders'[\s\S]*'updatedAt'/,
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

test("Rider withdrawal requests are routed through the backend callable", () => {
  assert.match(index, /exports\.requestRiderWithdrawal = riderConnect\.requestRiderWithdrawal\(\);/);
  assert.match(webSender, /httpsCallable\('requestRiderWithdrawal'\)/);
  assert.doesNotMatch(webSender, /collection\('payoutRequests'\)\.doc\(\)[\s\S]*batch\.set\(requestRef/);
  assert.doesNotMatch(webSender, /collection\('riderBankAccounts'\)\.doc\(user\.uid\)/);
});
