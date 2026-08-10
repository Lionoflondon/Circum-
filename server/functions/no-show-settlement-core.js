"use strict";

const AMOUNTS = Object.freeze({customerPence: 700, riderPence: 400, platformPence: 300});
const MAX_ATTEMPTS = 5;
const RETRY_DELAYS_MS = Object.freeze([5, 15, 60, 240].map((minutes) => minutes * 60 * 1000));

function text(value) {
  return `${value || ""}`.trim();
}

function authorityDecision({delivery = {}, paymentSession = {}, paymentIntent = {}} = {}) {
  const senderId = text(delivery.senderId || delivery.userId);
  const sessionId = text(delivery.paymentSessionId);
  const intentId = text(delivery.stripePaymentIntentId);
  const intentMetadata = paymentIntent.metadata || {};
  const paymentStatus = text(delivery.paymentStatus).toLowerCase();
  const paidAmountPence = Math.round(Number(delivery.paidAmount || 0) * 100);
  const sessionLinked = sessionId && paymentSession.userId === senderId;
  if (!senderId || !sessionId || !sessionLinked) return {allowed: false, reason: "missing_payment_authority"};
  if (!["paid", "succeeded", "success", "captured"].includes(paymentStatus) || paidAmountPence < AMOUNTS.customerPence) {
    return {allowed: false, reason: "paid_amount_insufficient"};
  }
  if (intentId) {
    const linked = text(paymentSession.stripePaymentIntentId) === intentId &&
      text(intentMetadata.paymentSessionId) === sessionId &&
      text(intentMetadata.userId) === senderId;
    if (!linked || text(paymentIntent.status) !== "succeeded") {
      return {allowed: false, reason: "payment_authority_mismatch"};
    }
  } else if (Number(delivery.remainingAmount || 0) > 0 || Number(delivery.rothAppliedAmount || 0) < 7) {
    return {allowed: false, reason: "payment_authority_mismatch"};
  }
  return {allowed: true, paymentIntentId: intentId || null, paymentReference: intentId || sessionId, sessionId, paidAmountPence};
}

function pendingFinancial(deliveryId, riderId) {
  return {
    settlementId: `no_show_${deliveryId}`,
    idempotencyKey: `no_show_settlement_${deliveryId}`,
    deliveryId,
    riderId,
    state: "SETTLEMENT_PENDING",
    settlementStatus: "pending_collection",
    customerCharge: 7,
    riderCompensation: 4,
    platformAmount: 3,
    customerCollected: 0,
    riderCredited: 0,
    platformRealized: 0,
    additionalCustomerCharge: 0,
    attemptCount: 0,
  };
}

function retryDecision(attemptCount, now = Date.now()) {
  const attempts = Math.max(1, Number(attemptCount) || 1);
  if (attempts >= MAX_ATTEMPTS) return {exhausted: true, nextAttemptAt: null};
  const delay = RETRY_DELAYS_MS[Math.min(attempts - 1, RETRY_DELAYS_MS.length - 1)];
  return {exhausted: false, nextAttemptAt: new Date(now + delay)};
}

module.exports = {AMOUNTS, MAX_ATTEMPTS, RETRY_DELAYS_MS, authorityDecision, pendingFinancial, retryDecision};
