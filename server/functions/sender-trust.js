/* eslint-disable max-len, require-jsdoc */
"use strict";

const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");

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
    if (baseline <= previousPoints) return;
    const previousTier = normalizeTier(user.senderTier || user.trustTier, previousPoints);
    const frozen = user.senderTrustFrozen === true;
    const newTier = frozen ? previousTier : tierForPoints(baseline);
    const timestamp = FieldValue.serverTimestamp();
    transaction.set(userRef, {
      senderTrustPoints: baseline,
      senderTier: newTier,
      senderTrustBreakdown: {
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
      pointsChange: baseline - previousPoints,
      reason: "System baseline from delivery history",
      source: "system",
      awardedBy: "system",
      previousPoints,
      newPoints: baseline,
      previousTier,
      newTier,
      createdAt: timestamp,
    });
  });
  return {ok: true, baseline};
});

module.exports.tierForPoints = tierForPoints;
module.exports.normalizeTier = normalizeTier;
