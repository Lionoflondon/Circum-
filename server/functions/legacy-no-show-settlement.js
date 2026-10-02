"use strict";

/* eslint-disable max-len, require-jsdoc */
const {FieldValue} = require("firebase-admin/firestore");
const {getFirestore} = require("firebase-admin/firestore");
const core = require("./legacy-no-show-policy");

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

async function settleCollected(db, deliveryId, paymentAuthority, paymentIntent = {}) {
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
    const sessionId = text(delivery.paymentSessionId);
    const sessionSnap = sessionId ? await transaction.get(db.collection("senderPaymentSessions").doc(sessionId)) : null;
    const freshAuthority = core.authorityDecision({delivery, paymentSession: sessionSnap?.data() || {}, paymentIntent});
    if (!freshAuthority.allowed || freshAuthority.paymentReference !== paymentAuthority.paymentReference ||
        delivery.status !== "sender_no_show_pickup" || delivery.refundPending === true ||
        ["refunded", "partially_refunded"].includes(text(delivery.paymentStatus)) || Number(delivery.refundedAmount || 0) > 0) {
      throw new Error("no_show_authority_changed_or_refund_requires_review");
    }
    const riderId = text(delivery.riderId || delivery.assignedRiderId);
    if (!riderId || riderId !== text(settlement.riderId)) throw new Error("Assigned Rider authority changed.");
    const earningRef = db.collection("riderEarningTransactions").doc(`no_show_${deliveryId}`);
    const platformRef = db.collection("platformSettlementTransactions").doc(`no_show_${deliveryId}`);
    const [cancellationRows, earningRows] = await Promise.all([
      transaction.get(db.collection("deliveryCancellationSettlements").where("deliveryId", "==", deliveryId).limit(1)),
      transaction.get(db.collection("riderEarningTransactions").where("deliveryId", "==", deliveryId).limit(50)),
    ]);
    if (!cancellationRows.empty || earningRows.docs.some((doc) => doc.id !== earningRef.id)) throw new Error("no_show_other_settlement_authority_requires_review");
    if (!delivery.stripePaymentIntentId) {
      const debitId = sessionSnap.data()?.rothDebitTransactionId;
      if (!debitId || sessionSnap.data()?.rothDebitStatus !== "completed") throw new Error("no_show_roth_debit_authority_missing");
      const debit = await transaction.get(db.collection("walletTransactions").doc(debitId));
      const row = debit.data() || {};
      if (!debit.exists || row.status !== "completed" || row.referenceId !== sessionId || row.relatedEntityId !== deliveryId || row.uid !== (delivery.senderId || delivery.userId) || row.balanceType !== "rothCredit" || Number(row.amount) !== -Number(sessionSnap.data()?.rothAppliedAmount) || Number(row.amount) > -7) throw new Error("no_show_roth_debit_authority_mismatch");
    }
    const earningSnap = await transaction.get(earningRef);
    const platformSnap = await transaction.get(platformRef);
    if (earningSnap.exists && (earningSnap.data().riderId !== riderId || Number(earningSnap.data().amount) !== 4 || earningSnap.data().type !== "no_show_fee")) throw new Error("no_show_earning_conflict");
    if (platformSnap.exists && (Number(platformSnap.data().amount) !== 3 || platformSnap.data().paymentReference !== paymentAuthority.paymentReference)) throw new Error("no_show_platform_conflict");
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
  return settleCollected(db, deliveryId, authority, originalIntent);
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

module.exports = {processNoShowSettlement, processPendingNoShowSettlements, settleCollected};
