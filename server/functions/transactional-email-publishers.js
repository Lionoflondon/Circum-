/* eslint-disable max-len, require-jsdoc */
"use strict";

const {normalizeEmail} = require("./email-queue");
const templates = require("./transactional-email-templates");

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

function record({to, template, eventType, collection, sourceId, required, recipientField, senderCategory = "info", extra = {}}) {
  const recipient = normalizeEmail(to);
  if (!recipient || !template) return null;
  return {
    to: recipient,
    subject: template.subject,
    text: template.text,
    html: template.html,
    preheader: template.preheader,
    heading: template.heading,
    ctaLabel: template.ctaLabel,
    ctaUrl: template.ctaUrl,
    templateId: template.templateId,
    eventType,
    sourceCollection: collection,
    sourceDocumentId: sourceId,
    sourceRequiredStatus: required,
    sourceRecipientField: recipientField,
    senderCategory,
    providerTags: template.providerTags,
    ...extra,
  };
}

function emailId(...parts) {
  return parts.map((part) => text(part).replace(/[^A-Za-z0-9_-]/g, "_")).join("_").slice(0, 200);
}

function timestampKey(value) {
  if (value && typeof value === "object" && (value.seconds != null || value._seconds != null)) {
    return `${value.seconds ?? value._seconds}_${value.nanos ?? value._nanoseconds ?? 0}`;
  }
  if (value instanceof Date) return `${value.getTime()}`;
  return text(value);
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
    lower(data.settlementStatus) === "completed";
}

async function publishFromEvent({db, eventType, eventId, decoded}) {
  const path = documentPath(decoded.documentName);
  const before = decoded.before || {};
  const after = decoded.after || {};

  const deliveryId = asId(path, "deliveryRequests");
  if (deliveryId && eventType === CREATED && isOrdinaryDelivery(after) &&
      paymentConfirmed(after) && ["requested", "created", "pending", "scheduled"].includes(lower(after.status))) {
    const to = after.senderEmail || after.email;
    const payload = record({to, template: templates.bookingConfirmed({reference: deliveryId}),
      eventType: "delivery_booking_paid", collection: "deliveryRequests", sourceId: deliveryId,
      required: "paid", recipientField: after.senderEmail ? "senderEmail" : "email", senderCategory: "info",
      extra: {recipientId: text(after.senderId)}});
    if (payload) payload.sourceRequiredFields = {paymentStatus: ["paid", "succeeded", "success", "roth_paid", "stripe_paid"]};
    return createOnly(db, emailId("delivery_booking_paid", deliveryId), payload);
  }
  if (deliveryId && eventType === UPDATED && isOrdinaryDelivery(after) && !finalDelivery(before) && finalDelivery(after)) {
    const to = after.senderEmail || after.email;
    const payload = record({to, template: templates.deliveryCompleted({reference: deliveryId}),
      eventType: "delivery_completed", collection: "deliveryRequests", sourceId: deliveryId,
      required: lower(after.status || after.deliveryStatus), recipientField: after.senderEmail ? "senderEmail" : "email", senderCategory: "info",
      extra: {recipientId: text(after.senderId)}});
    if (payload) payload.sourceRequiredFields = {settlementStatus: "completed"};
    return createOnly(db, emailId("delivery_completed", deliveryId), payload);
  }

  const settlementId = asId(path, "deliveryCancellationSettlements");
  if (settlementId && eventType === UPDATED && lower(after.status) === "settled" && lower(before.status) !== "settled") {
    const deliverySnap = await db.collection("deliveryRequests").doc(settlementId).get();
    if (!deliverySnap.exists) return {status: "skipped", reason: "delivery_missing"};
    const delivery = deliverySnap.data() || {};
    if (lower(delivery.cancellationSettlementStatus) !== "settled") return {status: "skipped", reason: "settlement_not_authoritative"};
    const to = delivery.senderEmail || delivery.email;
    const payload = record({to, template: templates.cancellationSettled({reference: settlementId}),
      eventType: "delivery_cancellation_settled", collection: "deliveryRequests", sourceId: settlementId,
      required: "settled", recipientField: delivery.senderEmail ? "senderEmail" : "email", senderCategory: "info",
      extra: {recipientId: text(delivery.senderId)}});
    if (payload) payload.sourceRequiredFields = {cancellationSettlementStatus: "settled"};
    return createOnly(db, emailId("delivery_cancellation_settled", settlementId), payload);
  }

  const invoiceId = asId(path, "businessInvoices");
  if (invoiceId && eventType === UPDATED && !["paid", "paid_manually"].includes(lower(before.status)) &&
      ["paid", "paid_manually"].includes(lower(after.status)) && Number(after.balanceDue || 0) <= 0) {
    const to = after.billingEmail;
    const ref = text(after.invoiceNumber || invoiceId);
    const payload = record({to, template: templates.businessInvoicePaid({reference: ref}),
      eventType: "business_invoice_paid", collection: "businessInvoices", sourceId: invoiceId,
      required: lower(after.status), recipientField: "billingEmail", senderCategory: "business",
      extra: {businessId: text(after.businessId), invoiceId}});
    if (payload) payload.sourceRequiredFields = {balanceDue: 0};
    return createOnly(db, emailId("business_invoice_paid", invoiceId), payload);
  }

  const walletTransactionId = asId(path, "walletTransactions");
  if (walletTransactionId && eventType === CREATED && lower(after.status) === "completed" &&
      lower(after.walletType || "sender") === "sender" && after.userId && after.userEmail) {
    const isStarterWelcome = lower(after.metadata && after.metadata.source) === "sender_welcome_roth" ||
      walletTransactionId.startsWith("sender_welcome_roth_");
    if (isStarterWelcome) return {status: "ignored", reason: "starter_welcome_has_dedicated_email", eventId};
    const amount = after.amount == null ? after.creditedAmount : after.amount;
    const type = lower(after.balanceType || after.type || after.reason);
    const movement = type.includes("refund") ? "refunded" : type.includes("debit") || type.includes("payment") ? "debited" : type.includes("restore") ? "restored" : type.includes("credit") || type.includes("reward") ? "credited" : "updated";
    const payload = record({to: after.userEmail, template: templates.rothActivity({
      amount, movement, reference: walletTransactionId,
    }), eventType: "roth_activity_ready", collection: "walletTransactions", sourceId: walletTransactionId,
      required: "completed", recipientField: "userEmail", senderCategory: "info",
      extra: {recipientId: text(after.uid || after.userId)}});
    return createOnly(db, emailId("roth_activity", walletTransactionId), payload);
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
    const inviterEmail = record({to: after.referrerEmail, template: templates.referralReward(),
      eventType: "referral_award_finalized", collection: "referrals", sourceId: referralId, required: "roth_awarded",
      recipientField: "referrerEmail", senderCategory: "info", extra: {recipientId: text(after.referrerUserId)}});
    const referredEmail = record({to: after.referredEmail, template: templates.referralReward(),
      eventType: "referral_award_finalized", collection: "referrals", sourceId: referralId, required: "roth_awarded",
      recipientField: "referredEmail", senderCategory: "info", extra: {recipientId: text(after.referredUserId || referralId)}});
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
    const decisionKey = after.adminOperationUpdatedAt || after.riderAuthorityUpdatedAt;
    const decisionId = timestampKey(decisionKey);
    const payload = record({to: after.email, template: templates.riderDecision({decision}),
      eventType: "rider_application_decision", collection: "riderProfiles", sourceId: riderId,
      required: decision, recipientField: "email", senderCategory: "info",
      extra: {recipientId: riderId, decisionKey: decisionId}});
    return createOnly(db, emailId("rider_application", riderId, decision, decisionId), payload);
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
    const [type] = healthEvents[pickupStatus];
    const to = after.email;
    const payload = record({to, template: templates.healthUpdate({type: pickupStatus}),
      eventType: `health_plus_${type}`, collection: "prescriptionPickups", sourceId: pickupId,
      required: pickupStatus, recipientField: "email", senderCategory: "health",
      extra: {pickupId, recipientId: text(after.userId || after.senderId)}});
    return createOnly(db, emailId("health", pickupId, type), payload);
  }

  const giftId = asId(path, "giftRequests");
  if (giftId && (eventType === CREATED || eventType === UPDATED) &&
      lower(after.paymentStatus) === "paid" && lower(before.paymentStatus) !== "paid") {
    const rothAmount = Number(after.walletContributionGbp || 0);
    const cardAmount = Number(after.remainingStripeAmountGbp || 0);
    if (rothAmount > 0 && Number.isFinite(rothAmount) && Number.isFinite(cardAmount) && cardAmount >= 0) {
      const ledger = await db.collection("walletTransactions").doc(`gift_roth_${giftId}`).get();
      if (!ledger.exists || lower(ledger.data().status) !== "completed" ||
          Number(ledger.data().amount) !== -rothAmount || text(ledger.data().referenceId) !== giftId) {
        return {status: "skipped", reason: "gift_roth_ledger_not_final"};
      }
      const template = templates.giftPaymentConfirmed({recipientName: after.recipientName, rothAmount, split: cardAmount > 0});
      const payload = record({to: after.senderEmail, template, eventType: "gift_payment_confirmed", collection: "giftRequests",
        sourceId: giftId, required: "paid", recipientField: "senderEmail", senderCategory: "gifts",
        extra: {recipientRole: "sender", giftPaymentRothAmount: rothAmount, giftPaymentCardAmount: cardAmount,
          sourceRequiredFields: {paymentStatus: "paid", walletContributionGbp: rothAmount, remainingStripeAmountGbp: cardAmount}}});
      return createOnly(db, emailId("gift_payment_confirmed", giftId), payload);
    }
  }
  if (giftId && eventType === UPDATED && lower(after.status || after.giftStatus) === "delivered" &&
      lower(after.giftStoryStatus) === "unlocked" &&
      (lower(before.status || before.giftStatus) !== "delivered" || lower(before.giftStoryStatus) !== "unlocked")) {
    const {queueGiftDeliveryEmail} = require("./gift-email-notifications");
    const {queueStoryEmail} = require("./gift-story-automation");
    const senderEmail = normalizeEmail(after.senderEmail);
    const recipientEmail = normalizeEmail(after.recipientEmail || after.recipientContact);
    const [deliveryId, senderQueued, recipientQueued] = await Promise.all([
      queueGiftDeliveryEmail({giftId, gift: after, db}),
      queueStoryEmail(db, {giftId, role: "sender", email: senderEmail, token: text(after.giftStoryAccessToken),
        sourceRecipientField: "senderEmail"}),
      queueStoryEmail(db, {giftId, role: "recipient", email: recipientEmail, token: text(after.recipientStoryToken),
        sourceRecipientField: normalizeEmail(after.recipientEmail) ? "recipientEmail" : "recipientContact"}),
    ]);
    return {status: "published", deliveryId, senderQueued, recipientQueued};
  }

  return {status: "ignored", eventId};
}

module.exports = {CREATED, UPDATED, documentPath, publishFromEvent, paymentConfirmed, finalDelivery, isOrdinaryDelivery};
