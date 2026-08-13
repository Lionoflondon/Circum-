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
  verifiedStripeRothPurchase,
  senderWalletProjectionRecord,
  walletTransactionView,
} = require("./roth-ledger-core");
const {
  canRedeemGiftCard,
  normalizeEmail,
  roundMoney: roundWalletMoney,
  walletIdForEmail,
} = require("./wallet-core");
const communicationEngine = require("./communication-engine");
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

async function initialiseSenderWalletRecord(context) {
  const identity = await requireSenderIdentity(context);
  const db = getFirestore();
  const projectionRef = db.collection("senderWallets").doc(context.auth.uid);
  const legacyRef = db.collection("wallets").doc(identity.walletId);
  const roleRef = db.collection("users").doc(context.auth.uid).collection("wallets").doc("sender");
  let result;
  await db.runTransaction(async (transaction) => {
    const [projectionSnap, legacySnap, roleSnap] = await Promise.all([
      transaction.get(projectionRef), transaction.get(legacyRef), transaction.get(roleRef),
    ]);
    const projection = projectionSnap.exists ? projectionSnap.data() : {};
    const legacy = legacySnap.exists ? legacySnap.data() : {};
    const role = roleSnap.exists ? roleSnap.data() : {};
    const balance = roundWalletMoney(legacySnap.exists ?
      (legacy.balance == null ? legacy.rothCredit || 0 : legacy.balance) :
      (projection.balanceRoth == null ? projection.balance || 0 : projection.balanceRoth));
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
    transaction.set(projectionRef, {
      ...record,
      authority: "projection",
      projectionOf: `wallets/${identity.walletId}`,
    }, {merge: true});
    transaction.set(legacyRef, {
      userId: identity.walletId, uid: context.auth.uid, userEmail: identity.userEmail,
      normalizedEmail: identity.userEmail, balance, rothCredit: balance,
      authority: "canonical_ledger_balance",
      currency: legacy.currency || "GBP", isFrozen: frozen,
      createdAt: legacy.createdAt || now, updatedAt: now,
    }, {merge: true});
    transaction.set(roleRef, {
      balance, balanceRoth: balance, currency: "ROTH", walletType: "sender",
      authority: "projection", projectionOf: `wallets/${identity.walletId}`,
      createdAt: role.createdAt || now, updatedAt: now,
    }, {merge: true});
    result = {
      userId: context.auth.uid,
      balance,
      currency: "ROTH",
      status: frozen ? "frozen" : "active",
      version: record.version,
    };
  });
  return result;
}

async function initialiseRiderWalletRecord(context, {markOnboarding = false} = {}) {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Sign in to access your Roth Wallet.");
  }
  const identity = await resolveWalletIdentity({
    userId: context.auth.uid,
    email: context.auth.token.email,
    authUid: context.auth.uid,
  });
  const db = getFirestore();
  const riderRef = db.collection("riders").doc(context.auth.uid);
  const walletRef = db.collection("wallets").doc(identity.walletId);
  const projectionRef = db.collection("riderRothWallets").doc(context.auth.uid);
  const auditRef = db.collection("riderOnboardingEvents").doc(`roth_wallet_${context.auth.uid}`);
  let result;
  await db.runTransaction(async (transaction) => {
    const [riderSnap, walletSnap, projectionSnap, auditSnap] = await Promise.all([
      transaction.get(riderRef),
      transaction.get(walletRef),
      transaction.get(projectionRef),
      markOnboarding ? transaction.get(auditRef) : Promise.resolve(null),
    ]);
    if (!riderSnap.exists) {
      throw new functions.https.HttpsError("permission-denied", "Rider wallet access denied.");
    }
    const wallet = walletSnap.exists ? walletSnap.data() : {};
    const projection = projectionSnap.exists ? projectionSnap.data() : {};
    const balance = roundWalletMoney(walletSnap.exists ?
      (wallet.balance == null ? wallet.rothCredit || 0 : wallet.balance) : 0);
    if (balance < 0) {
      throw new functions.https.HttpsError("failed-precondition", "Roth Wallet balance requires review.");
    }
    const frozen = wallet.isFrozen === true || projection.status === "frozen";
    const now = FieldValue.serverTimestamp();
    transaction.set(walletRef, {
      userId: identity.walletId,
      uid: context.auth.uid,
      userEmail: identity.userEmail,
      normalizedEmail: identity.userEmail,
      authority: "canonical_ledger_balance",
      balance,
      rothCredit: balance,
      currency: wallet.currency || "GBP",
      isFrozen: frozen,
      pendingEarnings: roundWalletMoney(wallet.pendingEarnings || 0),
      availableEarnings: roundWalletMoney(wallet.availableEarnings || 0),
      createdAt: wallet.createdAt || now,
      updatedAt: now,
    }, {merge: true});
    transaction.set(projectionRef, {
      riderId: context.auth.uid,
      balance,
      available: balance,
      pending: 0,
      currency: "ROTH",
      status: frozen ? "frozen" : "active",
      authority: "projection",
      projectionOf: `wallets/${identity.walletId}`,
      version: Math.max(1, Number(projection.version || 0) + 1),
      createdAt: projection.createdAt || now,
      updatedAt: now,
    }, {merge: true});
    if (markOnboarding) {
      const onboardingStatus = projectionSnap.exists ? "connected" : "wallet_created";
      transaction.set(riderRef, {
        rothOnboardingComplete: true,
        rothOnboardingStatus: onboardingStatus,
        rothWalletId: projectionRef.id,
        rothWalletConnectedAt: now,
        updatedAt: now,
      }, {merge: true});
      transaction.set(auditRef, {
        type: projectionSnap.exists ? "roth_wallet_connected" : "roth_wallet_created",
        riderId: context.auth.uid,
        actorType: "rider",
        actorId: context.auth.uid,
        actorEmail: context.auth.token.email || null,
        source: "cloud-functions",
        walletId: projectionRef.id,
        statusAfterEvent: onboardingStatus,
        createdAt: auditSnap && auditSnap.exists ? auditSnap.data().createdAt : now,
        updatedAt: now,
      }, {merge: true});
    }
    result = {
      ok: true,
      walletCreated: !projectionSnap.exists,
      walletExisted: projectionSnap.exists,
      balance,
      currency: "ROTH",
      status: frozen ? "frozen" : "active",
    };
  });
  return result;
}

exports.initialiseRiderWalletRecord = initialiseRiderWalletRecord;

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
  const senderWalletRef = identity.uid ? db.collection("senderWallets").doc(identity.uid) : null;
  const roleWalletRef = identity.uid ?
    db.collection("users").doc(identity.uid).collection("wallets").doc("sender") : null;
  let result = {transactionId: ledgerRef.id};
  await db.runTransaction(async (transaction) => {
    const [existingLedger, wallet, senderWalletSnap, roleWalletSnap] = await Promise.all([
      transaction.get(ledgerRef),
      transaction.get(walletRef),
      senderWalletRef ? transaction.get(senderWalletRef) : Promise.resolve(null),
      roleWalletRef ? transaction.get(roleWalletRef) : Promise.resolve(null),
    ]);
    if (existingLedger.exists) {
      const existing = existingLedger.data();
      const sameMovement = existing.walletId === identity.walletId &&
        roundMoney(existing.amount) === roundedAmount &&
        existing.balanceType === balanceType && existing.type === type &&
        `${existing.relatedEntityId || ""}` === `${relatedEntityId || ""}`;
      if (!sameMovement) throw new Error("Idempotency key is already bound to another Roth movement.");
      result = {transactionId: ledgerRef.id, idempotent: true};
      return;
    }
    const walletData = wallet.exists ? wallet.data() : {};
    const senderWallet = senderWalletSnap && senderWalletSnap.exists ? senderWalletSnap.data() : {};
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
      authority: "canonical_ledger_balance",
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
      transaction.set(senderWalletRef, {
        ...senderWalletProjectionRecord({
          userId: identity.uid,
          balance: balanceAfter,
          frozen: walletData.isFrozen === true,
          version: Number(senderWallet.version || 0) + 1,
          createdAt: senderWallet.createdAt || walletData.createdAt || now,
          updatedAt: now,
        }),
        authority: "projection",
        projectionOf: `wallets/${identity.walletId}`,
      }, {merge: true});
    }
    if (roleWalletRef && balanceType === BALANCE_TYPES.rothCredit && !ledgerOnly) {
      const roleWallet = roleWalletSnap && roleWalletSnap.exists ? roleWalletSnap.data() : {};
      transaction.set(roleWalletRef, {
        balance: balanceAfter,
        balanceRoth: balanceAfter,
        currency: "ROTH",
        walletType: "sender",
        authority: "projection",
        projectionOf: `wallets/${identity.walletId}`,
        createdAt: roleWallet.createdAt || walletData.createdAt || now,
        updatedAt: now,
      }, {merge: true});
    }
    transaction.set(ledgerRef, {
      id: ledgerRef.id,
      transactionId: ledgerRef.id,
      userId: identity.walletId,
      uid: identity.uid,
      userEmail: identity.userEmail,
      normalizedEmail: identity.userEmail,
      walletId: identity.walletId,
      amount: roundedAmount,
      direction: roundedAmount < 0 ? "debit" : "credit",
      walletType: "sender",
      balanceType,
      type,
      reason: reason || type,
      description: reason || type,
      relatedEntityId,
      idempotencyKey: transactionId || providerTransactionId || ledgerRef.id,
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
    if (issuedByAdminId && transactionId) {
      transaction.set(db.collection("adminAuditLogs").doc(`roth_${ledgerRef.id}`), {
        adminUserId: issuedByAdminId,
        adminEmail: issuedByAdminEmail || null,
        actionType: roundedAmount < 0 ? "roth_credit_debited" : "roth_credit_issued",
        recordType: "wallets",
        recordId: identity.walletId,
        newValue: {amount: roundedAmount, reason: reason || type, transactionId: ledgerRef.id},
        createdAt: now,
      });
    }
  });
  return result;
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
  const senderWalletRef = identity.uid ? db.collection("senderWallets").doc(identity.uid) : null;
  await db.runTransaction(async (transaction) => {
    const [walletSnap, existingTx, senderWalletSnap] = await Promise.all([
      transaction.get(walletRef),
      transaction.get(txRef),
      senderWalletRef ? transaction.get(senderWalletRef) : Promise.resolve(null),
    ]);
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

exports.initialiseSenderWallet = functions.runWith({enforceAppCheck: true}).https.onCall(async (_data, context) => {
  return initialiseSenderWalletRecord(context);
});

exports.getSenderWallet = functions.runWith({enforceAppCheck: true}).https.onCall(async (_data, context) => {
  return initialiseSenderWalletRecord(context);
});

async function walletTransactionsPage({identity, uid, data, walletType}) {
  const db = getFirestore();
  const requestedPageSize = Number(data && data.pageSize || 20);
  const pageSize = Number.isFinite(requestedPageSize) ?
    Math.min(50, Math.max(1, Math.floor(requestedPageSize))) : 20;
  const pageToken = `${data && data.pageToken || ""}`.trim();
  const legacyPage = pageToken.startsWith("legacy:");
  const cursorId = legacyPage ? pageToken.slice("legacy:".length) : pageToken;
  let query = db.collection("walletTransactions")
      .where("walletId", "==", identity.walletId)
      .orderBy("createdAt", "desc")
      .orderBy("__name__", "desc")
      .limit(pageSize + 1);
  if (cursorId && !legacyPage) {
    const cursor = await db.collection("walletTransactions").doc(cursorId).get();
    if (!cursor.exists || cursor.data().walletId !== identity.walletId) {
      throw new functions.https.HttpsError("invalid-argument", "Wallet history cursor is invalid.");
    }
    query = query.startAfter(cursor);
  }
  const walletSnap = legacyPage ? {empty: true, docs: []} : await query.get();
  let legacyQuery = db.collection("walletTransactions")
      .where("uid", "==", uid)
      .orderBy("createdAt", "desc")
      .orderBy("__name__", "desc")
      .limit(pageSize + 1);
  if (legacyPage) {
    const cursor = await db.collection("walletTransactions").doc(cursorId).get();
    if (!cursor.exists || cursor.data().uid !== uid) {
      throw new functions.https.HttpsError("invalid-argument", "Wallet history cursor is invalid.");
    }
    legacyQuery = legacyQuery.startAfter(cursor);
  }
  const legacyUidSnap = walletSnap.empty ? await legacyQuery.get() : {docs: []};
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
  const page = records.slice(0, pageSize);
  return {
    transactions: page.map(({createdAtMillis, ...record}) => ({...record, walletType})),
    nextPageToken: records.length > pageSize ? (walletSnap.docs.length > 0 ?
      walletSnap.docs[pageSize - 1].id : `legacy:${legacyUidSnap.docs[pageSize - 1].id}`) : null,
  };
}

exports.getSenderWalletTransactions = functions.runWith({enforceAppCheck: true}).https.onCall(async (data, context) => {
  const identity = await requireSenderIdentity(context);
  return walletTransactionsPage({identity, uid: context.auth.uid, data, walletType: "sender"});
});

exports.getRiderRothWallet = functions.runWith({enforceAppCheck: true}).https.onCall(async (_data, context) => {
  return initialiseRiderWalletRecord(context);
});

exports.getRiderRothTransactions = functions.runWith({enforceAppCheck: true}).https.onCall(async (data, context) => {
  const wallet = await initialiseRiderWalletRecord(context);
  const identity = await resolveWalletIdentity({
    userId: context.auth.uid,
    email: context.auth.token.email,
    authUid: context.auth.uid,
  });
  const page = await walletTransactionsPage({
    identity,
    uid: context.auth.uid,
    data,
    walletType: "rider",
  });
  return {...page, balance: wallet.balance, currency: wallet.currency, status: wallet.status};
});

exports.completeSenderWalletOnboarding = functions.runWith({enforceAppCheck: true}).https.onCall(async (_data, context) => {
  await requireSenderIdentity(context);
  await getFirestore().collection("users").doc(context.auth.uid).set({
    senderWalletOnboardingCompleted: true,
    senderWalletOnboardingCompletedAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  return {completed: true};
});

exports.requestSenderWalletDebit = functions.runWith({enforceAppCheck: true}).https.onCall(async (_data, context) => {
  await requireSenderIdentity(context);
  throw new functions.https.HttpsError(
      "permission-denied",
      "Roth is applied only through a verified CIRCUM checkout.",
  );
});

exports.requestSenderWalletRefund = functions.runWith({enforceAppCheck: true}).https.onCall(async (data, context) => {
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

exports.createWalletTopUp = (stripe) => functions.runWith({enforceAppCheck: true}).https.onCall(async (data, context) => {
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

exports.applyCheckoutRoth = functions.runWith({enforceAppCheck: true}).https.onCall(async (_data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Sign in to use Roth.");
  }
  throw new functions.https.HttpsError(
      "permission-denied",
      "Roth is applied only through the canonical payment session.",
  );
});

exports.issueRothToWallets = functions.runWith({enforceAppCheck: true}).https.onCall(async (data, context) => {
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
    const senderProjectionRef = targets.includes("sender") ?
      db.collection("senderWallets").doc(recipient.uid) : null;
    const legacyTxRef = targets.includes("sender") ?
      db.collection("walletTransactions").doc(`${adminIssueId}_sender_legacy`) : null;
    const legacyWalletSnap = legacyWalletRef ? await transaction.get(legacyWalletRef) : null;
    const legacyTxSnap = legacyTxRef ? await transaction.get(legacyTxRef) : null;
    const senderProjectionSnap = senderProjectionRef ? await transaction.get(senderProjectionRef) : null;
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
        const projection = senderProjectionSnap && senderProjectionSnap.exists ? senderProjectionSnap.data() : {};
        transaction.set(senderProjectionRef, senderWalletProjectionRecord({
          userId: recipient.uid, balance: after, frozen: legacyWallet.isFrozen === true,
          version: Number(projection.version || 0) + 1,
          createdAt: projection.createdAt || legacyWallet.createdAt || now, updatedAt: now,
        }), {merge: true});
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

exports.issueRothCredit = functions.runWith({enforceAppCheck: true}).https.onCall(async (data, context) => {
  requireRothAdmin(context);
  const rawUser = `${data.userId || data.email || ""}`.trim();
  const amount = Number(data.amount || 0);
  const reason = `${data.reason || ""}`.trim();
  const idempotencyKey = `${data.idempotencyKey || data.adminIssueId || ""}`.trim();
  if (!rawUser || amount <= 0 || !reason || !idempotencyKey) {
    throw new functions.https.HttpsError("invalid-argument", "User, amount, reason and idempotency key are required.");
  }
  const identity = await resolveWalletIdentity({userId: rawUser, email: data.email});
  const transactionId = `admin_roth_credit_${idempotencyKey}`;
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
    transactionId,
    metadata: {
      source: "admin_issue_roth",
      input: rawUser,
      idempotencyKey,
      correlationId: transactionId,
    },
  });
  await writeRothAudit({
    adminId: context.auth.uid,
    adminEmail: context.auth.token.email || null,
    action: "roth_credit_issued",
    userId: identity.walletId,
    amount,
    reason,
    metadata: {uid: identity.uid, userEmail: identity.userEmail, idempotencyKey, transactionId},
  });
  return result;
});

exports.debitRothCredit = functions.runWith({enforceAppCheck: true}).https.onCall(async (data, context) => {
  requireRothAdmin(context);
  const rawUser = `${data.userId || data.email || ""}`.trim();
  const amount = Number(data.amount || 0);
  const reason = `${data.reason || ""}`.trim();
  const idempotencyKey = `${data.idempotencyKey || ""}`.trim();
  if (!rawUser || amount <= 0 || !reason || !idempotencyKey) {
    throw new functions.https.HttpsError("invalid-argument", "User, amount, reason and idempotency key are required.");
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
    transactionId: `admin_roth_debit_${idempotencyKey}`,
    relatedEntityId: `${data.relatedEntityId || idempotencyKey}`,
    metadata: {source: "admin_debit_roth", input: rawUser},
  });
  return result;
});

exports.setWalletFrozen = functions.runWith({enforceAppCheck: true}).https.onCall(async (data, context) => {
  requireRothAdmin(context);
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

exports.redeemGiftCard = functions.runWith({enforceAppCheck: true}).https.onCall(async (data, context) => {
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
