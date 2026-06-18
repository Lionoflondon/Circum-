/* eslint-disable max-len, require-jsdoc */
"use strict";

const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {getAuth} = require("firebase-admin/auth");
const {
  BALANCE_TYPES,
  TRANSACTION_TYPES,
  assertBalanceType,
  assertTransactionType,
  nextBalance,
  roundMoney,
} = require("./roth-ledger-core");
const {
  canRedeemGiftCard,
  normalizeEmail,
  roundMoney: roundWalletMoney,
  walletIdForEmail,
} = require("./wallet-core");

function hasAdminRole(context) {
  const token = context.auth && context.auth.token || {};
  const role = `${token.role || token.adminRole || ""}`.toLowerCase();
  const roles = Array.isArray(token.roles) ? token.roles.map((item) => `${item}`.toLowerCase()) : [];
  return token.admin === true || token.super_admin === true ||
    [role, ...roles].some((item) => ["super_admin", "finance_admin", "operations_admin"].includes(item));
}

function requireRothAdmin(context) {
  if (!context.auth || !hasAdminRole(context)) {
    throw new functions.https.HttpsError("permission-denied", "Roth wallet access requires admin finance permissions.");
  }
}

async function writeRothAudit({adminId, adminEmail, action, userId, amount = null, reason = null, metadata = {}}) {
  await getFirestore().collection("adminAuditLogs").add({
    adminUserId: adminId,
    adminEmail,
    actionType: action,
    recordType: "wallets",
    recordId: userId,
    newValue: {userId, amount, reason, ...metadata},
    createdAt: FieldValue.serverTimestamp(),
  });
}

async function resolveWalletIdentity({userId = "", email = "", authUid = ""}) {
  const raw = `${email || userId || ""}`.trim();
  let normalizedEmail = normalizeEmail(email || (raw.includes("@") ? raw : ""));
  let uid = authUid || (!raw.includes("@") ? raw : "");
  try {
    if (normalizedEmail) {
      const user = await getAuth().getUserByEmail(normalizedEmail);
      uid = uid || user.uid;
      normalizedEmail = normalizeEmail(user.email || normalizedEmail);
    } else if (uid) {
      const user = await getAuth().getUser(uid);
      normalizedEmail = normalizeEmail(user.email || "");
    }
  } catch (error) {
    if (!normalizedEmail && !uid) throw error;
  }
  const walletId = walletIdForEmail(normalizedEmail) || uid;
  if (!walletId) throw new Error("Wallet identity requires email or uid.");
  return {walletId, uid: uid || null, userEmail: normalizedEmail || null};
}

async function recordRothMovement({
  db = getFirestore(),
  userId,
  userEmail = null,
  uid = null,
  amount,
  balanceType,
  type,
  reason,
  relatedEntityId = null,
  paymentProvider = "roth_internal",
  providerTransactionId = null,
  issuedByAdminId = null,
  issuedByAdminEmail = null,
  metadata = {},
  allowNegative = false,
  ledgerOnly = false,
  transactionId = null,
}) {
  if (!userId) throw new Error("Roth ledger movement requires userId.");
  assertBalanceType(balanceType);
  assertTransactionType(type);
  const roundedAmount = roundMoney(amount);
  if (roundedAmount === 0) throw new Error("Roth ledger movement amount cannot be zero.");
  const identity = await resolveWalletIdentity({userId, email: userEmail, authUid: uid});
  const walletRef = db.collection("wallets").doc(identity.walletId);
  const ledgerRef = transactionId ?
    db.collection("walletTransactions").doc(transactionId) :
    db.collection("walletTransactions").doc();
  await db.runTransaction(async (transaction) => {
    const existingLedger = await transaction.get(ledgerRef);
    if (existingLedger.exists) return;
    const wallet = await transaction.get(walletRef);
    const walletData = wallet.exists ? wallet.data() : {};
    const rawBalance = balanceType === BALANCE_TYPES.rothCredit ?
      (walletData.balance == null ? walletData.rothCredit : walletData.balance) :
      walletData[balanceType];
    const balanceBefore = roundMoney(rawBalance || 0);
    const balanceAfter = ledgerOnly ? balanceBefore : nextBalance({
      balanceBefore,
      amount: roundedAmount,
      allowNegative,
      type,
    });
    const now = FieldValue.serverTimestamp();
    transaction.set(walletRef, {
      userId: identity.walletId,
      uid: identity.uid,
      userEmail: identity.userEmail,
      normalizedEmail: identity.userEmail,
      balance: balanceType === BALANCE_TYPES.rothCredit && !ledgerOnly ?
        balanceAfter :
        roundMoney(walletData.balance == null ? walletData.rothCredit : walletData.balance),
      currency: walletData.currency || "GBP",
      isFrozen: walletData.isFrozen === true,
      rothCredit: balanceType === BALANCE_TYPES.rothCredit && !ledgerOnly ?
        balanceAfter :
        roundMoney(walletData.rothCredit == null ? walletData.balance : walletData.rothCredit),
      pendingEarnings: roundMoney(walletData.pendingEarnings || 0),
      availableEarnings: roundMoney(walletData.availableEarnings || 0),
      ...(ledgerOnly ? {} : {[balanceType]: balanceAfter}),
      createdAt: walletData.createdAt || now,
      updatedAt: now,
    }, {merge: true});
    transaction.set(ledgerRef, {
      id: ledgerRef.id,
      userId: identity.walletId,
      uid: identity.uid,
      userEmail: identity.userEmail,
      normalizedEmail: identity.userEmail,
      walletId: identity.walletId,
      amount: roundedAmount,
      balanceType,
      type,
      reason: reason || type,
      relatedEntityId,
      paymentProvider,
      providerTransactionId,
      issuedByAdminId,
      issuedByAdminEmail,
      balanceBefore,
      balanceAfter,
      ledgerOnly,
      createdAt: now,
      metadata,
    });
  });
  return {transactionId: ledgerRef.id};
}

async function safeRecordRothMovement(args) {
  try {
    return await recordRothMovement(args);
  } catch (error) {
    console.error("Roth ledger write failed", {
      error: error.message,
      userId: args && args.userId,
      relatedEntityId: args && args.relatedEntityId,
      providerTransactionId: args && args.providerTransactionId,
    });
    try {
      await (args.db || getFirestore()).collection("rothLedgerRepairLogs").add({
        error: error.message,
        userId: args && args.userId || null,
        amount: args && args.amount || null,
        balanceType: args && args.balanceType || null,
        type: args && args.type || null,
        relatedEntityId: args && args.relatedEntityId || null,
        providerTransactionId: args && args.providerTransactionId || null,
        metadata: args && args.metadata || {},
        createdAt: FieldValue.serverTimestamp(),
      });
    } catch (repairError) {
      console.error("Roth repair log write failed", repairError);
    }
    return null;
  }
}

exports.recordRothMovement = recordRothMovement;
exports.safeRecordRothMovement = safeRecordRothMovement;

async function applyWalletDebit({
  db = getFirestore(),
  userId,
  userEmail = null,
  uid = null,
  amount,
  type,
  referenceId,
  notes,
  metadata = {},
  transactionId = null,
}) {
  if (!userId) throw new Error("Wallet debit requires userId.");
  const debit = roundWalletMoney(amount);
  if (debit <= 0) return {walletContributionGbp: 0};
  const identity = await resolveWalletIdentity({userId, email: userEmail, authUid: uid});
  const walletRef = db.collection("wallets").doc(identity.walletId);
  const txRef = transactionId ?
    db.collection("walletTransactions").doc(transactionId) :
    db.collection("walletTransactions").doc();
  await db.runTransaction(async (transaction) => {
    const [walletSnap, existingTx] = await Promise.all([
      transaction.get(walletRef),
      transaction.get(txRef),
    ]);
    if (existingTx.exists) return;
    const wallet = walletSnap.exists ? walletSnap.data() : {};
    if (wallet.isFrozen === true) throw new Error("Wallet is frozen.");
    const before = roundWalletMoney(wallet.balance == null ? wallet.rothCredit : wallet.balance);
    if (before < debit) throw new Error("Wallet balance is too low.");
    const after = roundWalletMoney(before - debit);
    const now = FieldValue.serverTimestamp();
    transaction.set(walletRef, {
      userId: identity.walletId,
      uid: identity.uid,
      userEmail: identity.userEmail,
      normalizedEmail: identity.userEmail,
      balance: after,
      rothCredit: after,
      currency: "GBP",
      isFrozen: wallet.isFrozen === true,
      pendingEarnings: roundWalletMoney(wallet.pendingEarnings || 0),
      availableEarnings: roundWalletMoney(wallet.availableEarnings || 0),
      createdAt: wallet.createdAt || now,
      updatedAt: now,
    }, {merge: true});
    transaction.set(txRef, {
      id: txRef.id,
      userId: identity.walletId,
      uid: identity.uid,
      userEmail: identity.userEmail,
      normalizedEmail: identity.userEmail,
      walletId: identity.walletId,
      type,
      amount: -debit,
      balanceType: BALANCE_TYPES.rothCredit,
      balanceBefore: before,
      balanceAfter: after,
      referenceId,
      relatedEntityId: referenceId,
      notes,
      paymentProvider: "roth_internal",
      createdAt: now,
      metadata,
    });
  });
  return {walletContributionGbp: debit, transactionId: txRef.id};
}

exports.applyWalletDebit = applyWalletDebit;

exports.createWalletTopUp = (stripe) => functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Sign in to top up Roth.");
  }
  const amount = roundWalletMoney(data.amount);
  if (amount < 1) {
    throw new functions.https.HttpsError("invalid-argument", "Top-up amount must be at least £1.");
  }
  const identity = await resolveWalletIdentity({
    userId: context.auth.uid,
    email: context.auth.token.email,
    authUid: context.auth.uid,
  });
  const baseUrl = `${data.returnUrl || "https://circumuk.com/?app=sender&section=wallet"}`;
  const separator = baseUrl.includes("?") ? "&" : "?";
  const session = await stripe.checkout.sessions.create({
    mode: "payment",
    payment_method_types: ["card"],
    line_items: [{
      quantity: 1,
      price_data: {
        currency: "gbp",
        unit_amount: Math.round(amount * 100),
        product_data: {
          name: "Roth Wallet Top-Up",
          description: "Adds Roth balance to your Circum Wallet after payment succeeds.",
        },
      },
    }],
    success_url: `${baseUrl}${separator}wallet_topup=success&session_id={CHECKOUT_SESSION_ID}`,
    cancel_url: `${baseUrl}${separator}wallet_topup=cancelled`,
    metadata: {
      type: "wallet_top_up",
      userId: identity.walletId,
      uid: identity.uid || "",
      userEmail: identity.userEmail || "",
      amountGbp: `${amount}`,
    },
  });
  return {checkoutUrl: session.url, sessionId: session.id};
});

async function recordWalletTopUpFromStripeSession(sessionData, eventId = null) {
  const metadata = sessionData.metadata || {};
  if (metadata.type !== "wallet_top_up") return null;
  const amount = roundWalletMoney(metadata.amountGbp || Number(sessionData.amount_total || 0) / 100);
  if (amount <= 0) return null;
  return recordRothMovement({
    userId: metadata.userId || metadata.userEmail || metadata.uid,
    uid: metadata.uid || null,
    userEmail: metadata.userEmail || null,
    amount,
    balanceType: BALANCE_TYPES.rothCredit,
    type: TRANSACTION_TYPES.userTopUp,
    reason: "Roth top-up",
    relatedEntityId: sessionData.id,
    paymentProvider: "stripe",
    providerTransactionId: sessionData.payment_intent || sessionData.id,
    transactionId: `wallet_top_up_${sessionData.id}`,
    metadata: {
      stripeEventId: eventId,
      stripeCheckoutSessionId: sessionData.id,
      stripePaymentIntentId: sessionData.payment_intent || null,
      label: "Roth top-up",
    },
  });
}

exports.recordWalletTopUpFromStripeSession = recordWalletTopUpFromStripeSession;

exports.applyCheckoutRoth = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Sign in to use Roth.");
  }
  const amount = roundWalletMoney(data.amount);
  const referenceId = `${data.referenceId || ""}`.trim();
  const service = `${data.service || "delivery"}`.trim().toLowerCase();
  if (amount <= 0 || !referenceId) {
    throw new functions.https.HttpsError("invalid-argument", "Amount and reference are required.");
  }
  const type = service === "gifts" ? "gift_payment" :
    service === "health_plus" ? "health_payment" :
      "delivery_payment";
  return applyWalletDebit({
    userId: context.auth.uid,
    userEmail: context.auth.token.email,
    amount,
    type,
    referenceId,
    notes: `Roth applied to ${service.replace("_", " ")} checkout.`,
    transactionId: `wallet_${service}_${referenceId}`,
    metadata: {service, source: "checkout_roth"},
  });
});

exports.issueRothCredit = functions.https.onCall(async (data, context) => {
  requireRothAdmin(context);
  const rawUser = `${data.userId || data.email || ""}`.trim();
  const amount = Number(data.amount || 0);
  const reason = `${data.reason || ""}`.trim();
  if (!rawUser || amount <= 0 || !reason) {
    throw new functions.https.HttpsError("invalid-argument", "User, amount and reason are required.");
  }
  const identity = await resolveWalletIdentity({userId: rawUser, email: data.email});
  const result = await recordRothMovement({
    userId: identity.walletId,
    uid: identity.uid,
    userEmail: identity.userEmail,
    amount,
    balanceType: BALANCE_TYPES.rothCredit,
    type: TRANSACTION_TYPES.adminCredit,
    reason,
    paymentProvider: "manual_admin",
    issuedByAdminId: context.auth.uid,
    issuedByAdminEmail: context.auth.token.email || null,
    metadata: {source: "admin_issue_roth", input: rawUser},
  });
  await writeRothAudit({
    adminId: context.auth.uid,
    adminEmail: context.auth.token.email || null,
    action: "roth_credit_issued",
    userId: identity.walletId,
    amount,
    reason,
    metadata: {uid: identity.uid, userEmail: identity.userEmail},
  });
  return result;
});

exports.debitRothCredit = functions.https.onCall(async (data, context) => {
  requireRothAdmin(context);
  const rawUser = `${data.userId || data.email || ""}`.trim();
  const amount = Number(data.amount || 0);
  const reason = `${data.reason || ""}`.trim();
  if (!rawUser || amount <= 0 || !reason) {
    throw new functions.https.HttpsError("invalid-argument", "User, amount and reason are required.");
  }
  const identity = await resolveWalletIdentity({userId: rawUser, email: data.email});
  const result = await recordRothMovement({
    userId: identity.walletId,
    uid: identity.uid,
    userEmail: identity.userEmail,
    amount: -Math.abs(amount),
    balanceType: BALANCE_TYPES.rothCredit,
    type: TRANSACTION_TYPES.adminDebit,
    reason,
    paymentProvider: "manual_admin",
    issuedByAdminId: context.auth.uid,
    issuedByAdminEmail: context.auth.token.email || null,
    metadata: {source: "admin_debit_roth", input: rawUser},
  });
  await writeRothAudit({
    adminId: context.auth.uid,
    adminEmail: context.auth.token.email || null,
    action: "roth_credit_debited",
    userId: identity.walletId,
    amount: -Math.abs(amount),
    reason,
    metadata: {uid: identity.uid, userEmail: identity.userEmail},
  });
  return result;
});

exports.setWalletFrozen = functions.https.onCall(async (data, context) => {
  requireRothAdmin(context);
  const userId = `${data.userId || data.email || ""}`.trim();
  const frozen = data.isFrozen === true;
  const reason = `${data.reason || ""}`.trim();
  if (!userId || !reason) {
    throw new functions.https.HttpsError("invalid-argument", "User and reason are required.");
  }
  const identity = await resolveWalletIdentity({userId, email: data.email});
  await getFirestore().collection("wallets").doc(identity.walletId).set({
    userId: identity.walletId,
    uid: identity.uid,
    userEmail: identity.userEmail,
    normalizedEmail: identity.userEmail,
    isFrozen: frozen,
    currency: "GBP",
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  await writeRothAudit({
    adminId: context.auth.uid,
    adminEmail: context.auth.token.email || null,
    action: frozen ? "wallet_frozen" : "wallet_unfrozen",
    userId: identity.walletId,
    reason,
  });
  return {userId: identity.walletId, isFrozen: frozen};
});

exports.redeemGiftCard = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Sign in to redeem a gift card.");
  }
  const code = `${data.code || ""}`.trim().toUpperCase();
  if (!code) {
    throw new functions.https.HttpsError("invalid-argument", "Gift card code is required.");
  }
  const db = getFirestore();
  const identity = await resolveWalletIdentity({
    userId: context.auth.uid,
    email: context.auth.token.email,
    authUid: context.auth.uid,
  });
  const cardRef = db.collection("giftCards").doc(code);
  const walletRef = db.collection("wallets").doc(identity.walletId);
  const txRef = db.collection("walletTransactions").doc(`gift_card_${code}`);
  await db.runTransaction(async (transaction) => {
    const [cardSnap, walletSnap, existingTx] = await Promise.all([
      transaction.get(cardRef),
      transaction.get(walletRef),
      transaction.get(txRef),
    ]);
    if (existingTx.exists) {
      throw new functions.https.HttpsError("already-exists", "This gift card has already been redeemed.");
    }
    const card = cardSnap.exists ? cardSnap.data() : null;
    if (!canRedeemGiftCard(card)) {
      throw new functions.https.HttpsError("failed-precondition", "This gift card cannot be redeemed.");
    }
    const value = roundWalletMoney(card.value || 0);
    if (value <= 0) {
      throw new functions.https.HttpsError("failed-precondition", "This gift card has no redeemable value.");
    }
    const wallet = walletSnap.exists ? walletSnap.data() : {};
    if (wallet.isFrozen === true) {
      throw new functions.https.HttpsError("failed-precondition", "This wallet is frozen.");
    }
    const before = roundWalletMoney(wallet.balance == null ? wallet.rothCredit : wallet.balance);
    const after = roundWalletMoney(before + value);
    const now = FieldValue.serverTimestamp();
    transaction.set(walletRef, {
      userId: context.auth.uid,
      uid: identity.uid,
      userEmail: identity.userEmail,
      normalizedEmail: identity.userEmail,
      balance: after,
      rothCredit: after,
      currency: "GBP",
      isFrozen: false,
      pendingEarnings: roundWalletMoney(wallet.pendingEarnings || 0),
      availableEarnings: roundWalletMoney(wallet.availableEarnings || 0),
      createdAt: wallet.createdAt || now,
      updatedAt: now,
    }, {merge: true});
    transaction.set(txRef, {
      id: txRef.id,
      userId: identity.walletId,
      uid: identity.uid,
      userEmail: identity.userEmail,
      normalizedEmail: identity.userEmail,
      walletId: identity.walletId,
      type: "gift_card_redemption",
      amount: value,
      balanceType: BALANCE_TYPES.rothCredit,
      balanceBefore: before,
      balanceAfter: after,
      referenceId: code,
      relatedEntityId: code,
      notes: "Roth gift card redeemed.",
      paymentProvider: "gift_card",
      createdAt: now,
      metadata: {giftCardCode: code},
    });
    transaction.set(cardRef, {
      status: "redeemed",
      redeemedBy: identity.uid || context.auth.uid,
      redeemedByEmail: identity.userEmail,
      redeemedAt: now,
      updatedAt: now,
    }, {merge: true});
  });
  return {status: "redeemed"};
});

exports.BALANCE_TYPES = BALANCE_TYPES;
exports.TRANSACTION_TYPES = TRANSACTION_TYPES;
