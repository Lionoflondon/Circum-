/* eslint-disable max-len, require-jsdoc */
"use strict";

const {FieldValue} = require("firebase-admin/firestore");

function refundPatch(charge) {
  const refundedAmount = Number(charge.amount_refunded || 0);
  const originalAmount = Number(charge.amount || 0);
  const fullyRefunded = charge.refunded === true || originalAmount > 0 && refundedAmount >= originalAmount;
  const latest = charge.refunds && charge.refunds.data && charge.refunds.data[0];
  return {
    refundStatus: fullyRefunded ? "refunded" : refundedAmount > 0 ? "partially_refunded" : "not_refunded",
    refunded: fullyRefunded,
    refundedAmount,
    refundedCurrency: `${charge.currency || ""}`.toUpperCase(),
    refundedAt: latest && latest.created ? new Date(latest.created * 1000) : FieldValue.serverTimestamp(),
    stripeRefundId: latest && latest.id || null,
    refundReviewRequired: false,
    refundReviewStatus: "synced_from_stripe",
    refundUpdatedAt: FieldValue.serverTimestamp(),
  };
}

async function syncChargeRefund({db, event}) {
  const eventRef = db.collection("stripeWebhookEvents").doc(event.id);
  const charge = event.data.object;
  const paymentIntentId = typeof charge.payment_intent === "string" ? charge.payment_intent : charge.payment_intent && charge.payment_intent.id;
  if (!paymentIntentId) return {handled: false, reason: "missing_payment_intent"};
  const directId = charge.metadata && (charge.metadata.deliveryId || charge.metadata.requestId);
  const query = directId ? null : await db.collection("deliveryRequests").where("stripePaymentIntentId", "==", paymentIntentId).limit(2).get();
  const refs = directId ? [db.collection("deliveryRequests").doc(directId)] : query.docs.map((doc) => doc.ref);
  if (!refs.length) return {handled: false, reason: "delivery_not_found", paymentIntentId};
  if (!directId && refs.length > 1) {
    await db.runTransaction(async (transaction) => {
      const seen = await transaction.get(eventRef);
      if (seen.exists) return;
      transaction.create(eventRef, {
        type: event.type,
        paymentIntentId,
        deliveryIds: refs.map((ref) => ref.id),
        reviewRequired: true,
        reason: "multiple_deliveries_for_payment_intent",
        createdAt: FieldValue.serverTimestamp(),
      });
      transaction.set(db.collection("adminAuditLogs").doc(), {
        action: "stripe_refund_requires_review",
        actionType: "stripe_refund_requires_review",
        paymentIntentId,
        deliveryIds: refs.map((ref) => ref.id),
        stripeChargeId: charge.id || null,
        reason: "multiple_deliveries_for_payment_intent",
        createdAt: FieldValue.serverTimestamp(),
      });
    });
    return {handled: false, reason: "multiple_deliveries_for_payment_intent", paymentIntentId, deliveryIds: refs.map((ref) => ref.id), reviewRequired: true};
  }
  const patch = refundPatch(charge);
  await db.runTransaction(async (transaction) => {
    const seen = await transaction.get(eventRef);
    if (seen.exists) return;
    for (const ref of refs) transaction.set(ref, patch, {merge: true});
    transaction.create(eventRef, {type: event.type, paymentIntentId, deliveryIds: refs.map((ref) => ref.id), createdAt: FieldValue.serverTimestamp()});
  });
  return {handled: true, paymentIntentId, deliveryIds: refs.map((ref) => ref.id), refundStatus: patch.refundStatus};
}

module.exports = {refundPatch, syncChargeRefund};
