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
  productJoinProjection,
  roundMoney,
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

test("Wallet transaction view links Roth and Stripe components to one product transaction", () => {
  const view = walletTransactionView({
    id: "roth-delivery-1",
    amount: -5,
    type: TRANSACTION_TYPES.rothSpend,
    relatedEntityId: "delivery-1",
    metadata: {
      canonicalTransactionId: "txn-1",
      paymentId: "payment-1",
      productType: "delivery",
      productId: "delivery-1",
      totalAmount: 18.79,
      rothApplied: 5,
      stripeAmount: 13.79,
      stripePaymentIntentId: "pi_test",
    },
  });
  assert.equal(view.canonicalTransactionId, "txn-1");
  assert.equal(view.paymentId, "payment-1");
  assert.equal(view.deliveryId, "delivery-1");
  assert.equal(view.activityRoute, "delivery");
  assert.equal(view.totalAmount, 18.79);
  assert.equal(view.rothApplied, 5);
  assert.equal(view.stripeAmount, 13.79);
  assert.equal(view.stripePaymentIntentId, "pi_test");
  assert.equal(view.displayLabel, "Delivery payment");
  assert.equal(view.viewAllowed, true);
  assert.equal(view.viewTargetId, "delivery-1");
});

test("Wallet transaction links preserve distinct same-value product records", () => {
  const first = walletTransactionView({
    id: "debit-1", amount: -16.98,
    metadata: {canonicalTransactionId: "txn-1", productType: "delivery", productId: "delivery-1"},
  });
  const second = walletTransactionView({
    id: "debit-2", amount: -16.98,
    metadata: {canonicalTransactionId: "txn-2", productType: "delivery", productId: "delivery-2"},
  });
  assert.notEqual(first.transactionId, second.transactionId);
  assert.notEqual(first.canonicalTransactionId, second.canonicalTransactionId);
  assert.notEqual(first.deliveryId, second.deliveryId);
});

test("wallet product join projects Sender delivery, Gift, Health+, and Business targets", () => {
  const sender = productJoinProjection({
    metadata: {
      productType: "delivery",
      productId: "delivery-1",
      paymentId: "pay-1",
      customerReference: "Croydon",
    },
  });
  assert.equal(sender.activityRoute, "delivery");
  assert.equal(sender.viewTargetId, "delivery-1");
  assert.equal(sender.displayLabel, "Delivery to Croydon");
  assert.equal(sender.viewAllowed, true);

  const gift = productJoinProjection({
    metadata: {productType: "gift", giftRequestId: "gift-1", paymentId: "pay-gift"},
  });
  assert.equal(gift.activityRoute, "gift");
  assert.equal(gift.productId, "gift-1");
  assert.equal(gift.displayLabel, "Gift purchase");
  assert.equal(gift.viewAllowed, true);

  const health = productJoinProjection({
    metadata: {productType: "health_plus", healthPlusBookingId: "health-1", paymentId: "pay-health"},
  });
  assert.equal(health.activityRoute, "health_plus");
  assert.equal(health.productId, "health-1");
  assert.equal(health.authorizationContext.healthPlusRestricted, true);
  assert.equal(health.displayLabel, "Health+ delivery");

  const business = productJoinProjection({
    metadata: {productType: "business", businessId: "biz-1", invoiceId: "invoice-1", paymentId: "pay-biz"},
  });
  assert.equal(business.activityRoute, "business");
  assert.equal(business.viewTargetId, "invoice-1");
  assert.equal(business.authorizationContext.businessId, "biz-1");
  assert.equal(business.displayLabel, "Business payment");
});

test("wallet product join keeps split Roth and Stripe rails on one product target", () => {
  const roth = walletTransactionView({
    id: "roth-split",
    amount: -5,
    metadata: {
      canonicalTransactionId: "payment-1",
      paymentId: "payment-1",
      productType: "delivery",
      productId: "delivery-1",
      totalAmount: 18.79,
      rothApplied: 5,
      stripeAmount: 13.79,
    },
  });
  const stripe = walletTransactionView({
    id: "stripe-split",
    amount: -13.79,
    type: TRANSACTION_TYPES.stripePaymentRecord,
    metadata: {
      canonicalTransactionId: "payment-1",
      paymentId: "payment-1",
      productType: "delivery",
      productId: "delivery-1",
      totalAmount: 18.79,
      rothApplied: 5,
      stripeAmount: 13.79,
      stripePaymentIntentId: "pi_1",
    },
  });
  assert.equal(roth.canonicalTransactionId, stripe.canonicalTransactionId);
  assert.equal(roth.productType, stripe.productType);
  assert.equal(roth.productId, stripe.productId);
  assert.equal(roth.activityRoute, stripe.activityRoute);
  assert.equal(roundMoney(roth.rothApplied + roth.stripeAmount), roth.totalAmount);
});

test("wallet product join handles adjustments, referrals, and legacy fallback safely", () => {
  const adjustment = productJoinProjection({
    metadata: {
      productType: "delivery_adjustment",
      adjustmentId: "adj-1",
      deliveryId: "delivery-1",
    },
  });
  assert.equal(adjustment.activityRoute, "delivery");
  assert.equal(adjustment.viewTargetId, "delivery-1");
  assert.equal(adjustment.displayLabel, "Delivery adjustment");

  const referral = productJoinProjection({
    type: TRANSACTION_TYPES.referralReward,
    reason: "Referral activated after first completed activity",
    metadata: {referralCode: "ABC123", rewardReason: "Referral reward"},
  });
  assert.equal(referral.activityRoute, null);
  assert.equal(referral.viewAllowed, false);
  assert.equal(referral.displayLabel, "Referral reward");

  const legacy = productJoinProjection({type: "manual_legacy", referenceId: "sender_quote_123"});
  assert.equal(legacy.activityRoute, null);
  assert.equal(legacy.viewAllowed, false);
  assert.equal(legacy.displayLabel, "CIRCUM transaction");
});

test("product payment writers persist canonical Wallet join metadata", () => {
  const gifts = fs.readFileSync("gifts-payment.js", "utf8");
  assert.match(gifts, /productType: "gift"/);
  assert.match(gifts, /giftRequestId: giftDraftId/);
  assert.match(gifts, /canonicalTransactionId: session\.id/);
  assert.match(gifts, /stripeAmount: gross/);

  const health = fs.readFileSync("health-plus.js", "utf8");
  assert.match(health, /productType: "health_plus"/);
  assert.match(health, /healthPlusBookingId: bookingId/);
  assert.match(health, /rothApplied: rothAmount/);
  assert.match(health, /stripeAmount: cardAmount/);

  const business = fs.readFileSync("business-payments.js", "utf8");
  assert.match(business, /productType: "business"/);
  assert.match(business, /businessId,\s*\n\s*invoiceId,/);
  assert.match(business, /canonicalTransactionId: paymentRef\.id/);
  assert.match(business, /stripeAmount: normalizedCardAmount/);
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

test("sender wallet history authorizes product links before exposing view targets", () => {
  const source = fs.readFileSync("roth-ledger.js", "utf8");
  assert.match(source, /async function authorizedWalletProductJoin/);
  assert.match(source, /activityRoute === "health_plus"/);
  assert.match(source, /businessAuthority\(account, \{uid, email\}\)\.member === true/);
  assert.match(source, /viewAllowed: false/);
  assert.match(source, /Promise\.all\(rawRecords\.map\(\(record\) =>\s*authorizedWalletProductJoin/);
});
