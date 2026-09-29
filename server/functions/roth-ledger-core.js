/* eslint-disable max-len, require-jsdoc */
"use strict";

const BALANCE_TYPES = Object.freeze({
  rothCredit: "rothCredit",
  pendingEarnings: "pendingEarnings",
  availableEarnings: "availableEarnings",
});

const TRANSACTION_TYPES = Object.freeze({
  adminIssue: "admin_issue",
  giftPaymentDebit: "gift_payment_debit",
  refundCredit: "refund_credit",
  adjustment: "adjustment",
  rothCredit: "roth_credit",
  rothDebit: "roth_debit",
  rothSpend: "roth_spend",
  giftCardRedeem: "gift_card_redeem",
  userTopUp: "USER_TOP_UP",
  rewardCredit: "reward_credit",
  referralReward: "referral_reward",
  referralWelcomeReward: "referral_welcome_reward",
  adminCredit: "admin_credit",
  adminDebit: "admin_debit",
  earningsPending: "earnings_pending",
  earningsAvailable: "earnings_available",
  withdrawal: "withdrawal",
  stripePaymentRecord: "stripe_payment_record",
  refundRecord: "refund_record",
  rothCardConversion: "roth_card_conversion",
  checkoutSpend: "checkout_spend",
  refund: "refund",
  promotionalReward: "promotional_reward",
  reversal: "reversal",
});

const LEDGER_EVENTS = Object.freeze({
  walletCreated: "roth_wallet_created",
  adminIssued: "roth_admin_issued",
  paymentDebited: "roth_payment_debited",
  paymentRefunded: "roth_payment_refunded",
  paymentFailed: "roth_payment_failed",
});

function roundMoney(value) {
  const amount = Number(value || 0);
  if (!Number.isFinite(amount)) return 0;
  return Math.round(amount * 100) / 100;
}

function verifiedStripePaidGbpSession(sessionData, {
  ownerId = "",
  ownerEmail = "",
  expectedAmountGBP = null,
} = {}) {
  const session = sessionData || {};
  if (`${session.payment_status || ""}`.toLowerCase() !== "paid") {
    throw new Error("Stripe payment has not been verified as paid.");
  }
  const currency = `${session.currency || ""}`.toLowerCase();
  if (currency !== "gbp") {
    throw new Error("Stripe payment must be paid in GBP.");
  }
  const amountPence = Number(session.amount_total || 0);
  if (!Number.isInteger(amountPence) || amountPence <= 0) {
    throw new Error("Stripe payment amount must be greater than zero.");
  }
  if (!`${ownerId || ""}`.trim() && !`${ownerEmail || ""}`.trim()) {
    throw new Error("Stripe payment owner could not be verified.");
  }
  const referenceOwner = `${session.client_reference_id || ""}`.trim();
  if (referenceOwner && `${ownerId || ""}`.trim() &&
      referenceOwner !== `${ownerId || ""}`.trim()) {
    throw new Error("Stripe payment owner does not match the session.");
  }
  const amountGBP = roundMoney(amountPence / 100);
  if (expectedAmountGBP != null && amountGBP !== roundMoney(expectedAmountGBP)) {
    throw new Error("Stripe payment amount does not match the expected charge.");
  }
  return {
    amountGBP,
    currency: "GBP",
    paymentIntentId: session.payment_intent || null,
    checkoutSessionId: session.id || null,
  };
}

function verifiedStripeRothPurchase(sessionData, {ownerId = "", ownerEmail = ""} = {}) {
  const payment = verifiedStripePaidGbpSession(sessionData, {ownerId, ownerEmail});
  return {
    ...payment,
    rothIssued: payment.amountGBP,
  };
}

function assertBalanceType(balanceType) {
  if (!Object.values(BALANCE_TYPES).includes(balanceType)) {
    throw new Error(`Unsupported Roth balance type: ${balanceType}`);
  }
}

function assertTransactionType(type) {
  if (!Object.values(TRANSACTION_TYPES).includes(type)) {
    throw new Error(`Unsupported Roth transaction type: ${type}`);
  }
}

function canWithdraw(balanceType) {
  return balanceType === BALANCE_TYPES.availableEarnings;
}

function isRothCreditWithdrawable() {
  return false;
}

function nextBalance({balanceBefore, amount, allowNegative = false, type}) {
  const after = roundMoney(balanceBefore + amount);
  if (after < 0 && !allowNegative && type !== TRANSACTION_TYPES.reversal) {
    throw new Error("Roth ledger balances cannot go negative without an auditable reversal.");
  }
  return after;
}

function senderWalletRecord({walletId, userId, email, balance = 0, createdAt = null, updatedAt = null}) {
  return {
    walletId,
    userId,
    email: `${email || ""}`.trim().toLowerCase(),
    walletType: "sender",
    balance: roundMoney(balance),
    currencyEquivalent: "GBP",
    createdAt,
    updatedAt: updatedAt || createdAt,
  };
}

function senderWalletProjectionRecord({
  userId,
  balance = 0,
  frozen = false,
  version = 1,
  createdAt = null,
  updatedAt = null,
}) {
  const normalizedBalance = roundMoney(balance);
  if (normalizedBalance < 0) {
    throw new Error("Sender Roth balance cannot be negative.");
  }
  return {
    userId,
    balance: normalizedBalance,
    currency: "ROTH",
    status: frozen ? "frozen" : "active",
    createdAt,
    updatedAt: updatedAt || createdAt,
    version: Math.max(1, Number(version || 1)),
  };
}

function walletTransactionView(record) {
  const rawAmount = roundMoney(record.amount);
  const rawDirection = `${record.direction || (rawAmount < 0 ? "debit" : "credit")}`.toLowerCase();
  const metadata = record.metadata && typeof record.metadata === "object" ? record.metadata : {};
  const source = `${record.source || metadata.source || ""}`.trim().slice(0, 64);
  const paymentMethodLabel = `${record.paymentMethodLabel || metadata.paymentMethodLabel || metadata.paidWith || ""}`.trim().slice(0, 64);
  return {
    transactionId: `${record.transactionId || record.id || ""}`,
    walletType: "sender",
    direction: rawDirection === "debit" ? "debit" : "credit",
    type: `${record.type || "adjustment"}`,
    amount: Math.abs(rawAmount),
    balanceBefore: roundMoney(record.balanceBefore),
    balanceAfter: roundMoney(record.balanceAfter),
    description: `${record.description || record.reason || record.notes || record.type || "Roth activity"}`,
    relatedEntityId: record.relatedEntityId || record.referenceId || null,
    referenceType: record.referenceType || metadata.referenceType || null,
    source,
    paymentMethodLabel,
    createdBy: record.createdBy === "system" ? "system" : "circum",
    createdAt: record.createdAt || null,
    status: `${record.status || "unknown"}`,
  };
}

function encodeWalletCursor({source, createdAtMillis, transactionId}) {
  return Buffer.from(JSON.stringify({
    source: `${source || ""}`,
    createdAtMillis: Number(createdAtMillis || 0),
    transactionId: `${transactionId || ""}`,
  })).toString("base64url");
}

function decodeWalletCursor(token) {
  if (!token) return null;
  try {
    const value = JSON.parse(Buffer.from(`${token}`, "base64url").toString("utf8"));
    if (!value || !value.transactionId || !Number.isFinite(Number(value.createdAtMillis))) return null;
    return {
      source: `${value.source || ""}`,
      createdAtMillis: Number(value.createdAtMillis),
      transactionId: `${value.transactionId}`,
    };
  } catch (_) {
    return null;
  }
}

function paginateWalletTransactions(records, {pageSize = 20, pageOffset = 0, pageToken = null} = {}) {
  const safeSize = Math.min(50, Math.max(1, Number(pageSize || 20)));
  const safeOffset = Math.max(0, Number(pageOffset || 0));
  const sorted = [...records].sort((a, b) => {
    const aTime = Number(a.createdAtMillis || 0);
    const bTime = Number(b.createdAtMillis || 0);
    if (aTime !== bTime) return bTime - aTime;
    return `${b.transactionId || b.id || ""}`.localeCompare(`${a.transactionId || a.id || ""}`);
  });
  const cursor = decodeWalletCursor(pageToken);
  const cursorIndex = cursor ? sorted.findIndex((record) =>
    Number(record.createdAtMillis || 0) === cursor.createdAtMillis &&
    `${record.transactionId || record.id || ""}` === cursor.transactionId) : -1;
  const start = cursorIndex >= 0 ? cursorIndex + 1 : safeOffset;
  const page = sorted.slice(start, start + safeSize);
  const nextOffset = start + page.length;
  return {
    records: page,
    nextPageToken: nextOffset < sorted.length ? encodeWalletCursor({
      source: cursor && cursor.source,
      createdAtMillis: page[page.length - 1].createdAtMillis,
      transactionId: page[page.length - 1].transactionId || page[page.length - 1].id,
    }) : null,
  };
}

function ledgerTransactionRecord({
  transactionId,
  walletId,
  userId,
  email,
  type,
  direction,
  amount,
  balanceBefore,
  source,
  referenceType,
  referenceId,
  reason,
  createdBy,
  createdAt = null,
}) {
  assertTransactionType(type);
  const roundedAmount = roundMoney(amount);
  const signedAmount = direction === "debit" ? -Math.abs(roundedAmount) : Math.abs(roundedAmount);
  const balanceAfter = nextBalance({
    balanceBefore: roundMoney(balanceBefore),
    amount: signedAmount,
    type,
  });
  return {
    transactionId,
    walletId,
    userId,
    email: `${email || ""}`.trim().toLowerCase(),
    type,
    direction,
    amount: roundedAmount,
    balanceBefore: roundMoney(balanceBefore),
    balanceAfter,
    source,
    referenceType,
    referenceId,
    reason,
    createdBy,
    createdAt,
  };
}

module.exports = {
  BALANCE_TYPES,
  LEDGER_EVENTS,
  TRANSACTION_TYPES,
  roundMoney,
  verifiedStripePaidGbpSession,
  verifiedStripeRothPurchase,
  assertBalanceType,
  assertTransactionType,
  canWithdraw,
  isRothCreditWithdrawable,
  ledgerTransactionRecord,
  nextBalance,
  paginateWalletTransactions,
  senderWalletRecord,
  senderWalletProjectionRecord,
  walletTransactionView,
  encodeWalletCursor,
  decodeWalletCursor,
};
