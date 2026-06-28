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
const senderTrust = require("./sender-trust");

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

async function requireTrustedRothAdmin(context) {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Roth admin authentication is required.");
  }
  if (hasAdminRole(context)) {
    return {
      uid: context.auth.uid,
      email: context.auth.token.email || null,
    };
  }
  const adminSnap = await getFirestore()
      .collection("adminUsers")
      .doc(context.auth.uid)
      .get();
  const admin = adminSnap.exists ? adminSnap.data() : {};
  const role = `${admin.role || ""}`.toLowerCase();
  if (admin.status === "active" && ["super_admin", "finance_admin", "operations_admin"].includes(role)) {
    return {
      uid: context.auth.uid,
      email: context.auth.token.email || admin.email || null,
    };
  }
  throw new functions.https.HttpsError("permission-denied", "Roth wallet access requires admin finance permissions.");
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

async function resolveRecipientUser({recipientUid = "", recipientEmail = ""}) {
  const email = normalizeEmail(recipientEmail || "");
  const uid = `${recipientUid || ""}`.trim();
  try {
    const user = email ? await getAuth().getUserByEmail(email) : await getAuth().getUser(uid);
    return {
      uid: user.uid,
      email: normalizeEmail(user.email || email),
    };
  } catch (error) {
    throw new functions.https.HttpsError("not-found", "Recipient user could not be found.");
  }
}

function walletTargetsFor(value) {
  const target = `${value || ""}`.trim().toLowerCase();
  if (target === "sender") return ["sender"];
  if (target === "rider") return ["rider"];
  if (target === "both") return ["sender", "rider"];
  throw new functions.https.HttpsError("invalid-argument", "Wallet target must be sender, rider, or both.");
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
  const transactionId = `wallet_top_up_${sessionData.id}`;
  const movement = await recordRothMovement({
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
    transactionId,
    metadata: {
      stripeEventId: eventId,
      stripeCheckoutSessionId: sessionData.id,
      stripePaymentIntentId: sessionData.payment_intent || null,
      label: "Roth top-up",
    },
  });
  const progression = await senderTrust.awardRothTopUpProgression({
    uid: metadata.uid || null,
    userEmail: metadata.userEmail || null,
    amount,
    stripeSessionId: sessionData.id,
    walletTransactionId: transactionId,
  });
  return {...movement, progression};
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

exports.issueRothToWallets = functions.https.onCall(async (data, context) => {
  const admin = await requireTrustedRothAdmin(context);
  const amount = roundWalletMoney(data.amount);
  const reason = `${data.reason || ""}`.trim();
  const idempotencyKey = `${data.idempotencyKey || ""}`.trim();
  const targets = walletTargetsFor(data.walletTarget);
  if (!Number.isFinite(amount) || amount <= 0) {
    throw new functions.https.HttpsError("invalid-argument", "Roth amount must be greater than zero.");
  }
  if (!reason) {
    throw new functions.https.HttpsError("invalid-argument", "Reason is required.");
  }
  if (!idempotencyKey) {
    throw new functions.https.HttpsError("invalid-argument", "Idempotency key is required.");
  }
  const recipient = await resolveRecipientUser({
    recipientUid: data.recipientUid || data.userId,
    recipientEmail: data.recipientEmail || data.email,
  });
  const db = getFirestore();
  const adminIssueId = `${data.adminIssueId || idempotencyKey}`.trim();
  const issueRef = db.collection("rothAdminIssues").doc(idempotencyKey);
  const ledgerRefs = targets.map((walletType) => ({
    walletType,
    ref: db.collection("rothLedger").doc(`${adminIssueId}_${walletType}`),
    walletRef: db.collection("users").doc(recipient.uid).collection("wallets").doc(walletType),
  }));
  const legacyIdentity = await resolveWalletIdentity({
    userId: recipient.uid,
    email: recipient.email,
    authUid: recipient.uid,
  });
  let result = null;
  await db.runTransaction(async (transaction) => {
    const existingIssue = await transaction.get(issueRef);
    if (existingIssue.exists) {
      const existing = existingIssue.data();
      result = {
        adminIssueId: existing.adminIssueId,
        idempotencyKey: existing.idempotencyKey,
        recipientUid: existing.recipientUid,
        recipientEmail: existing.recipientEmail,
        walletTarget: existing.walletTarget,
        amount: existing.amount,
        credited: existing.credited || [],
        idempotentReplay: true,
      };
      return;
    }
    const now = FieldValue.serverTimestamp();
    const roleWalletSnaps = [];
    const roleLedgerSnaps = [];
    for (const item of ledgerRefs) {
      roleWalletSnaps.push(await transaction.get(item.walletRef));
      roleLedgerSnaps.push(await transaction.get(item.ref));
    }
    const legacyWalletRef = targets.includes("sender") ?
      db.collection("wallets").doc(legacyIdentity.walletId) : null;
    const legacyTxRef = targets.includes("sender") ?
      db.collection("walletTransactions").doc(`${adminIssueId}_sender_legacy`) : null;
    const legacyWalletSnap = legacyWalletRef ? await transaction.get(legacyWalletRef) : null;
    const legacyTxSnap = legacyTxRef ? await transaction.get(legacyTxRef) : null;
    const credited = [];
    for (let index = 0; index < ledgerRefs.length; index++) {
      const item = ledgerRefs[index];
      const walletSnap = roleWalletSnaps[index];
      const ledgerSnap = roleLedgerSnaps[index];
      if (ledgerSnap.exists) {
        throw new functions.https.HttpsError("already-exists", "Roth issue ledger entry already exists.");
      }
      const wallet = walletSnap.exists ? walletSnap.data() : {};
      const before = roundWalletMoney(wallet.balance || 0);
      const after = roundWalletMoney(before + amount);
      transaction.set(item.walletRef, {
        balance: after,
        balanceRoth: after,
        lifetimeIssuedRoth: roundWalletMoney((wallet.lifetimeIssuedRoth || 0) + amount),
        lifetimeSpentRoth: roundWalletMoney(wallet.lifetimeSpentRoth || 0),
        updatedAt: now,
        createdAt: wallet.createdAt || now,
        currency: "ROTH",
        walletType: item.walletType,
      }, {merge: true});
      transaction.set(item.ref, {
        uid: recipient.uid,
        walletType: item.walletType,
        amount,
        direction: "credit",
        reason,
        source: "admin_issue",
        adminId: admin.uid,
        adminEmail: admin.email,
        adminIssueId,
        idempotencyKey,
        createdAt: now,
        metadata: {
          recipientEmail: recipient.email,
          walletTarget: data.walletTarget,
        },
      });
      credited.push({
        walletType: item.walletType,
        ledgerEntryId: item.ref.id,
        balanceAfter: after,
      });
    }
    if (legacyWalletRef && legacyTxRef && legacyWalletSnap && legacyTxSnap) {
      if (!legacyTxSnap.exists) {
        const legacyWallet = legacyWalletSnap.exists ? legacyWalletSnap.data() : {};
        const before = roundWalletMoney(legacyWallet.balance == null ? legacyWallet.rothCredit : legacyWallet.balance);
        const after = roundWalletMoney(before + amount);
        transaction.set(legacyWalletRef, {
          userId: legacyIdentity.walletId,
          uid: recipient.uid,
          userEmail: recipient.email,
          normalizedEmail: recipient.email,
          balance: after,
          rothCredit: after,
          currency: "GBP",
          isFrozen: legacyWallet.isFrozen === true,
          pendingEarnings: roundWalletMoney(legacyWallet.pendingEarnings || 0),
          availableEarnings: roundWalletMoney(legacyWallet.availableEarnings || 0),
          createdAt: legacyWallet.createdAt || now,
          updatedAt: now,
        }, {merge: true});
        transaction.set(legacyTxRef, {
          id: legacyTxRef.id,
          userId: legacyIdentity.walletId,
          uid: recipient.uid,
          userEmail: recipient.email,
          normalizedEmail: recipient.email,
          walletId: legacyIdentity.walletId,
          amount,
          direction: "credit",
          source: "admin_issue",
          balanceType: BALANCE_TYPES.rothCredit,
          type: TRANSACTION_TYPES.adminCredit,
          reason,
          paymentProvider: "manual_admin",
          issuedByAdminId: admin.uid,
          issuedByAdminEmail: admin.email,
          balanceBefore: before,
          balanceAfter: after,
          createdAt: now,
          metadata: {adminIssueId, idempotencyKey, walletType: "sender"},
        });
      }
    }
    const issueRecord = {
      adminIssueId,
      idempotencyKey,
      recipientUid: recipient.uid,
      recipientEmail: recipient.email,
      walletTarget: data.walletTarget,
      amount,
      credited,
      createdAt: now,
    };
    result = {
      adminIssueId,
      idempotencyKey,
      recipientUid: recipient.uid,
      recipientEmail: recipient.email,
      walletTarget: data.walletTarget,
      amount,
      credited,
    };
    transaction.set(issueRef, issueRecord);
    transaction.set(db.collection("adminAuditLogs").doc(), {
      action: "roth_issue",
      actionType: "roth_issue",
      adminId: admin.uid,
      adminUserId: admin.uid,
      adminEmail: admin.email,
      recipientUid: recipient.uid,
      walletTarget: data.walletTarget,
      amount,
      reason,
      adminIssueId,
      idempotencyKey,
      createdAt: now,
    });
  });
  return result;
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
