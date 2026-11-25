/* eslint-disable max-len, require-jsdoc */
"use strict";
const {HttpsError} = require("firebase-functions/v1/https");
const {verifiedAdjustmentPayment} = require("./delivery-adjustment-core");

function amountPence(row) {
  const amount = Math.round(Number(row.additionalAmount) * 100);
  if (!Number.isSafeInteger(amount) || amount <= 0) throw new HttpsError("failed-precondition", "No valid additional payment is due.");
  return amount;
}
function approved(row, senderId) {
  if (!row || row.senderId !== senderId) throw new HttpsError("permission-denied", "Only the sender can pay this adjustment.");
  if (row.status !== "awaiting_sender_payment" || row.adminDecision !== "approve") throw new HttpsError("failed-precondition", "This adjustment is not approved for payment.");
}
async function createPayment({db, stripe, adjustmentId, senderId, hosted = false}) {
  if (typeof adjustmentId !== "string" || !/^[A-Za-z0-9_-]{1,150}$/.test(adjustmentId)) throw new HttpsError("invalid-argument", "Adjustment reference required.");
  const ref = db.collection("deliveryAdjustments").doc(adjustmentId);
  const surface = hosted ? "hosted" : "native";
  const row = await db.runTransaction(async (tx) => {
    const snapshot = await tx.get(ref);
    const row = snapshot.exists ? snapshot.data() : null;
    if (row?.status === "paid" && row.senderId === senderId) return row;
    approved(row, senderId);
    const amount = amountPence(row);
    const existingSurface = row.paymentCheckoutSurface || (row.paymentIntentId ? "native" : null);
    if (existingSurface && existingSurface !== surface) throw new HttpsError("failed-precondition", "Resume the existing payment on its original platform.");
    if (row.paymentQuotePence && row.paymentQuotePence !== amount) throw new HttpsError("failed-precondition", "Payment quote changed; reconciliation required.");
    tx.update(ref, {paymentCheckoutSurface: surface, paymentQuotePence: amount, updatedAt: Date.now()});
    return {...row, paymentQuotePence: amount};
  });
  if (row.status === "paid") return {paid: true, success: true};
  const amount = row.paymentQuotePence;
  const metadata = {type: "delivery_adjustment", feature: "delivery_adjustment", adjustmentId, bookingId: row.bookingId, senderId};
  if (hosted) {
    const session = row.paymentCheckoutSessionId ? await stripe.checkout.sessions.retrieve(row.paymentCheckoutSessionId) :
      await stripe.checkout.sessions.create({mode: "payment", payment_method_types: ["card"],
        line_items: [{price_data: {currency: "gbp", unit_amount: amount, product_data: {name: "Circum delivery adjustment"}}, quantity: 1}],
        metadata, payment_intent_data: {metadata},
        success_url: "https://circumuk.com/send/?payment_return=adjustment",
        cancel_url: "https://circumuk.com/send/?payment_return=cancelled",
      }, {idempotencyKey: `delivery-adjustment-checkout-${adjustmentId}`});
    if (session.status === "complete" && session.payment_status === "paid") {
      await finalizeCheckout({db, stripe, session, senderId});
      return {paid: true, success: true};
    }
    if (session.status !== "open" || session.payment_status === "paid" || !/^https:\/\/checkout\.stripe\.com\//.test(session.url || "")) throw new HttpsError("failed-precondition", "This checkout is closed; reconcile the existing payment before starting another.");
    await ref.update({paymentCheckoutSessionId: session.id, updatedAt: Date.now()});
    return {checkoutUrl: session.url, sessionId: session.id, amount};
  }
  delete metadata.type; // Preserve the original native idempotency payload.
  const intent = row.paymentIntentId ? await stripe.paymentIntents.retrieve(row.paymentIntentId) :
    await stripe.paymentIntents.create({amount, currency: "gbp", payment_method_types: ["card"], metadata}, {idempotencyKey: `delivery-adjustment-${adjustmentId}`});
  if (intent.amount !== amount || intent.currency !== "gbp" || intent.metadata?.adjustmentId !== adjustmentId || intent.metadata?.senderId !== senderId || intent.metadata?.bookingId !== row.bookingId) throw new HttpsError("failed-precondition", "Existing payment does not match this adjustment.");
  if (intent.status === "canceled") throw new HttpsError("failed-precondition", "This payment is closed; reconcile it before starting another.");
  await ref.update({paymentIntentId: intent.id, paymentStatus: intent.status, updatedAt: Date.now()});
  return {clientSecret: intent.client_secret, paymentIntentId: intent.id, amount};
}
async function settle({db, adjustmentId, intent, senderId, sessionId = null}) {
  const ref = db.collection("deliveryAdjustments").doc(adjustmentId);
  return db.runTransaction(async (tx) => {
    const snapshot = await tx.get(ref);
    const row = snapshot.exists ? snapshot.data() : null;
    if (!row || (senderId && row.senderId !== senderId)) throw new HttpsError("permission-denied", "Adjustment payment ownership mismatch.");
    if ((sessionId && row.paymentCheckoutSessionId !== sessionId) || (!sessionId && row.paymentCheckoutSurface === "hosted") || (!sessionId && row.paymentIntentId !== intent.id)) throw new HttpsError("failed-precondition", "Adjustment payment reference mismatch.");
    if (!verifiedAdjustmentPayment(intent, row, adjustmentId) || (row.paymentQuotePence && row.paymentQuotePence !== intent.amount)) throw new HttpsError("failed-precondition", "Payment does not match the approved adjustment.");
    if (row.status === "paid") return {success: true, duplicate: true};
    approved(row, row.senderId);
    const bookingRef = db.collection("deliveryRequests").doc(row.bookingId);
    const booking = await tx.get(bookingRef);
    if (!booking.exists || booking.data().status !== "awaiting_sender_adjustment") throw new HttpsError("failed-precondition", "Booking no longer awaits this adjustment.");
    tx.update(ref, {paymentIntentId: intent.id, status: "paid", paymentStatus: "succeeded", senderDecision: "approved_and_paid", paidAt: Date.now(), updatedAt: Date.now()});
    tx.update(bookingRef, {status: booking.data().preAdjustmentStatus || "accepted", price: row.revisedQuote, paidAmount: row.revisedQuote, adjustmentResolvedBy: "sender_payment", "loadDiscrepancy.senderDecision": "approved_and_paid", riderAdjustment: Number(row.additionalAmount), updatedAt: Date.now()});
    return {success: true, duplicate: false, riderId: row.riderId};
  });
}
async function finalizeCheckout({db, stripe, session, senderId}) {
  const canonical = await stripe.checkout.sessions.retrieve(session.id, {expand: ["payment_intent"]});
  const metadata = canonical.metadata || {};
  const intent = canonical.payment_intent;
  if (canonical.status !== "complete" || canonical.payment_status !== "paid" || canonical.currency !== "gbp" || metadata.type !== "delivery_adjustment" || !intent || typeof intent !== "object" || canonical.amount_total !== intent.amount || (senderId && metadata.senderId !== senderId)) throw new HttpsError("failed-precondition", "The additional payment has not been confirmed.");
  return settle({db, adjustmentId: metadata.adjustmentId, intent, senderId: senderId || metadata.senderId, sessionId: canonical.id});
}
async function finalizePayment({db, stripe, adjustmentId, senderId}) {
  const snapshot = await db.collection("deliveryAdjustments").doc(adjustmentId).get();
  const row = snapshot.exists ? snapshot.data() : null;
  if (!row || row.senderId !== senderId) throw new HttpsError("permission-denied", "Only the sender can finalize this adjustment.");
  if (row.paymentCheckoutSessionId) return finalizeCheckout({db, stripe, session: {id: row.paymentCheckoutSessionId}, senderId});
  if (!row.paymentIntentId) throw new HttpsError("failed-precondition", "Adjustment payment was not created.");
  const intent = await stripe.paymentIntents.retrieve(row.paymentIntentId);
  return settle({db, adjustmentId, intent, senderId});
}
async function handlePaymentIntent({db, stripe, intent, eventType}) {
  const metadata = intent.metadata || {};
  if (metadata.feature !== "delivery_adjustment") return {handled: false};
  const snapshot = await db.collection("deliveryAdjustments").doc(metadata.adjustmentId).get();
  const row = snapshot.exists ? snapshot.data() : null;
  if (!row || row.senderId !== metadata.senderId || row.bookingId !== metadata.bookingId) throw new HttpsError("failed-precondition", "Unbound adjustment intent.");
  if (row.paymentCheckoutSessionId) {
    const session = await stripe.checkout.sessions.retrieve(row.paymentCheckoutSessionId);
    const boundId = typeof session.payment_intent === "string" ? session.payment_intent : session.payment_intent?.id;
    if (boundId !== intent.id) throw new HttpsError("failed-precondition", "Adjustment intent does not match checkout.");
  } else if (row.paymentIntentId !== intent.id) throw new HttpsError("failed-precondition", "Adjustment intent reference mismatch.");
  if (eventType === "payment_intent.succeeded") await finalizePayment({db, stripe, adjustmentId: metadata.adjustmentId, senderId: metadata.senderId});
  return {handled: true};
}
module.exports = {amountPence, createPayment, finalizePayment, finalizeCheckout, settle, handlePaymentIntent};
