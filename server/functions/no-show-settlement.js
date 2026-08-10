"use strict";

/* eslint-disable max-len, require-jsdoc */
const {FieldValue} = require("firebase-admin/firestore");
const functions = require("firebase-functions/v1");
const {getFirestore} = require("firebase-admin/firestore");
const {requireAdmin} = require("./admin-auth");
const core = require("./no-show-settlement-core");

function text(value) {
  return `${value || ""}`.trim();
}

async function markFailure(db, deliveryId, reason, details = {}) {
  const settlementRef = db.collection("noShowSettlements").doc(deliveryId);
  const incidentRef = db.collection("operationsIncidents").doc(`no_show_settlement_${deliveryId}`);
  const result = await db.runTransaction(async (transaction) => {
    const current = await transaction.get(settlementRef);
    if (current.exists && (current.data() || {}).state === "SETTLED") {
      return {success: true, state: "SETTLED", duplicate: true};
    }
    const attemptCount = Number(current.exists && (current.data() || {}).attemptCount || 0) + 1;
    const retry = core.retryDecision(attemptCount);
    transaction.set(settlementRef, {
      state: retry.exhausted ? "REVIEW_REQUIRED" : "SETTLEMENT_PENDING",
      settlementStatus: retry.exhausted ? "retry_exhausted" : "pending_collection",
      failureReason: reason,
      lastAttemptStatus: "failed",
      attemptCount,
      nextAttemptAt: retry.nextAttemptAt,
      customerCollected: 0,
      riderCredited: 0,
      platformRealized: 0,
      ...details,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    transaction.set(incidentRef, {
      incidentId: incidentRef.id,
      incidentType: "no_show_collection_failed",
      severity: "red",
      status: "open",
      deliveryId,
      failureReason: reason,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    return {success: false, state: retry.exhausted ? "REVIEW_REQUIRED" : "SETTLEMENT_PENDING", reason, attemptCount};
  });
  return result;
}

async function settleCollected(db, deliveryId, paymentAuthority) {
  return db.runTransaction(async (transaction) => {
    const deliveryRef = db.collection("deliveryRequests").doc(deliveryId);
    const settlementRef = db.collection("noShowSettlements").doc(deliveryId);
    const [deliverySnap, settlementSnap] = await Promise.all([
      transaction.get(deliveryRef), transaction.get(settlementRef),
    ]);
    if (!deliverySnap.exists || !settlementSnap.exists) throw new Error("No-show settlement authority is missing.");
    const settlement = settlementSnap.data() || {};
    if (settlement.state === "SETTLED") return {success: true, state: "SETTLED", duplicate: true};
    const delivery = deliverySnap.data() || {};
    const riderId = text(delivery.riderId || delivery.assignedRiderId);
    if (!riderId || riderId !== text(settlement.riderId)) throw new Error("Assigned Rider authority changed.");
    const earningRef = db.collection("riderEarningTransactions").doc(`no_show_${deliveryId}`);
    const platformRef = db.collection("platformSettlementTransactions").doc(`no_show_${deliveryId}`);
    const earningSnap = await transaction.get(earningRef);
    const platformSnap = await transaction.get(platformRef);
    if (!earningSnap.exists) {
      transaction.create(earningRef, {
        transactionId: earningRef.id,
        idempotencyKey: `no_show_settlement_${deliveryId}`,
        deliveryId,
        riderId,
        type: "no_show_fee",
        amount: 4,
        status: "completed",
        source: "no_show_deduction_from_paid_delivery",
        createdAt: FieldValue.serverTimestamp(),
      });
      transaction.set(db.collection("riderEarnings").doc(riderId), {
        availableBalance: FieldValue.increment(4),
        noShowFeesTotal: FieldValue.increment(4),
        waitingNoShowTotal: FieldValue.increment(4),
        lifetimeEarnings: FieldValue.increment(4),
        totalAmountEarned: FieldValue.increment(4),
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    }
    if (!platformSnap.exists) {
      transaction.create(platformRef, {
        transactionId: platformRef.id,
        idempotencyKey: `no_show_settlement_${deliveryId}`,
        deliveryId,
        type: "no_show_platform_retained",
        amount: 3,
        currency: "GBP",
        status: "realized",
        paymentReference: paymentAuthority.paymentReference,
        stripePaymentIntentId: paymentAuthority.paymentIntentId || null,
        createdAt: FieldValue.serverTimestamp(),
      });
    }
    const settled = {
      state: "SETTLED",
      settlementStatus: "settled",
      customerCollected: 7,
      riderCredited: 4,
      platformRealized: 3,
      additionalCustomerCharge: 0,
      deductedFromPaidAmount: 7,
      paymentReference: paymentAuthority.paymentReference,
      stripePaymentIntentId: paymentAuthority.paymentIntentId || null,
      settledAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    };
    const publicSettlement = {
      state: settled.state,
      settlementStatus: settled.settlementStatus,
      customerCollected: settled.customerCollected,
      riderCredited: settled.riderCredited,
      platformRealized: settled.platformRealized,
      additionalCustomerCharge: settled.additionalCustomerCharge,
      deductedFromPaidAmount: settled.deductedFromPaidAmount,
      settledAt: settled.settledAt,
      updatedAt: settled.updatedAt,
    };
    transaction.set(settlementRef, settled, {merge: true});
    transaction.set(deliveryRef, {
      noShowFinancial: {...(delivery.noShowFinancial || {}), ...publicSettlement},
    }, {merge: true});
    transaction.set(db.collection("operationsIncidents").doc(`no_show_settlement_${deliveryId}`), {
      status: "resolved",
      resolution: "deducted_from_paid_amount_rider_and_platform_settled",
      resolvedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    transaction.set(deliveryRef.collection("timeline").doc(`no_show_settled_${deliveryId}`), {
      eventId: `no_show_settled_${deliveryId}`,
      eventType: "NoShowSettlementApplied",
      deliveryId,
      immutable: true,
      customerCollected: 7,
      riderCredited: 4,
      platformRealized: 3,
      timestamp: FieldValue.serverTimestamp(),
    });
    return {success: true, state: "SETTLED"};
  });
}

async function processNoShowSettlement({db, stripe, deliveryId}) {
  const [deliverySnap, settlementSnap] = await Promise.all([
    db.collection("deliveryRequests").doc(deliveryId).get(),
    db.collection("noShowSettlements").doc(deliveryId).get(),
  ]);
  if (!deliverySnap.exists || !settlementSnap.exists) return markFailure(db, deliveryId, "settlement_authority_missing");
  const delivery = deliverySnap.data() || {};
  if ((settlementSnap.data() || {}).state === "SETTLED") return {success: true, state: "SETTLED", duplicate: true};
  const sessionId = text(delivery.paymentSessionId);
  const sessionSnap = sessionId ? await db.collection("senderPaymentSessions").doc(sessionId).get() : null;
  let originalIntent = {};
  if (delivery.stripePaymentIntentId) {
    try {
      originalIntent = await stripe.paymentIntents.retrieve(delivery.stripePaymentIntentId);
    } catch (error) {
      return markFailure(db, deliveryId, "original_payment_unavailable", {providerCode: text(error && error.code)});
    }
  }
  const authority = core.authorityDecision({
    delivery,
    paymentSession: sessionSnap && sessionSnap.exists ? sessionSnap.data() || {} : {},
    paymentIntent: originalIntent || {},
  });
  if (!authority.allowed) return markFailure(db, deliveryId, authority.reason);
  return settleCollected(db, deliveryId, authority);
}

async function processPendingNoShowSettlements({db = getFirestore(), stripe, limit = 25} = {}) {
  const snapshot = await db.collection("noShowSettlements")
      .where("state", "==", "SETTLEMENT_PENDING")
      .where("nextAttemptAt", "<=", new Date())
      .orderBy("nextAttemptAt", "asc")
      .limit(Math.min(Math.max(1, limit), 50)).get();
  const results = [];
  for (const doc of snapshot.docs) {
    results.push({deliveryId: doc.id, ...(await processNoShowSettlement({db, stripe, deliveryId: doc.id}))});
  }
  return {processed: results.length, results};
}

function scheduledNoShowSettlementRetries(stripe) {
  return functions.pubsub.schedule("every 5 minutes").timeZone("Europe/London")
      .onRun(() => processPendingNoShowSettlements({stripe}));
}

function adminRetryNoShowSettlement(stripe) {
  return functions.runWith({enforceAppCheck: true}).https.onCall(async (data, context) => {
    const actorUid = requireAdmin(context, "Finance or Operations Admin access is required.");
    const deliveryId = text(data && data.deliveryId);
    const reason = text(data && data.reason);
    if (!deliveryId || reason.length < 8) {
      throw new functions.https.HttpsError("invalid-argument", "Delivery and a meaningful retry reason are required.");
    }
    const db = getFirestore();
    await db.collection("adminAuditLogs").doc(`no_show_retry_${deliveryId}_${Date.now()}`).set({
      action: "no_show_settlement_retry_requested",
      deliveryId,
      reason: reason.slice(0, 500),
      actorUid,
      createdAt: FieldValue.serverTimestamp(),
    });
    return processNoShowSettlement({db, stripe, deliveryId});
  });
}

module.exports = {processNoShowSettlement, processPendingNoShowSettlements, scheduledNoShowSettlementRetries, adminRetryNoShowSettlement, settleCollected};
