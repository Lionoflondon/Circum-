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

test("sender wallet history prefers canonical walletId query with bounded legacy fallback", () => {
  const source = fs.readFileSync("roth-ledger.js", "utf8");
  assert.match(source, /collection\("walletTransactions"\)\s*\.where\("walletId", "==", identity\.walletId\)\s*\.orderBy\("createdAt", "desc"\)\s*\.limit\(100\)/);
  assert.match(source, /walletSnap\.empty \? await db\.collection\("walletTransactions"\)\s*\.where\("uid", "==", context\.auth\.uid\)\s*\.orderBy\("createdAt", "desc"\)\s*\.limit\(100\)/);
});
