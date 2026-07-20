/* eslint-disable max-len, require-jsdoc */
"use strict";

const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {emitNotification} = require("./communication-engine");

const ADMIN_TRUST_ROLES = new Set([
  "admin",
  "super_admin",
  "operations_admin",
  "support_agent",
]);

function clean(value) {
  return `${value || ""}`.trim();
}

function tierForPoints(points) {
  if (points >= 750) return "platinum_sender";
  if (points >= 300) return "priority_sender";
  if (points >= 100) return "regular_sender";
  if (points >= 25) return "active_sender";
  return "new_sender";
}

function normalizeTier(value, points = 0) {
  const raw = `${value || ""}`.trim().toLowerCase().replace(/[-\s]+/g, "_");
  return ["new_sender", "active_sender", "regular_sender", "priority_sender", "platinum_sender"].includes(raw) ? raw : tierForPoints(points);
}

function tokenRoles(token = {}) {
  const roles = Array.isArray(token.roles) ? token.roles : [];
  return [
    token.adminRole,
    token.role,
    ...roles,
  ].map((role) => clean(role).toLowerCase()).filter(Boolean);
}

function tokenHasTrustAdminRole(token = {}) {
  if (token.admin === true || token.superAdmin === true ||
      token.super_admin === true) {
    return true;
  }
  return tokenRoles(token).some((role) => ADMIN_TRUST_ROLES.has(role));
}

async function requireSenderTrustAdmin(db, context) {
  if (!context.auth || !context.auth.uid) {
    throw new functions.https.HttpsError("unauthenticated", "Sign in first.");
  }
  if (tokenHasTrustAdminRole(context.auth.token || {})) {
    return {
      uid: context.auth.uid,
      email: clean(context.auth.token.email),
      role: tokenRoles(context.auth.token || {})[0] || "admin",
    };
  }
  const email = clean(context.auth.token && context.auth.token.email).toLowerCase();
  const candidates = [context.auth.uid];
  if (email) candidates.push(email);
  for (const id of candidates) {
    const snapshot = await db.collection("adminUsers").doc(id).get();
    if (!snapshot.exists) continue;
    const data = snapshot.data() || {};
    const status = clean(data.status || "active").toLowerCase();
    const role = clean(data.role).toLowerCase();
    if (["disabled", "inactive", "suspended", "revoked"].includes(status)) {
      continue;
    }
    if (ADMIN_TRUST_ROLES.has(role)) {
      return {
        uid: context.auth.uid,
        email: clean(context.auth.token.email || data.email),
        role,
      };
    }
  }
  throw new functions.https.HttpsError(
      "permission-denied",
      "Sender trust updates require Admin customer permissions.",
  );
}

function trustActionRequest(data = {}) {
  const senderId = clean(data.senderId || data.userId);
  const action = clean(data.action).toLowerCase();
  const reason = clean(data.reason).slice(0, 500);
  const supported = new Set(["award", "deduct", "promote", "demote", "freeze", "restore"]);
  if (!senderId || !supported.has(action)) {
    throw new functions.https.HttpsError(
        "invalid-argument",
        "A sender and supported trust action are required.",
    );
  }
  if (!reason) {
    throw new functions.https.HttpsError(
        "invalid-argument",
        "A reason is required for Sender trust changes.",
    );
  }
  const points = Math.abs(Math.trunc(Number(data.points || data.pointsDelta || 0)));
  if (["award", "deduct"].includes(action) && points <= 0) {
    throw new functions.https.HttpsError(
        "invalid-argument",
        "Trust point changes must be greater than zero.",
    );
  }
  const tier = clean(data.tier || data.senderTier || data.trustTier);
  if (["promote", "demote"].includes(action) && !tier) {
    throw new functions.https.HttpsError(
        "invalid-argument",
        "Choose the target Sender trust tier.",
    );
  }
  return {senderId, action, reason, points, tier};
}

function money(value) {
  const parsed = Number(value || 0);
  return Number.isFinite(parsed) ? parsed : 0;
}

function isCompleted(status) {
  return ["completed", "complete", "delivered"].includes(`${status || ""}`.toLowerCase());
}

function deliveryValue(data) {
  return money(data.price || data.quote || data.amount || data.finalCustomerPrice || data.total);
}

function rothTopUpPoints(amount) {
  const value = money(amount);
  if (value <= 0) return 0;
  if (value <= 25) return 1;
  if (value <= 50) return 2;
  if (value <= 100) return 3;
  if (value <= 250) return 4;
  if (value <= 500) return 5;
  return 6;
}

function isSenderEligibleForRothProgression(user) {
  const roles = Array.isArray(user.roles) ?
    user.roles.map((role) => `${role}`.toLowerCase()) : [];
  const userType = `${user.userType || user.role || ""}`.toLowerCase();
  const riderOnly = ["rider", "driver"].includes(userType) &&
    !roles.some((role) => ["sender", "customer", "user"].includes(role));
  return !riderOnly;
}

async function awardRothTopUpProgression({
  uid,
  userEmail,
  amount,
  stripeSessionId,
  walletTransactionId,
}) {
  if (!uid || !stripeSessionId) return {awarded: false, points: 0};
  const points = rothTopUpPoints(amount);
  if (points <= 0) return {awarded: false, points: 0};
  const db = getFirestore();
  const userRef = db.collection("users").doc(uid);
  const eventRef = db.collection("senderTrustEvents")
      .doc(`roth_topup_${stripeSessionId}`);
  const ledgerRef = walletTransactionId ?
    db.collection("walletTransactions").doc(walletTransactionId) : null;
  let awarded = false;
  await db.runTransaction(async (transaction) => {
    const eventSnap = await transaction.get(eventRef);
    if (eventSnap.exists) return;
    const userSnap = await transaction.get(userRef);
    const user = userSnap.exists ? userSnap.data() : {};
    if (!isSenderEligibleForRothProgression(user)) return;
    const previousPoints = Number(
        user.senderTrustPoints || user.trustPoints || 0,
    );
    const previousTier = normalizeTier(
        user.senderTier || user.trustTier,
        previousPoints,
    );
    const newPoints = previousPoints + points;
    const frozen = user.senderTrustFrozen === true;
    const newTier = frozen ? previousTier : tierForPoints(newPoints);
    const breakdown = user.senderTrustBreakdown || {};
    const timestamp = FieldValue.serverTimestamp();
    transaction.set(userRef, {
      senderTrustPoints: newPoints,
      senderTier: newTier,
      senderTrustBreakdown: {
        ...breakdown,
        rothTopUps: Number(breakdown.rothTopUps || 0) + points,
      },
      senderTrustUpdatedAt: timestamp,
      senderTrustUpdatedBy: "system",
      senderTrustLastReason:
        `Roth top-up reward: +${points} progression points`,
      updatedAt: timestamp,
    }, {merge: true});
    transaction.create(eventRef, {
      userId: uid,
      userName: user.fullName || user.name || "Sender",
      userEmail: user.email || userEmail || null,
      eventType: "roth_top_up_reward",
      pointsChange: points,
      reason: `Roth top-up reward: +${points} progression points`,
      source: "system",
      awardedBy: "system",
      relatedEntityId: stripeSessionId,
      topUpAmount: money(amount),
      previousPoints,
      newPoints,
      previousTier,
      newTier,
      createdAt: timestamp,
    });
    if (ledgerRef) {
      transaction.set(ledgerRef, {
        progressionPointsAwarded: points,
        progressionLabel:
          `Roth top-up reward: +${points} progression points`,
        updatedAt: timestamp,
      }, {merge: true});
    }
    awarded = true;
  });
  return {awarded, points: awarded ? points : 0};
}

async function readSenderDeliveries(db, uid) {
  const snapshots = await Promise.all([
    db.collection("deliveryRequests").where("senderId", "==", uid).get(),
    db.collection("deliveryRequests").where("userId", "==", uid).get(),
    db.collection("history").where("userId", "==", uid).get(),
  ]);
  const byId = new Map();
  for (const snapshot of snapshots) {
    for (const doc of snapshot.docs) byId.set(doc.id, doc.data());
  }
  return [...byId.values()];
}

exports.syncSenderTrustBaseline = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Sign in to sync sender trust.");
  }
  const uid = context.auth.uid;
  const db = getFirestore();
  const deliveries = await readSenderDeliveries(db, uid);
  const parcelsSent = deliveries.length;
  const successfulDeliveries = deliveries.filter((delivery) => isCompleted(delivery.status)).length;
  const lifetimeSpend = deliveries.reduce((total, delivery) => total + deliveryValue(delivery), 0);
  const lifetimeSpendPoints = Math.floor(lifetimeSpend / 100) * 2;
  const baseline = parcelsSent + successfulDeliveries + lifetimeSpendPoints;
  const userRef = db.collection("users").doc(uid);
  const eventRef = db.collection("senderTrustEvents").doc();
  await db.runTransaction(async (transaction) => {
    const userSnap = await transaction.get(userRef);
    const user = userSnap.exists ? userSnap.data() : {};
    const previousPoints = Number(user.senderTrustPoints || user.trustPoints || 0);
    const previousBreakdown = user.senderTrustBreakdown || {};
    const previousDeliveryBaseline =
      Number(previousBreakdown.parcelsSent || 0) +
      Number(previousBreakdown.successfulDeliveries || 0) +
      Number(previousBreakdown.lifetimeSpend || 0);
    const nonDeliveryPoints = Math.max(0, previousPoints - previousDeliveryBaseline);
    const nextPoints = baseline + nonDeliveryPoints;
    if (nextPoints <= previousPoints) return;
    const previousTier = normalizeTier(user.senderTier || user.trustTier, previousPoints);
    const frozen = user.senderTrustFrozen === true;
    const newTier = frozen ? previousTier : tierForPoints(nextPoints);
    const timestamp = FieldValue.serverTimestamp();
    transaction.set(userRef, {
      senderTrustPoints: nextPoints,
      senderTier: newTier,
      senderTrustBreakdown: {
        ...previousBreakdown,
        parcelsSent,
        successfulDeliveries,
        lifetimeSpend: lifetimeSpendPoints,
      },
      senderTrustUpdatedAt: timestamp,
      senderTrustUpdatedBy: "system",
      updatedAt: timestamp,
    }, {merge: true});
    transaction.set(eventRef, {
      userId: uid,
      userName: user.fullName || user.name || "Sender",
      userEmail: user.email || context.auth.token.email || null,
      eventType: "system_baseline_sync",
      pointsChange: nextPoints - previousPoints,
      reason: "System baseline from delivery history",
      source: "system",
      awardedBy: "system",
      previousPoints,
      newPoints: nextPoints,
      previousTier,
      newTier,
      createdAt: timestamp,
    });
  });
  return {ok: true, baseline};
});

exports.adminUpdateSenderTrust = functions.https.onCall(async (data, context) => {
  const db = getFirestore();
  const operator = await requireSenderTrustAdmin(db, context);
  const request = trustActionRequest(data);
  const userRef = db.collection("users").doc(request.senderId);
  const eventRef = db.collection("senderTrustEvents").doc();
  let result = null;
  await db.runTransaction(async (transaction) => {
    const userSnap = await transaction.get(userRef);
    if (!userSnap.exists) {
      throw new functions.https.HttpsError("not-found", "Sender account not found.");
    }
    const user = userSnap.data() || {};
    const previousPoints = Number(user.senderTrustPoints || user.trustPoints || 0);
    const previousTier = normalizeTier(user.senderTier || user.trustTier, previousPoints);
    const previousFrozen = user.senderTrustFrozen === true;
    let nextPoints = previousPoints;
    let nextTier = previousTier;
    let nextFrozen = previousFrozen;
    let pointsChange = 0;
    switch (request.action) {
      case "award":
        pointsChange = request.points;
        nextPoints += request.points;
        nextTier = previousFrozen ? previousTier : tierForPoints(nextPoints);
        break;
      case "deduct":
        pointsChange = -request.points;
        nextPoints = Math.max(0, previousPoints - request.points);
        nextTier = previousFrozen ? previousTier : tierForPoints(nextPoints);
        break;
      case "promote":
      case "demote":
        nextTier = normalizeTier(request.tier, nextPoints);
        break;
      case "freeze":
        nextFrozen = true;
        break;
      case "restore":
        nextFrozen = false;
        nextTier = tierForPoints(nextPoints);
        break;
    }
    const timestamp = FieldValue.serverTimestamp();
    const userPatch = {
      senderTrustPoints: nextPoints,
      senderTier: nextTier,
      senderTrustFrozen: nextFrozen,
      senderTrustUpdatedAt: timestamp,
      senderTrustUpdatedBy: operator.uid,
      senderTrustLastReason: request.reason,
      updatedAt: timestamp,
    };
    const event = {
      senderId: request.senderId,
      userId: request.senderId,
      userName: user.fullName || user.name || "Sender",
      userEmail: user.email || null,
      eventType: `admin_${request.action}`,
      action: request.action,
      pointsChange,
      pointsDelta: pointsChange,
      previousPoints,
      nextPoints,
      newPoints: nextPoints,
      previousTier,
      nextTier,
      newTier: nextTier,
      previousFrozen,
      nextFrozen,
      reason: request.reason,
      source: "admin",
      awardedBy: operator.uid,
      operatorId: operator.uid,
      operatorEmail: operator.email || null,
      operatorRole: operator.role || null,
      createdAt: timestamp,
    };
    transaction.set(userRef, userPatch, {merge: true});
    transaction.set(eventRef, event);
    result = {
      ok: true,
      senderId: request.senderId,
      action: request.action,
      previousPoints,
      nextPoints,
      previousTier,
      nextTier,
      previousFrozen,
      nextFrozen,
      pointsChange,
      eventId: eventRef.id,
    };
  });
  await emitNotification({
    recipientId: request.senderId,
    recipientRole: "sender",
    type: "sender_trust_updated",
    title: "Sender trust updated",
    body: "Your Circum Sender trust profile was updated.",
    data: {
      route: "profile",
      action: request.action,
      eventId: result.eventId,
      nextTier: result.nextTier,
      pointsChange: `${result.pointsChange}`,
    },
  }).catch((error) => {
    console.error("Sender trust notification failed", error);
  });
  return result;
});

module.exports.tierForPoints = tierForPoints;
module.exports.normalizeTier = normalizeTier;
module.exports.rothTopUpPoints = rothTopUpPoints;
module.exports.awardRothTopUpProgression = awardRothTopUpProgression;
module.exports.isSenderEligibleForRothProgression =
  isSenderEligibleForRothProgression;
module.exports.trustActionRequest = trustActionRequest;
module.exports.tokenHasTrustAdminRole = tokenHasTrustAdminRole;
