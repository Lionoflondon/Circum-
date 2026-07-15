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

test("conversation lifecycle and messages are callable-owned", () => {
  const block = blockFor("match /chats/{chatId}");
  assert.match(block, /allow read:\s*if isAdmin\(\) \|\| isParticipant\(\);/);
  assert.match(block, /allow create, update, delete:\s*if false;/);
  assert.match(block, /match \/messages\/\{messageId\} \{/);
  assert.match(block, /allow create:\s*if false;/);
  assert.match(block, /allow update, delete:\s*if false;/);
});

test("support tickets are backend or narrowly web-live-chat authored only", () => {
  const block = blockFor("match /supportTickets/{ticketId}");
  assert.match(block, /allow read, write:\s*if isAdmin\(\);/);
  assert.match(block, /request\.resource\.data\.channel == 'web_live_chat'/);
  assert.doesNotMatch(block, /sender_in_app_chat/);
});

test("sender booking drafts remain callable-owned", () => {
  const block = blockFor("match /senderBookingDrafts/{uid}");
  assert.match(block, /allow read:\s*if signedIn\(\) && uid == request\.auth\.uid;/);
  assert.match(block, /allow create, update, delete:\s*if false;/);
});

test("gift payment drafts cannot carry client-authored settlement amounts", () => {
  const block = blockFor("match /giftPaymentDrafts/{giftDraftId}");
  assert.match(block, /request\.resource\.data\.paymentStatus == 'payment_pending'/);
  assert.match(block, /request\.resource\.data\.rothApplied == 0/);
  assert.match(block, /request\.resource\.data\.walletContributionGbp == 0/);
  assert.match(block, /request\.resource\.data\.cardAmount == request\.resource\.data\.grossBudget/);
  assert.match(block, /request\.resource\.data\.remainingStripeAmountGbp == request\.resource\.data\.grossBudget/);
  assert.match(block, /allow update, delete:\s*if isAdmin\(\);/);
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

test("ratings, tips, reports, and appreciation events are backend-owned", () => {
  for (const collection of [
    "match /driverRatings/{ratingId}",
    "match /deliveryTips/{tipId}",
    "match /ratingReports/{reportId}",
    "match /notificationEvents/{eventId}",
  ]) {
    const block = blockFor(collection);
    assert.match(block, /allow create[^;]*if false|allow create, update, delete:\s*if false/);
    assert.match(block, /allow delete:\s*if false|allow create, update, delete:\s*if false/);
  }
  const ratings = blockFor("match /driverRatings/{ratingId}");
  assert.match(ratings, /allow update:\s*if false/);
});

test("sender payment records are explicit and backend-owned", () => {
  const block = blockFor("match /senderPaymentRecords/{paymentId}");
  assert.match(block, /allow read:[\s\S]*isFinanceAdmin\(\)/);
  assert.match(block, /resource\.data\.userId == request\.auth\.uid/);
  assert.match(block, /allow create, update, delete:\s*if false;/);
});

test("tracking mirrors are explicit and backend-owned", () => {
  const deliveryRequests = blockFor("match /deliveryRequests/{deliveryId}");
  assert.match(deliveryRequests, /match \/tracking\/\{trackingId\} \{/);
  assert.match(deliveryRequests, /allow read:\s*if canReadDeliveryTracking\(deliveryId\);/);
  assert.match(deliveryRequests, /allow create, update:\s*if false;/);

  const block = blockFor("match /activeDeliveries/{deliveryId}");
  assert.match(block, /allow read:\s*if canReadDeliveryTracking\(deliveryId\);/);
  assert.match(block, /allow create, update:\s*if false;/);
  assert.match(block, /allow delete:\s*if isAdmin\(\);/);
});

test("Rider IRIS acknowledgements are explicit and backend-owned", () => {
  const block = blockFor("match /riderIrisAcknowledgements/{deliveryId}");
  assert.match(block, /allow read:\s*if canReadDeliveryTracking\(deliveryId\);/);
  assert.match(block, /allow create, update, delete:\s*if false;/);
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
