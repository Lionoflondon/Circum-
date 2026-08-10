/* eslint-disable max-len, require-jsdoc */
"use strict";

const functions = require("firebase-functions/v1");
const {getFirestore} = require("firebase-admin/firestore");

const CUSTOMER_EVENTS = new Map([
  ["DeliveryCreated", "Delivery requested"],
  ["QuoteConfirmed", "Quote confirmed"],
  ["PaymentConfirmed", "Payment confirmed"],
  ["RiderAssigned", "Rider assigned"],
  ["RiderAccepted", "Rider accepted"],
  ["RiderArrivedPickup", "Rider arrived at pickup"],
  ["Collected", "Parcel collected"],
  ["InTransit", "On the way"],
  ["RiderArrivedDropoff", "Rider arrived at the drop-off"],
  ["VerificationStarted", "Delivery verification started"],
  ["EvidenceUploaded", "Proof of delivery recorded"],
  ["Completed", "Delivered"],
  ["Cancelled", "Delivery cancelled"],
  ["Refunded", "Refund processed"],
]);

function text(value, max = 300) {
  return `${value || ""}`.trim().slice(0, max);
}

function millis(value) {
  return value && typeof value.toMillis === "function" ? value.toMillis() : null;
}

function amount(value) {
  const number = Number(value || 0);
  return Number.isFinite(number) ? Math.round(number * 100) / 100 : 0;
}

function address(value, fallback) {
  if (value && typeof value === "object") {
    for (const key of ["formattedAddress", "displayAddress", "addressLine1", "address"]) {
      if (text(value[key])) return text(value[key]);
    }
  }
  return text(fallback) || "Address unavailable";
}

function ownsDelivery(data, uid) {
  return [data.senderId, data.userId, data.customerId, data.createdByUserId, data.ownerUid]
      .some((value) => text(value) === uid);
}

function receipt(data, deliveryId) {
  const pricing = data.pricingBreakdown && typeof data.pricingBreakdown === "object" ? data.pricingBreakdown : {};
  const snapshot = pricing.canonicalQuoteSnapshot && typeof pricing.canonicalQuoteSnapshot === "object" ? pricing.canonicalQuoteSnapshot : {};
  const rawItems = Array.isArray(snapshot.lineItems) ? snapshot.lineItems : (Array.isArray(pricing.lineItems) ? pricing.lineItems : []);
  return {
    reference: text(data.deliveryReference || data.trackingReference || deliveryId, 100),
    dateMillis: millis(data.deliveredAt || data.completedAt || data.createdAt),
    serviceType: text(data.serviceLevel || data.selectedServiceLevel || data.selectedSpeed || snapshot.speed, 60),
    currency: text(data.currency || snapshot.currency || "GBP", 10).toUpperCase(),
    amountPaid: amount(data.paidAmount || pricing.amountDue || snapshot.amountDue || snapshot.total),
    paymentStatus: text(data.paymentStatus || "unavailable", 40).toLowerCase(),
    paymentMethod: text(data.paymentMethod || "unavailable", 40).toLowerCase(),
    rothAppliedAmount: amount(data.rothAppliedAmount),
    externalPaidAmount: amount(data.remainingAmount),
    vatAmount: amount(data.vatAmount || snapshot.vatAmount),
    completionStatus: text(data.deliveryStatus || data.status || "requested", 60).toLowerCase(),
    lineItems: rawItems.slice(0, 30).map((item) => ({label: text(item && item.label, 100), amount: amount(item && item.amount)})).filter((item) => item.label && item.amount !== 0),
  };
}

function customerEvent(doc) {
  const event = doc.data() || {};
  const eventType = text(event.eventType || event.event, 100);
  const label = CUSTOMER_EVENTS.get(eventType);
  if (!label) return null;
  return {eventId: doc.id, eventType, label, timestampMillis: millis(event.timestamp || event.createdAt)};
}

exports.getCustomerDeliveryTrust = functions.runWith({enforceAppCheck: true})
    .region("us-central1").https.onCall(async (data, context) => {
      const uid = context.auth && context.auth.uid;
      if (!uid) throw new functions.https.HttpsError("unauthenticated", "Sign in to view this delivery.");
      const deliveryId = text(data && data.deliveryId, 180);
      if (!deliveryId) throw new functions.https.HttpsError("invalid-argument", "Delivery is required.");
      const db = getFirestore();
      const delivery = await db.collection("deliveryRequests").doc(deliveryId).get();
      if (!delivery.exists || !ownsDelivery(delivery.data() || {}, uid)) throw new functions.https.HttpsError("not-found", "Delivery not found.");
      const record = delivery.data() || {};
      const timeline = await delivery.ref.collection("timeline").orderBy("timestamp", "asc").limit(100).get();
      return {
        deliveryId,
        state: text(record.deliveryStatus || record.status || "requested", 60).toLowerCase(),
        rider: record.assignedRiderId ? {assigned: true, displayName: text(record.riderName || record.assignedRiderName || "CIRCUM Rider", 100)} : {assigned: false},
        etaMinutes: Number.isFinite(Number(record.etaMinutes)) ? Number(record.etaMinutes) : null,
        pickup: address(record.pickupAddressCanonical || record.pickupDetails, record.pickupAddress),
        dropoff: address(record.dropoffAddressCanonical || record.dropoffDetails, record.dropoffAddress),
        evidenceAvailable: record.proofAvailable === true || record.evidenceStatus === "complete" || Boolean(record.completedAt || record.deliveredAt),
        support: {available: true, conversationType: "support", deliveryReference: text(record.deliveryReference || record.trackingReference || deliveryId, 100)},
        timeline: timeline.docs.map(customerEvent).filter(Boolean),
        receipt: receipt(record, deliveryId),
        projectionVersion: "2026-08-customer-trust-v1",
      };
    });

exports._private = {CUSTOMER_EVENTS, customerEvent, ownsDelivery, receipt};
