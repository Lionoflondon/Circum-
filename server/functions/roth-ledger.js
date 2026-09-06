/* eslint-disable max-len, require-jsdoc */
"use strict";

const functions = require("firebase-functions/v1");
const crypto = require("node:crypto");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {getAuth} = require("firebase-admin/auth");
const {senderPaymentCallable} = require("./sender-app-check");
const {
  BALANCE_TYPES,
  TRANSACTION_TYPES,
  assertBalanceType,
  assertTransactionType,
  nextBalance,
  roundMoney,
  verifiedStripeRothPurchase,
  senderWalletProjectionRecord,
  walletTransactionView,
  paginateWalletTransactions,
} = require("./roth-ledger-core");
const {
  canRedeemGiftCard,
  normalizeEmail,
  roundMoney: roundWalletMoney,
  walletIdForEmail,
} = require("./wallet-core");
const communicationEngine = require("./communication-engine");
const senderTrust = require("./sender-trust");

const SENDER_WELCOME_ROTH_AMOUNT = 5;
const SENDER_WELCOME_ROTH_REASON = "Welcome Roth credit";

function hasAdminRole(context) {
  const token = context.auth && context.auth.token || {};
  const role = `${token.role || token.adminRole || ""}`.toLowerCase();
  const roles = Array.isArray(token.roles) ? token.roles.map((item) => `${item}`.toLowerCase()) : [];
  return token.admin === true || token.super_admin === true ||
    [role, ...roles].some((item) => ["super_admin", "finance_admin", "operations_admin"].includes(item));
}

async function requireRothAdmin(context) {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Roth admin authentication is required.");
  }
  if (hasAdminRole(context)) return;
  const adminSnap = await getFirestore().collection("adminUsers").doc(context.auth.uid).get();
  const admin = adminSnap.exists ? adminSnap.data() : {};
  const role = `${admin.role || ""}`.toLowerCase();
  if (admin.status === "active" && ["super_admin", "finance_admin", "operations_admin"].includes(role)) return;
  throw new functions.https.HttpsError("permission-denied", "Roth wallet access requires admin finance permissions.");
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

async function requireSenderIdentity(context) {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Sign in to access your Wallet.");
  }
  return resolveWalletIdentity({
    userId: context.auth.uid,
    email: context.auth.token.email,
    authUid: context.auth.uid,
  });
}

function hasPendingSenderWelcomeRoth(record = {}) {
  return `${record.starterRothGrantStatus || ""}`.trim().toLowerCase() === "pending";
}

async function repairPendingSenderWelcomeRoth(context, source) {
  const db = getFirestore();
  const userRef = db.collection("users").doc(context.auth.uid);
  const userSnap = await userRef.get();
  const user = userSnap.exists ? userSnap.data() || {} : {};
  if (!hasPendingSenderWelcomeRoth(user)) return null;
  const grant = await grantSenderWelcomeRoth({
    uid: context.auth.uid,
    email: context.auth.token.email,
    source,
  });
  await userRef.set({
    starterRothGrantStatus: "granted",
    starterRothGrantedAt: FieldValue.serverTimestamp(),
    starterRothAmount: SENDER_WELCOME_ROTH_AMOUNT,
    starterRothTransactionId: grant.transactionId,
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  return grant;
}

async function initialiseSenderWalletRecord(context) {
  const identity = await requireSenderIdentity(context);
  const starterRoth = await repairPendingSenderWelcomeRoth(context, "initialiseSenderWallet");
  const db = getFirestore();
  const projectionRef = db.collection("senderWallets").doc(context.auth.uid);
  const legacyRef = db.collection("wallets").doc(identity.walletId);
  const roleRef = db.collection("users").doc(context.auth.uid).collection("wallets").doc("sender");
  let result;
  await db.runTransaction(async (transaction) => {
    const [projectionSnap, legacySnap, roleSnap] = await transaction.getAll(
        projectionRef, legacyRef, roleRef,
    );
    const projection = projectionSnap.exists ? projectionSnap.data() : {};
    const legacy = legacySnap.exists ? legacySnap.data() : {};
    const role = roleSnap.exists ? roleSnap.data() : {};
    const balance = roundWalletMoney(legacy.balance == null ?
      (legacy.rothCredit == null ? role.balance || 0 : legacy.rothCredit) : legacy.balance);
    const frozen = legacy.isFrozen === true || projection.status === "frozen";
    const now = FieldValue.serverTimestamp();
    const record = senderWalletProjectionRecord({
      userId: context.auth.uid,
      balance,
      frozen,
      version: Number(projection.version || 0) || 1,
      createdAt: projection.createdAt || legacy.createdAt || now,
      updatedAt: now,
    });
    transaction.set(projectionRef, record, {merge: true});
    transaction.set(legacyRef, {
      userId: identity.walletId, uid: context.auth.uid, userEmail: identity.userEmail,
      normalizedEmail: identity.userEmail, balance, rothCredit: balance,
      currency: legacy.currency || "GBP", isFrozen: frozen,
      createdAt: legacy.createdAt || now, updatedAt: now,
    }, {merge: true});
    transaction.set(roleRef, {
      balance, balanceRoth: balance, currency: "ROTH", walletType: "sender",
      createdAt: role.createdAt || now, updatedAt: now,
    }, {merge: true});
    result = {
      userId: context.auth.uid,
      balance,
      currency: "ROTH",
      status: frozen ? "frozen" : "active",
      version: record.version,
      ...(starterRoth ? {
        starterRothGranted: true,
        starterRothAmount: starterRoth.amount,
        starterRothTransactionId: starterRoth.transactionId,
      } : {}),
    };
  });
  return result;
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
  idempotencyKey = null,
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
  const operationKey = `${idempotencyKey || transactionId || providerTransactionId || ledgerRef.id}`.trim();
  const operationKeyId = crypto.createHash("sha256").update(operationKey).digest("hex");
  const idempotencyRef = db.collection("rothMovementIdempotency").doc(operationKeyId);
  const senderWalletRef = identity.uid ? db.collection("senderWallets").doc(identity.uid) : null;
  const acquisitionUid = identity.uid || (typeof userId === "string" && !userId.includes("@") ? userId : null);
  const acquisitionReward = acquisitionUid && (type === TRANSACTION_TYPES.referralWelcomeReward ||
    (type === TRANSACTION_TYPES.promotionalReward && transactionId === `sender_welcome_roth_${acquisitionUid}`));
  const acquisitionRefs = acquisitionReward ? [
    db.collection("walletTransactions").doc(`sender_welcome_roth_${acquisitionUid}`),
    db.collection("walletTransactions").doc(`referral_reward_${acquisitionUid}_referred`),
  ] : [];
  let creditedTransactionId = ledgerRef.id;
  await db.runTransaction(async (transaction) => {
    creditedTransactionId = ledgerRef.id;
    // One read operation cannot leave sibling reads using an aborted attempt.
    const snapshots = await transaction.getAll(
        ledgerRef, idempotencyRef, walletRef, ...(senderWalletRef ? [senderWalletRef] : []), ...acquisitionRefs,
    );
    const [existingLedger, existingIdempotency, wallet] = snapshots;
    const senderWalletSnap = senderWalletRef ? snapshots[3] : null;
    const acquisitionSnapshots = acquisitionReward ? snapshots.slice(senderWalletRef ? 4 : 3) : [];
    const signature = {
      walletId: identity.walletId,
      uid: identity.uid || null,
      amount: roundedAmount,
      balanceType,
      type,
      reason: reason || type,
    };
    const existingSignature = existingIdempotency.exists ? existingIdempotency.data() :
      existingLedger.exists ? existingLedger.data() : null;
    if (existingSignature) {
      const fieldsMatch = ["walletId", "uid", "amount", "balanceType", "type", "reason"]
        .every((field) => existingSignature[field] === signature[field]);
      if (!fieldsMatch) throw new Error("Roth idempotency key conflict.");
      creditedTransactionId = existingSignature.transactionId || ledgerRef.id;
      return;
    }
    let movementAmount = roundedAmount;
    if (acquisitionReward) {
      if (balanceType !== BALANCE_TYPES.rothCredit || roundedAmount <= 0 || ledgerOnly) throw new Error("Invalid newcomer reward");
      let previouslyGranted = 0;
      for (const snapshot of acquisitionSnapshots) {
        if (!snapshot.exists) continue;
        const prior = snapshot.data();
        if (!Number.isFinite(prior.amount) || prior.amount < 0 || (prior.uid && prior.uid !== acquisitionUid)) throw new Error("Newcomer reward history requires reconciliation");
        previouslyGranted += prior.amount;
      }
      movementAmount = roundMoney(Math.min(roundedAmount, Math.max(0, SENDER_WELCOME_ROTH_AMOUNT - previouslyGranted)));
      if (movementAmount === 0) {
        creditedTransactionId = acquisitionSnapshots.find((snapshot) => snapshot.exists).id;
        transaction.create(idempotencyRef, {...signature, idempotencyKey: operationKey,
          transactionId: creditedTransactionId, creditedAmount: 0, acquisitionCap: SENDER_WELCOME_ROTH_AMOUNT,
          status: "covered_by_existing_acquisition_reward", createdAt: FieldValue.serverTimestamp()});
        return;
      }
    }
    const walletData = wallet.exists ? wallet.data() : {};
    const senderWallet = senderWalletSnap && senderWalletSnap.exists ? senderWalletSnap.data() : {};
    const rawBalance = balanceType === BALANCE_TYPES.rothCredit ?
      (walletData.balance == null ? walletData.rothCredit : walletData.balance) :
      walletData[balanceType];
    const balanceBefore = roundMoney(rawBalance || 0);
    const balanceAfter = ledgerOnly ? balanceBefore : nextBalance({
      balanceBefore,
      amount: movementAmount,
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
    if (senderWalletRef && balanceType === BALANCE_TYPES.rothCredit && !ledgerOnly) {
      transaction.set(senderWalletRef, senderWalletProjectionRecord({
        userId: identity.uid,
        balance: balanceAfter,
        frozen: walletData.isFrozen === true,
        version: Number(senderWallet.version || 0) + 1,
        createdAt: senderWallet.createdAt || walletData.createdAt || now,
        updatedAt: now,
      }), {merge: true});
    }
    transaction.set(ledgerRef, {
      id: ledgerRef.id,
      transactionId: ledgerRef.id,
      userId: identity.walletId,
      uid: identity.uid,
      userEmail: identity.userEmail,
      normalizedEmail: identity.userEmail,
      walletId: identity.walletId,
      amount: movementAmount,
      direction: movementAmount < 0 ? "debit" : "credit",
      walletType: "sender",
      balanceType,
      type,
      reason: reason || type,
      description: reason || type,
      relatedEntityId,
      idempotencyKey: operationKey,
      createdBy: issuedByAdminId || "system",
      status: "completed",
      paymentProvider,
      providerTransactionId,
      paymentIntentId: metadata.stripePaymentIntentId || metadata.paymentIntentId || null,
      amountGBP: metadata.amountGBP == null ? null : roundMoney(metadata.amountGBP),
      rothIssued: metadata.rothIssued == null ? null : roundMoney(metadata.rothIssued),
      currency: metadata.currency || null,
      source: metadata.source || null,
      issuedByAdminId,
      issuedByAdminEmail,
      balanceBefore,
      balanceAfter,
      ledgerOnly,
      createdAt: now,
      metadata,
    });
    transaction.create(idempotencyRef, {
      ...signature,
      idempotencyKey: operationKey,
      transactionId: ledgerRef.id,
      createdAt: now,
    });
  });
  return {transactionId: creditedTransactionId};
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
exports.requireTrustedRothAdmin = requireTrustedRothAdmin;

async function grantSenderWelcomeRoth({uid, email = null, source = "sender_account"}) {
  const cleanUid = `${uid || ""}`.trim();
  if (!cleanUid) throw new Error("Sender welcome Roth requires uid.");
  const normalizedEmail = normalizeEmail(email || "");
  const transactionId = `sender_welcome_roth_${cleanUid}`;
  const movement = await recordRothMovement({
    userId: cleanUid,
    uid: cleanUid,
    userEmail: normalizedEmail || null,
    amount: SENDER_WELCOME_ROTH_AMOUNT,
    balanceType: BALANCE_TYPES.rothCredit,
    type: TRANSACTION_TYPES.promotionalReward,
    reason: SENDER_WELCOME_ROTH_REASON,
    relatedEntityId: cleanUid,
    transactionId,
    idempotencyKey: `sender_welcome_roth:${cleanUid}`,
    metadata: {
      source: "sender_welcome_roth",
      trigger: source,
      starterAmount: SENDER_WELCOME_ROTH_AMOUNT,
      policy: "new_sender_account_starter_roth",
    },
  });
  return {
    amount: SENDER_WELCOME_ROTH_AMOUNT,
    transactionId: movement.transactionId,
  };
}

exports.grantSenderWelcomeRoth = grantSenderWelcomeRoth;
exports.SENDER_WELCOME_ROTH_AMOUNT = SENDER_WELCOME_ROTH_AMOUNT;

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
  const senderWalletRef = identity.uid ? db.collection("senderWallets").doc(identity.uid) : null;
  await db.runTransaction(async (transaction) => {
    // A single read operation prevents sibling reads retaining an aborted attempt.
    const [walletSnap, existingTx, senderWalletSnap] = await transaction.getAll(
        walletRef, txRef, ...(senderWalletRef ? [senderWalletRef] : []),
    );
    if (existingTx.exists) return;
    const wallet = walletSnap.exists ? walletSnap.data() : {};
    if (wallet.isFrozen === true) throw new Error("Wallet is frozen.");
    const before = roundWalletMoney(wallet.balance == null ? wallet.rothCredit : wallet.balance);
    if (before < debit) throw new Error("Wallet balance is too low.");
    const after = roundWalletMoney(before - debit);
    const senderWallet = senderWalletSnap && senderWalletSnap.exists ? senderWalletSnap.data() : {};
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
    if (senderWalletRef) {
      transaction.set(senderWalletRef, senderWalletProjectionRecord({
        userId: identity.uid,
        balance: after,
        frozen: wallet.isFrozen === true,
        version: Number(senderWallet.version || 0) + 1,
        createdAt: senderWallet.createdAt || wallet.createdAt || now,
        updatedAt: now,
      }), {merge: true});
    }
    transaction.set(txRef, {
      id: txRef.id,
      userId: identity.walletId,
      uid: identity.uid,
      userEmail: identity.userEmail,
      normalizedEmail: identity.userEmail,
      walletId: identity.walletId,
      type,
      amount: -debit,
      direction: "debit",
      walletType: "sender",
      balanceType: BALANCE_TYPES.rothCredit,
      balanceBefore: before,
      balanceAfter: after,
      referenceId,
      relatedEntityId: referenceId,
      notes,
      description: notes || type,
      idempotencyKey: transactionId || txRef.id,
      createdBy: "system",
      status: "completed",
      paymentProvider: "roth_internal",
      createdAt: now,
      metadata,
    });
  });
  return {walletContributionGbp: debit, transactionId: txRef.id};
}

exports.applyWalletDebit = applyWalletDebit;

exports.initialiseSenderWallet = senderPaymentCallable(async (_data, context) => {
  return initialiseSenderWalletRecord(context);
});

exports.getSenderWallet = senderPaymentCallable(async (_data, context) => {
  return initialiseSenderWalletRecord(context);
});

exports.getSenderWalletTransactions = senderPaymentCallable(async (data, context) => {
  const identity = await requireSenderIdentity(context);
  const db = getFirestore();
  const walletSnap = await db.collection("walletTransactions")
      .where("walletId", "==", identity.walletId)
      .orderBy("createdAt", "desc")
      .limit(100)
      .get();
  const legacyUidSnap = walletSnap.empty ? await db.collection("walletTransactions")
      .where("uid", "==", context.auth.uid)
      .orderBy("createdAt", "desc")
      .limit(100)
      .get() : {docs: []};
  const seen = new Set();
  const records = [...walletSnap.docs, ...legacyUidSnap.docs].filter((doc) => {
    if (seen.has(doc.id)) return false;
    seen.add(doc.id);
    return true;
  }).map((doc) => {
    const value = walletTransactionView({...doc.data(), transactionId: doc.id});
    const createdAt = doc.data().createdAt;
    return {...value, createdAtMillis: createdAt && typeof createdAt.toMillis === "function" ? createdAt.toMillis() : 0};
  });
  const page = paginateWalletTransactions(records, {
    pageSize: data && data.pageSize,
    pageOffset: Number(data && data.pageToken || 0),
  });
  return {
    transactions: page.records.map(({createdAtMillis, ...record}) => record),
    nextPageToken: page.nextPageToken,
  };
});

exports.completeSenderWalletOnboarding = senderPaymentCallable(async (_data, context) => {
  await requireSenderIdentity(context);
  await getFirestore().collection("users").doc(context.auth.uid).set({
    senderWalletOnboardingCompleted: true,
    senderWalletOnboardingCompletedAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  return {completed: true};
});

exports.requestSenderWalletDebit = senderPaymentCallable(async (data, context) => {
  await requireSenderIdentity(context);
  const amount = roundWalletMoney(data.amount);
  const idempotencyKey = `${data.idempotencyKey || ""}`.trim();
  const relatedEntityId = `${data.relatedEntityId || ""}`.trim();
  if (amount <= 0 || !idempotencyKey || !relatedEntityId) {
    throw new functions.https.HttpsError("invalid-argument", "A positive amount, reference and idempotency key are required.");
  }
  try {
    return await applyWalletDebit({
      userId: context.auth.uid, uid: context.auth.uid, userEmail: context.auth.token.email,
      amount, type: TRANSACTION_TYPES.checkoutSpend, referenceId: relatedEntityId,
      notes: "Roth used on an eligible Circum purchase.", transactionId: idempotencyKey,
      metadata: {source: "sender_wallet", ...(data.metadata || {})},
    });
  } catch (error) {
    throw new functions.https.HttpsError("failed-precondition", error.message);
  }
});

exports.requestSenderWalletRefund = senderPaymentCallable(async (data, context) => {
  const admin = await requireTrustedRothAdmin(context);
  const amount = roundWalletMoney(data.amount);
  const idempotencyKey = `${data.idempotencyKey || ""}`.trim();
  if (amount <= 0 || !idempotencyKey || !data.userId) {
    throw new functions.https.HttpsError("invalid-argument", "User, positive amount and idempotency key are required.");
  }
  return recordRothMovement({
    userId: data.userId, userEmail: data.email || null, amount,
    balanceType: BALANCE_TYPES.rothCredit, type: TRANSACTION_TYPES.refund,
    reason: `${data.reason || "Roth refund"}`, relatedEntityId: data.relatedEntityId || null,
    transactionId: idempotencyKey, issuedByAdminId: admin.uid, issuedByAdminEmail: admin.email,
    metadata: {source: "sender_wallet_refund"},
  });
});

exports.createWalletTopUp = (stripe) => senderPaymentCallable(async (data, context) => {
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
    client_reference_id: identity.walletId,
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
  let purchase;
  try {
    purchase = verifiedStripeRothPurchase(sessionData, {
      ownerId: metadata.userId || metadata.uid,
      ownerEmail: metadata.userEmail,
    });
  } catch (error) {
    if (metadata.uid) {
      try {
        await communicationEngine.emitNotification({
          recipientId: metadata.uid,
          recipientRole: "sender",
          type: "roth_purchase_failed",
          title: "Roth purchase needs attention",
          body: "We could not add Roth from this payment. No Roth has been credited.",
          data: {
            correlationId: `wallet_top_up_${sessionData.id || eventId || "unknown"}`,
            stripeEventId: eventId || "",
            stripeCheckoutSessionId: sessionData.id || "",
            paymentIntentId: sessionData.payment_intent || "",
            failureCode: "payment_not_verified",
          },
        });
      } catch (notificationError) {
        console.error("Roth purchase failure notification failed", {
          userId: metadata.userId || null,
          uid: metadata.uid || null,
          sessionId: sessionData.id || null,
          error: notificationError && notificationError.message ? notificationError.message : notificationError,
        });
      }
    }
    throw error;
  }
  const amount = purchase.rothIssued;
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
      amountGBP: purchase.amountGBP,
      rothIssued: purchase.rothIssued,
      currency: purchase.currency,
      source: "purchase",
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
  if (metadata.uid) {
    try {
      await communicationEngine.emitNotification({
        recipientId: metadata.uid,
        recipientRole: "sender",
        type: "roth_purchase_completed",
        title: "Roth added",
        body: `${amount} Roth has been added to your wallet.`,
        data: {
          correlationId: transactionId,
          transactionId,
          paymentIntentId: sessionData.payment_intent || "",
          amountGBP: `${purchase.amountGBP}`,
          rothIssued: `${purchase.rothIssued}`,
        },
      });
    } catch (error) {
      console.error("Roth purchase notification failed", {
        userId: metadata.userId || null,
        uid: metadata.uid || null,
        transactionId,
        error: error && error.message ? error.message : error,
      });
    }
  }
  return {...movement, progression};
}

exports.recordWalletTopUpFromStripeSession = recordWalletTopUpFromStripeSession;

exports.applyCheckoutRoth = senderPaymentCallable(async (data, context) => {
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

exports.debitRothCredit = senderPaymentCallable(async (data, context) => {
  await requireRothAdmin(context);
  const rawUser = `${data.userId || data.email || ""}`.trim();
  const amount = Number(data.amount || 0);
  const reason = `${data.reason || ""}`.trim();
  const idempotencyKey = `${data.idempotencyKey || data.adminIssueId || ""}`.trim();
  if (!rawUser || amount <= 0 || !reason || !idempotencyKey) {
    throw new functions.https.HttpsError("invalid-argument", "User, amount, reason and idempotency key are required.");
  }
  const identity = await resolveWalletIdentity({userId: rawUser, email: data.email});
  const transactionId = `admin_roth_debit_${idempotencyKey}`;
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
    transactionId,
    idempotencyKey,
    metadata: {source: "admin_debit_roth", input: rawUser, idempotencyKey},
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
  await requireRothAdmin(context);
  const userId = `${data.userId || data.email || ""}`.trim();
  const frozen = data.isFrozen === true;
  const reason = `${data.reason || ""}`.trim();
  if (!userId || !reason) {
    throw new functions.https.HttpsError("invalid-argument", "User and reason are required.");
  }
  const identity = await resolveWalletIdentity({userId, email: data.email});
  const db = getFirestore();
  await db.runTransaction(async (transaction) => {
    const legacyRef = db.collection("wallets").doc(identity.walletId);
    const projectionRef = identity.uid ? db.collection("senderWallets").doc(identity.uid) : null;
    const [legacySnap, projectionSnap] = await Promise.all([
      transaction.get(legacyRef), projectionRef ? transaction.get(projectionRef) : Promise.resolve(null),
    ]);
    const legacy = legacySnap.exists ? legacySnap.data() : {};
    const projection = projectionSnap && projectionSnap.exists ? projectionSnap.data() : {};
    const now = FieldValue.serverTimestamp();
    transaction.set(legacyRef, {
      userId: identity.walletId, uid: identity.uid, userEmail: identity.userEmail,
      normalizedEmail: identity.userEmail, isFrozen: frozen, currency: "GBP", updatedAt: now,
    }, {merge: true});
    if (projectionRef) {
      transaction.set(projectionRef, senderWalletProjectionRecord({
        userId: identity.uid,
        balance: projection.balance == null ? (legacy.balance == null ? legacy.rothCredit || 0 : legacy.balance) : projection.balance,
        frozen, version: Number(projection.version || 0) + 1,
        createdAt: projection.createdAt || legacy.createdAt || now, updatedAt: now,
      }), {merge: true});
    }
  });
  await writeRothAudit({
    adminId: context.auth.uid,
    adminEmail: context.auth.token.email || null,
    action: frozen ? "wallet_frozen" : "wallet_unfrozen",
    userId: identity.walletId,
    reason,
  });
  return {userId: identity.walletId, isFrozen: frozen};
});

exports.redeemGiftCard = senderPaymentCallable(async (data, context) => {
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
  const senderWalletRef = db.collection("senderWallets").doc(context.auth.uid);
  await db.runTransaction(async (transaction) => {
    const [cardSnap, walletSnap, existingTx, senderWalletSnap] = await Promise.all([
      transaction.get(cardRef),
      transaction.get(walletRef),
      transaction.get(txRef),
      transaction.get(senderWalletRef),
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
    const senderWallet = senderWalletSnap.exists ? senderWalletSnap.data() : {};
    transaction.set(senderWalletRef, senderWalletProjectionRecord({
      userId: context.auth.uid, balance: after, frozen: false,
      version: Number(senderWallet.version || 0) + 1,
      createdAt: senderWallet.createdAt || wallet.createdAt || now, updatedAt: now,
    }), {merge: true});
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
