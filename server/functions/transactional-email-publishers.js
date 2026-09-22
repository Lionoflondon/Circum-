/* eslint-disable max-len, require-jsdoc */
"use strict";

const {normalizeEmail} = require("./email-queue");

const CREATED = "google.cloud.firestore.document.v1.created";
const UPDATED = "google.cloud.firestore.document.v1.updated";
const text = (value) => `${value || ""}`.trim();
const lower = (value) => text(value).toLowerCase();

function documentPath(name = "") {
  return String(name).split("/documents/")[1] || String(name).replace(/^documents\//, "");
}

function asId(path, collection) {
  const match = new RegExp(`^${collection}/([^/]+)$`).exec(path);
  return match && match[1];
}

function createOnly(db, id, payload) {
  if (!id || !payload || !payload.to) return Promise.resolve({status: "skipped", reason: "recipient_missing"});
  return db.collection("emailQueue").doc(id).create({
    ...payload,
    notificationId: id,
    status: "queued",
    attempts: 0,
    maxAttempts: 5,
    provider: "resend",
    createdAt: new Date(),
    updatedAt: new Date(),
  }).then(() => ({status: "queued", id})).catch((error) => {
    if (error.code === 6 || error.code === "already-exists" || /already exists/i.test(text(error.message))) {
      return {status: "duplicate", id};
    }
    throw error;
  });
}

function record({to, subject, body, eventType, collection, sourceId, required, recipientField, extra = {}}) {
  const recipient = normalizeEmail(to);
  if (!recipient) return null;
  return {
    to: recipient,
    subject,
    text: body,
    eventType,
    sourceCollection: collection,
    sourceDocumentId: sourceId,
    sourceRequiredStatus: required,
    sourceRecipientField: recipientField,
    ...extra,
  };
}

function emailId(...parts) {
  return parts.map((part) => text(part).replace(/[^A-Za-z0-9_-]/g, "_")).join("_").slice(0, 200);
}

function isOrdinaryDelivery(data = {}) {
  const kind = lower(data.sourceModule || data.serviceType || data.type);
  return data.businessMode !== true && data.isBusiness !== true &&
    !kind.includes("gift") && !kind.includes("health") && kind !== "business";
}

function paymentConfirmed(data = {}) {
  return ["paid", "succeeded", "success", "roth_paid", "stripe_paid"]
      .includes(lower(data.paymentStatus || data.paymentState));
}

function finalDelivery(data = {}) {
  return ["delivered", "completed"].includes(lower(data.status || data.deliveryStatus)) &&
    (!data.settlementStatus || lower(data.settlementStatus) === "completed");
}

async function publishFromEvent({db, eventType, eventId, decoded}) {
  const path = documentPath(decoded.documentName);
  const before = decoded.before || {};
  const after = decoded.after || {};

  const deliveryId = asId(path, "deliveryRequests");
  if (deliveryId && eventType === CREATED && isOrdinaryDelivery(after) &&
      paymentConfirmed(after) && ["requested", "created", "pending"].includes(lower(after.status))) {
    const to = after.senderEmail || after.email;
    const payload = record({to, subject: "Your Circum delivery booking is confirmed",
      body: `Your paid Circum delivery booking is confirmed. Booking reference: ${deliveryId}. Open Circum to view your delivery.`,
      eventType: "delivery_booking_paid", collection: "deliveryRequests", sourceId: deliveryId,
      required: "paid", recipientField: after.senderEmail ? "senderEmail" : "email", extra: {recipientId: text(after.senderId)}});
    return createOnly(db, emailId("delivery_booking_paid", deliveryId), payload);
  }
  if (deliveryId && eventType === UPDATED && isOrdinaryDelivery(after) && !finalDelivery(before) && finalDelivery(after)) {
    const to = after.senderEmail || after.email;
    const payload = record({to, subject: "Your Circum delivery is complete",
      body: `Your Circum delivery has been completed. Booking reference: ${deliveryId}. Open Circum to view the delivery details.`,
      eventType: "delivery_completed", collection: "deliveryRequests", sourceId: deliveryId,
      required: lower(after.status || after.deliveryStatus), recipientField: after.senderEmail ? "senderEmail" : "email", extra: {recipientId: text(after.senderId)}});
    return createOnly(db, emailId("delivery_completed", deliveryId), payload);
  }

  const settlementId = asId(path, "deliveryCancellationSettlements");
  if (settlementId && eventType === UPDATED && lower(after.status) === "settled" && lower(before.status) !== "settled") {
    const deliverySnap = await db.collection("deliveryRequests").doc(settlementId).get();
    if (!deliverySnap.exists) return {status: "skipped", reason: "delivery_missing"};
    const delivery = deliverySnap.data() || {};
    if (lower(delivery.cancellationSettlementStatus) !== "settled") return {status: "skipped", reason: "settlement_not_authoritative"};
    const to = delivery.senderEmail || delivery.email;
    const payload = record({to, subject: "Your Circum delivery cancellation is confirmed",
      body: `The cancellation for your Circum delivery has been settled. Booking reference: ${settlementId}. Open Circum to view the account details.`,
      eventType: "delivery_cancellation_settled", collection: "deliveryRequests", sourceId: settlementId,
      required: "settled", recipientField: delivery.senderEmail ? "senderEmail" : "email", extra: {recipientId: text(delivery.senderId)}});
    return createOnly(db, emailId("delivery_cancellation_settled", settlementId), payload);
  }

  const invoiceId = asId(path, "businessInvoices");
  if (invoiceId && eventType === UPDATED && !["paid", "paid_manually"].includes(lower(before.status)) &&
      ["paid", "paid_manually"].includes(lower(after.status)) && Number(after.balanceDue || 0) <= 0) {
    const to = after.billingEmail;
    const ref = text(after.invoiceNumber || invoiceId);
    const payload = record({to, subject: "Your Circum Business invoice is paid",
      body: `Payment for Circum Business invoice ${ref} is complete. Sign in to Circum Business to view the invoice.`,
      eventType: "business_invoice_paid", collection: "businessInvoices", sourceId: invoiceId,
      required: lower(after.status), recipientField: "billingEmail", extra: {businessId: text(after.businessId), invoiceId}});
    return createOnly(db, emailId("business_invoice_paid", invoiceId), payload);
  }

  const walletTransactionId = asId(path, "walletTransactions");
  if (walletTransactionId && eventType === CREATED && lower(after.status) === "completed" &&
      lower(after.walletType || "sender") === "sender" && after.userId && after.userEmail) {
    const payload = record({to: after.userEmail, subject: "Your Circum Roth activity is complete",
      body: `A Roth account activity has been completed. Reference: ${walletTransactionId}. Open Circum to review your Roth activity.`,
      eventType: "roth_movement_completed", collection: "walletTransactions", sourceId: walletTransactionId,
      required: "completed", recipientField: "userEmail", extra: {recipientId: text(after.uid || after.userId)}});
    return createOnly(db, emailId("roth_movement_completed", walletTransactionId), payload);
  }

  const referralId = asId(path, "referrals");
  if (referralId && eventType === UPDATED && lower(after.status) === "roth_awarded" &&
      lower(before.status) !== "roth_awarded") {
    const [inviter, referred] = await Promise.all([
      db.collection("walletTransactions").doc(`referral_reward_${referralId}_referrer`).get(),
      db.collection("walletTransactions").doc(`referral_reward_${referralId}_referred`).get(),
    ]);
    if (!inviter.exists || !referred.exists || lower(inviter.data().status) !== "completed" || lower(referred.data().status) !== "completed") {
      return {status: "skipped", reason: "referral_ledger_not_final"};
    }
    const common = `Your Circum referral reward has been finalized in Roth. Open Circum to review your account.`;
    const inviterEmail = record({to: after.referrerEmail, subject: "Your Circum referral reward is complete", body: common,
      eventType: "referral_award_finalized", collection: "referrals", sourceId: referralId, required: "roth_awarded",
      recipientField: "referrerEmail", extra: {recipientId: text(after.referrerUserId)}});
    const referredEmail = record({to: after.referredEmail, subject: "Your Circum referral reward is complete", body: common,
      eventType: "referral_award_finalized", collection: "referrals", sourceId: referralId, required: "roth_awarded",
      recipientField: "referredEmail", extra: {recipientId: text(after.referredUserId || referralId)}});
    const results = await Promise.all([
      createOnly(db, emailId("referral_award", referralId, "referrer"), inviterEmail),
      createOnly(db, emailId("referral_award", referralId, "referred"), referredEmail),
    ]);
    return {status: "published", results};
  }

  const riderId = asId(path, "riderProfiles");
  const decision = lower(after.approvalStatus);
  if (riderId && eventType === UPDATED && decision !== lower(before.approvalStatus) &&
      ["approved", "rejected", "more_information_requested"].includes(decision) &&
      (after.adminOperationUpdatedAt || after.riderAuthorityUpdatedAt)) {
    const label = decision === "more_information_requested" ? "needs more information" : decision;
    const decisionKey = after.adminOperationUpdatedAt || after.riderAuthorityUpdatedAt;
    const payload = record({to: after.email, subject: "Circum Rider application update",
      body: `Your Circum Rider application ${label}. Open the Rider app to view the next steps.`,
      eventType: "rider_application_decision", collection: "riderProfiles", sourceId: riderId,
      required: decision, recipientField: "email", extra: {recipientId: riderId, decisionKey: String(decisionKey.seconds || decisionKey._seconds || decisionKey)}});
    return createOnly(db, emailId("rider_application", riderId, decision, decisionKey.seconds || decisionKey._seconds || decisionKey), payload);
  }

  const pickupId = asId(path, "prescriptionPickups");
  const pickupStatus = lower(after.status);
  const healthEvents = {
    assigned: ["rider_assigned", "A verified rider has been assigned."],
    collected: ["prescription_collected", "Your prescription has been collected securely."],
    out_for_delivery: ["en_route_to_customer", "Your Health+ delivery is on its way."],
    delivered: ["delivered", "Your Health+ delivery has been completed."],
    rescheduled: ["rescheduled", "Your Health+ collection has been rescheduled."],
    escalated: ["escalated", "Your Health+ delivery has been escalated for review."],
  };
  if (pickupId && eventType === UPDATED && before.status !== after.status && healthEvents[pickupStatus]) {
    const [type, body] = healthEvents[pickupStatus];
    const to = after.email;
    const payload = record({to, subject: "Health+ update", body,
      eventType: `health_plus_${type}`, collection: "prescriptionPickups", sourceId: pickupId,
      required: pickupStatus, recipientField: "email", extra: {pickupId, recipientId: text(after.userId || after.senderId)}});
    return createOnly(db, emailId("health", pickupId, type), payload);
  }

  const giftId = asId(path, "giftRequests");
  if (giftId && eventType === UPDATED && lower(after.status || after.giftStatus) === "delivered" &&
      lower(before.status || before.giftStatus) !== "delivered") {
    const {queueGiftDeliveryEmail} = require("./gift-email-notifications");
    const result = await queueGiftDeliveryEmail({giftId, gift: after, db});
    return result ? {status: "published", id: result} : {status: "skipped", reason: "gift_recipient_missing"};
  }

  return {status: "ignored", eventId};
}

module.exports = {CREATED, UPDATED, documentPath, publishFromEvent, paymentConfirmed, finalDelivery, isOrdinaryDelivery};
