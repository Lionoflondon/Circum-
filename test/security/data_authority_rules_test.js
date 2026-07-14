const assert = require("assert");
const fs = require("fs");
const path = require("path");
const test = require("node:test");

const root = path.resolve(__dirname, "..", "..");
const rules = fs.readFileSync(path.join(root, "firestore.rules"), "utf8");

function blockFor(matchLine) {
  const start = rules.indexOf(matchLine);
  assert.notStrictEqual(start, -1, `${matchLine} block is missing`);
  const next = rules.indexOf("\n    match /", start + matchLine.length);
  return rules.slice(start, next === -1 ? undefined : next);
}

test("deliveryRequests cannot be created directly by Sender or Rider clients", () => {
  const block = blockFor("match /deliveryRequests/{deliveryId}");
  assert.match(block, /allow create:\s*if isAdmin\(\);/);
  assert.doesNotMatch(block, /allow create:[^;]*(isCreatingOwnDelivery|request\.auth\.uid)/);
});

test("delivery lifecycle authority fields remain protected from client updates", () => {
  const protectedFields = [
    "status",
    "state",
    "deliveryStage",
    "dispatchStatus",
    "matchingStatus",
    "riderId",
    "assignedRiderId",
    "acceptedAt",
    "pickupArrivedAt",
    "dropoffArrivedAt",
    "collectedAt",
    "completedAt",
    "cancelledAt",
    "riderEarnings",
    "trustPoints",
    "pinVerified",
    "completionResult",
  ];
  const functionStart = rules.indexOf("function deliveryOperationalFieldsUnchanged()");
  assert.notStrictEqual(functionStart, -1, "deliveryOperationalFieldsUnchanged is missing");
  const functionEnd = rules.indexOf("function ownsSenderRecord", functionStart);
  const source = rules.slice(functionStart, functionEnd);
  for (const field of protectedFields) {
    assert.ok(source.includes(`'${field}'`), `${field} must remain backend-owned`);
  }
});

test("operational notifications are backend or admin authored only", () => {
  const block = blockFor("match /notifications/{notificationId}");
  assert.match(block, /allow create:\s*if isAdmin\(\);/);
  assert.match(block, /affectedKeys\(\)\.hasOnly\(\[\s*'read', 'readAt', 'archived', 'archivedAt', 'deletedAt'\s*\]\)/);
});

test("sender booking drafts remain callable-owned", () => {
  const block = blockFor("match /senderBookingDrafts/{uid}");
  assert.match(block, /allow read:\s*if signedIn\(\) && uid == request\.auth\.uid;/);
  assert.match(block, /allow create, update, delete:\s*if false;/);
});

test("wallet and payment ledgers remain backend-owned", () => {
  for (const collection of [
    "match /wallets/{userId}",
    "match /senderWallets/{userId}",
    "match /walletTransactions/{transactionId}",
    "match /rothLedger/{ledgerEntryId}",
  ]) {
    const block = blockFor(collection);
    assert.match(block, /allow create, update, delete:\s*if false;/);
  }
});

test("sender payment records are explicit and backend-owned", () => {
  const block = blockFor("match /senderPaymentRecords/{paymentId}");
  assert.match(block, /allow read:[\s\S]*isFinanceAdmin\(\)/);
  assert.match(block, /resource\.data\.userId == request\.auth\.uid/);
  assert.match(block, /allow create, update, delete:\s*if false;/);
});

test("activeDeliveries is explicit and limited to assigned rider location mirrors", () => {
  const block = blockFor("match /activeDeliveries/{deliveryId}");
  assert.match(block, /allow read:\s*if canReadDeliveryTracking\(deliveryId\);/);
  assert.match(block, /allow create, update:\s*if canWriteOwnActiveDeliveryLocation\(deliveryId\);/);
  assert.match(block, /allow delete:\s*if isAdmin\(\);/);

  const functionStart = rules.indexOf("function canWriteOwnActiveDeliveryLocation(deliveryId)");
  assert.notStrictEqual(functionStart, -1, "active delivery writer guard missing");
  const functionEnd = rules.indexOf("function canReadBusinessAccount", functionStart);
  const source = rules.slice(functionStart, functionEnd);
  for (const field of [
    "deliveryId",
    "riderId",
    "status",
    "riderLiveLocation",
    "trackingHealth",
    "lastBackendUploadAt",
    "updatedAt",
  ]) {
    assert.ok(source.includes(`'${field}'`), `${field} must be allowlisted`);
  }
});

test("business financial collections have explicit least-privilege rules", () => {
  const wallet = blockFor("match /business_wallets/{businessId}");
  assert.match(wallet, /allow read:[\s\S]*canReadBusinessAccount\(businessId\)/);
  assert.match(wallet, /allow create, update:\s*if isFinanceAdmin\(\);/);

  const invoices = blockFor("match /businessInvoices/{invoiceId}");
  assert.match(invoices, /allow read:[\s\S]*canReadBusinessAccount\(resource\.data\.businessId\)/);
  assert.match(invoices, /allow create:[\s\S]*canManageBusinessAccount\(request\.resource\.data\.businessId\)/);
  assert.match(invoices, /'stripePaymentIntentId'/);
  assert.match(invoices, /'paymentStatus'/);

  const payments = blockFor("match /businessInvoicePayments/{paymentId}");
  assert.match(payments, /allow create, update:\s*if isFinanceAdmin\(\);/);

  const purchases = blockFor("match /businessRothPurchases/{purchaseId}");
  assert.match(purchases, /request\.resource\.data\.status == 'pending'/);
  assert.match(purchases, /allow update:\s*if isFinanceAdmin\(\);/);
});

test("Phase 4 explicit collection rules no longer rely on the catch-all fallback", () => {
  for (const collection of [
    "match /activeDeliveries/{deliveryId}",
    "match /senderPaymentRecords/{paymentId}",
    "match /business_wallets/{businessId}",
    "match /businessInvoices/{invoiceId}",
    "match /businessInvoicePayments/{paymentId}",
    "match /businessRothPurchases/{purchaseId}",
  ]) {
    assert.notStrictEqual(rules.indexOf(collection), -1, `${collection} must be explicit`);
  }
});
