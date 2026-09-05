/* eslint-disable max-len */
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const {
  BALANCE_TYPES,
  LEDGER_EVENTS,
  TRANSACTION_TYPES,
  canWithdraw,
  isRothCreditWithdrawable,
  ledgerTransactionRecord,
  nextBalance,
  paginateWalletTransactions,
  senderWalletProjectionRecord,
  senderWalletRecord,
  verifiedStripePaidGbpSession,
  verifiedStripeRothPurchase,
  walletTransactionView,
} = require("./roth-ledger-core");

test("Roth credit is not withdrawable", () => {
  assert.equal(isRothCreditWithdrawable(), false);
  assert.equal(canWithdraw(BALANCE_TYPES.rothCredit), false);
  assert.equal(canWithdraw(BALANCE_TYPES.pendingEarnings), false);
  assert.equal(canWithdraw(BALANCE_TYPES.availableEarnings), true);
});

test("Sender Wallet projection is ROTH, versioned and never negative", () => {
  const wallet = senderWalletProjectionRecord({
    userId: "sender-1",
    balance: 42,
    version: 3,
    createdAt: "created",
  });
  assert.equal(wallet.currency, "ROTH");
  assert.equal(wallet.status, "active");
  assert.equal(wallet.version, 3);
  assert.throws(() => senderWalletProjectionRecord({
    userId: "sender-1",
    balance: -1,
  }), /cannot be negative/);
});

test("Wallet transaction view and pagination preserve newest-first ledger order", () => {
  const transactions = [
    {...walletTransactionView({id: "old", amount: 5, createdAt: "old"}), createdAtMillis: 1},
    {...walletTransactionView({id: "new", amount: -2, createdAt: "new"}), createdAtMillis: 2},
  ];
  const page = paginateWalletTransactions(transactions, {pageSize: 1});
  assert.equal(page.records[0].transactionId, "new");
  assert.equal(page.records[0].direction, "debit");
  assert.equal(page.nextPageToken, "1");
});

test("Roth credit cannot go negative unless reversal is explicit", () => {
  assert.throws(() => nextBalance({
    balanceBefore: 10,
    amount: -20,
    type: TRANSACTION_TYPES.adminDebit,
  }), /cannot go negative/);
  assert.equal(nextBalance({
    balanceBefore: 10,
    amount: -20,
    type: TRANSACTION_TYPES.reversal,
  }), -10);
});

test("sender Roth wallet uses canonical Gifts-ready fields", () => {
  const wallet = senderWalletRecord({
    walletId: "wallet-1",
    userId: "sender-1",
    email: "Sender@Example.com",
    balance: 200,
    createdAt: "now",
  });
  assert.equal(wallet.walletType, "sender");
  assert.equal(wallet.email, "sender@example.com");
  assert.equal(wallet.balance, 200);
  assert.equal(wallet.currencyEquivalent, "GBP");
});

test("Roth gift debit and refund ledger records are auditable", () => {
  const debit = ledgerTransactionRecord({
    transactionId: "tx-debit",
    walletId: "wallet-1",
    userId: "sender-1",
    email: "sender@example.com",
    type: TRANSACTION_TYPES.giftPaymentDebit,
    direction: "debit",
    amount: 50,
    balanceBefore: 200,
    source: "gifts",
    referenceType: "giftPaymentDraft",
    referenceId: "gift-1",
    reason: "Gift payment Roth debit.",
    createdBy: "system",
  });
  assert.equal(debit.balanceAfter, 150);
  assert.equal(debit.direction, "debit");

  const refund = ledgerTransactionRecord({
    transactionId: "tx-refund",
    walletId: "wallet-1",
    userId: "sender-1",
    email: "sender@example.com",
    type: TRANSACTION_TYPES.refundCredit,
    direction: "credit",
    amount: 50,
    balanceBefore: 150,
    source: "gifts",
    referenceType: "giftPaymentDraft",
    referenceId: "gift-1",
    reason: "Refund Roth after failed card payment.",
    createdBy: "system",
  });
  assert.equal(refund.balanceAfter, 200);
  assert.equal(LEDGER_EVENTS.paymentRefunded, "roth_payment_refunded");
  assert.equal(LEDGER_EVENTS.paymentFailed, "roth_payment_failed");
});

test("verified Stripe Roth purchase issues Roth 1:1 from paid GBP", () => {
  for (const amount of [5, 50, 5000]) {
    const purchase = verifiedStripeRothPurchase({
      id: `cs_${amount}`,
      payment_status: "paid",
      currency: "gbp",
      amount_total: amount * 100,
      payment_intent: `pi_${amount}`,
      client_reference_id: "sender-1",
    }, {ownerId: "sender-1"});
    assert.equal(purchase.amountGBP, amount);
    assert.equal(purchase.rothIssued, amount);
    assert.equal(purchase.currency, "GBP");
    assert.equal(purchase.paymentIntentId, `pi_${amount}`);
  }
});

test("verified Stripe Roth purchase rejects unsafe sessions", () => {
  assert.throws(() => verifiedStripeRothPurchase({
    payment_status: "unpaid",
    currency: "gbp",
    amount_total: 500,
  }, {ownerId: "sender-1"}), /not been verified as paid/);
  assert.throws(() => verifiedStripeRothPurchase({
    payment_status: "paid",
    currency: "usd",
    amount_total: 500,
  }, {ownerId: "sender-1"}), /must be paid in GBP/);
  assert.throws(() => verifiedStripeRothPurchase({
    payment_status: "paid",
    currency: "gbp",
    amount_total: 0,
  }, {ownerId: "sender-1"}), /greater than zero/);
  assert.throws(() => verifiedStripeRothPurchase({
    payment_status: "paid",
    currency: "gbp",
    amount_total: 500,
  }), /owner could not be verified/);
  assert.throws(() => verifiedStripeRothPurchase({
    payment_status: "paid",
    currency: "gbp",
    amount_total: 500,
    client_reference_id: "sender-2",
  }, {ownerId: "sender-1"}), /owner does not match/);
});

test("verified Stripe paid GBP session rejects mismatched expected amount", () => {
  assert.throws(() => verifiedStripePaidGbpSession({
    payment_status: "paid",
    currency: "gbp",
    amount_total: 499,
    client_reference_id: "sender-1",
  }, {ownerId: "sender-1", expectedAmountGBP: 5}), /amount does not match/);
  const verified = verifiedStripePaidGbpSession({
    payment_status: "paid",
    currency: "gbp",
    amount_total: 500,
    client_reference_id: "sender-1",
  }, {ownerId: "sender-1", expectedAmountGBP: 5});
  assert.equal(verified.amountGBP, 5);
});

test("sender wallet history prefers canonical walletId query with bounded legacy fallback", () => {
  const source = fs.readFileSync("roth-ledger.js", "utf8");
  assert.match(source, /collection\("walletTransactions"\)\s*\.where\("walletId", "==", identity\.walletId\)\s*\.orderBy\("createdAt", "desc"\)\s*\.limit\(100\)/);
  assert.match(source, /walletSnap\.empty \? await db\.collection\("walletTransactions"\)\s*\.where\("uid", "==", context\.auth\.uid\)\s*\.orderBy\("createdAt", "desc"\)\s*\.limit\(100\)/);
});

test("new Sender accounts receive an idempotent 5 Roth welcome ledger credit", () => {
  const source = fs.readFileSync("roth-ledger.js", "utf8");
  assert.match(source, /const SENDER_WELCOME_ROTH_AMOUNT = 5;/);
  assert.match(source, /async function grantSenderWelcomeRoth/);
  assert.match(source, /const transactionId = `sender_welcome_roth_\$\{cleanUid\}`;/);
  assert.match(source, /idempotencyKey: `sender_welcome_roth:\$\{cleanUid\}`/);
  assert.match(source, /type: TRANSACTION_TYPES\.promotionalReward/);
  assert.match(source, /policy: "new_sender_account_starter_roth"/);
  assert.match(source, /repairPendingSenderWelcomeRoth\(context, "initialiseSenderWallet"\)/);
});
