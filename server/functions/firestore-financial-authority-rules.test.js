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
  assert.match(rules, /function directContactFields\(\)/);
  assert.match(rules, /function publicDeliveryHasNoDirectContact\(data\)/);
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
  assert.match(
      rules,
      /function isSafeDeliveryCreate\(\)[\s\S]*publicDeliveryHasNoDirectContact\(request\.resource\.data\)/,
  );
  assert.match(
      rules,
      /function isOwnDeliveryUpdate\(\)[\s\S]*publicDeliveryHasNoDirectContact\(request\.resource\.data\)/,
  );
  for (const field of [
    "phone",
    "phoneNumber",
    "mobile",
    "contactNumber",
    "riderPhone",
    "senderPhone",
    "driverPhone",
    "courierPhone",
    "receiverPhone",
  ]) {
    assert.match(rules, new RegExp(`'${field}'`));
  }
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

test("riderProfiles mirrors riders admin-only authority fields", () => {
  assert.match(rules, /function riderAdminOnlyFields\(\)/);
  assert.match(
      rules,
      /match \/riderProfiles\/\{driverId\}[\s\S]*allow create: if isDriverManager\(\) \|\| isSafeRiderSelfCreate\(driverId\);[\s\S]*allow update: if isDriverManager\(\) \|\| isSafeRiderSelfUpdate\(driverId\);/,
  );
  for (const field of [
    "approvalStatus",
    "verificationStatus",
    "driverStatus",
    "role",
    "roles",
    "trustPoints",
    "stripeConnectAccountId",
  ]) {
    assert.match(rules, new RegExp(`'${field}'`));
  }
});

test("users cannot self-write admin or rider role escalation fields", () => {
  assert.match(rules, /function userAdminOnlyRoleFields\(\)/);
  assert.match(rules, /function hasUnsafeSelfUserRoleCreate\(\)/);
  assert.match(rules, /function hasUnsafeSelfUserTypeUpdate\(\)/);
  assert.match(
      rules,
      /match \/users\/\{userId\}[\s\S]*!request\.resource\.data\.keys\(\)\.hasAny\(userAdminOnlyRoleFields\(\)\)[\s\S]*!hasUnsafeSelfUserRoleCreate\(\)[\s\S]*!hasUnsafeSelfUserTypeCreate\(\)/,
  );
});

test("users cannot choose Stripe customer identity", () => {
  const block = rules.match(/function userAdminOnlyRoleFields\(\) \{[\s\S]*?\n {4}\}/)[0];
  assert.match(block, /'stripeCustomerId'/);
  assert.match(block, /'customerId'/);
});

test("rider earnings, wallet ledger, payout requests, and bank data are not client-writable", () => {
  const earningsBlock = rules.match(/match \/riderEarnings\/\{riderId\} \{[\s\S]*?\n {4}\}/)[0];
  assert.match(
      earningsBlock,
      /allow create, update, delete: if false;/,
  );
  assert.match(
      rules,
      /match \/riderWalletTransactions\/\{transactionId\}[\s\S]*allow create, update, delete: if false;/,
  );
  assert.match(
      rules,
      /match \/payoutRequests\/\{requestId\}[\s\S]*allow create: if isAdmin\(\);/,
  );
  assert.match(
      rules,
      /match \/riderBankAccounts\/\{riderId\}[\s\S]*allow read: if isAdmin\(\);[\s\S]*allow create, update: if isAdmin\(\);/,
  );
  assert.match(
      rules,
      /match \/riderEarningsReconciliations\/\{reconciliationId\}[\s\S]*allow read: if isFinanceAdmin\(\);[\s\S]*allow write: if false;/,
  );
});

test("ratings, tips, and reconciliation are backend-authored", () => {
  for (const collection of ["driverRatings", "deliveryTips", "ratingReports"]) {
    assert.match(rules, new RegExp(`match /${collection}/\\{[^}]+\\} \\{[\\s\\S]*allow create[^;]*if false;`));
  }
  assert.match(rules, /match \/tipReconciliations\/\{recordId\}[\s\S]*allow read: if isFinanceAdmin\(\);[\s\S]*allow create, update, delete: if false;/);
});

test("no-show settlement, Rider credit, and platform effect are server-authored", () => {
  for (const collection of [
    "riderEarningTransactions",
    "noShowSettlements",
    "platformSettlementTransactions",
  ]) {
    const block = rules.match(new RegExp(`match /${collection}/\\{[^}]+\\} \\{[\\s\\S]*?\\n {4}\\}`))[0];
    assert.match(block, /allow create, update, delete: if false;/);
    assert.match(rules, new RegExp(`'${collection}'`));
  }
});

test("Stripe Connect webhook replay ledger is server-owned only", () => {
  assert.match(
      rules,
      /match \/stripeConnectWebhookEvents\/\{eventId\} \{[\s\S]*allow read, write: if false;/,
  );
});

test("referral, Roth, quote, and payment-session authority is server-only", () => {
  for (const collection of [
    "wallets",
    "walletTransactions",
    "referrals",
    "referralCodes",
    "senderBookingQuotes",
    "senderPaymentSessions",
  ]) {
    assert.match(
        rules,
        new RegExp(`match /${collection}/\\{[^}]+\\} \\{[\\s\\S]*?allow create, update, delete: if false;`),
    );
  }
});

test("rider applications and documents are backend/admin write-authoritative", () => {
  assert.match(
      rules,
      /match \/riderApplications\/\{applicationId\} \{[\s\S]*applicationId == request\.auth\.uid[\s\S]*resource\.data\.riderId == request\.auth\.uid[\s\S]*allow create, update: if isAdmin\(\);/,
  );
  assert.match(
      rules,
      /match \/riderDocuments\/\{documentId\} \{[\s\S]*allow read: if isAdmin\(\) \|\|[\s\S]*resource\.data\.riderId == request\.auth\.uid[\s\S]*allow create, update: if isAdmin\(\);/,
  );
});

test("notifications are backend authored only", () => {
  const notificationBlock = rules.match(
      /match \/notifications\/\{notificationId\} \{[\s\S]*?\n {4}\}/,
  )[0];
  assert.match(
      notificationBlock,
      /allow create, update: if false;/,
  );
  assert.doesNotMatch(
      notificationBlock,
      /allow create[^;]*isAdmin\(\)/,
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
