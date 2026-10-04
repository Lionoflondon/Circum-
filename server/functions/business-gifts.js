/* eslint-disable max-len, require-jsdoc */
"use strict";

const crypto = require("node:crypto");
const functions = require("firebase-functions/v1");
const {FieldValue, getFirestore, Timestamp} = require("firebase-admin/firestore");
const checkoutReservations = require("./business-checkout-reservations");

const ORDER_COLLECTION = "businessGiftOrders";
const EVENT_COLLECTION = "businessGiftOrderEvents";
const MIN_BUDGET_GBP = 50;
const MAX_BUDGET_GBP = 100000;
const APPROVED_BUDGETS_GBP = Object.freeze([50, 100, 250, 500, 1000, 1500]);
const RAILS = new Set(["card", "invoice", "roth"]);

function text(value, max = 500) {
  return `${value || ""}`.trim().slice(0, max);
}

function money(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? Math.round(parsed * 100) / 100 : 0;
}

function orderIdFor({businessId, uid, idempotencyKey}) {
  return `business_gift_${crypto.createHash("sha256")
      .update(`${businessId}:${uid}:${idempotencyKey}`)
      .digest("hex")
      .slice(0, 40)}`;
}

function giftIdFor(orderId) {
  return `business_gift_${orderId}`;
}

function checkoutSessionIdFor(checkout = {}) {
  return text(checkout.sessionId || checkout.providerSessionId, 200) || null;
}

function normalizeRail(value) {
  const rail = text(value, 32).toLowerCase();
  return RAILS.has(rail) ? rail : "";
}

function normalizeRecipient(data = {}) {
  const recipientName = text(data.recipientName, 120);
  const recipientPhone = text(data.recipientPhone, 40);
  const recipientEmail = text(data.recipientEmail, 254).toLowerCase();
  const deliveryAddress = text(data.deliveryAddress, 500);
  const deliveryDate = normalizeBusinessDeliveryDate(data.deliveryDate);
  if (!recipientName || (!recipientPhone && !recipientEmail) || !deliveryAddress || !deliveryDate) {
    throw new functions.https.HttpsError(
        "invalid-argument",
        "Recipient name, contact, delivery address, and delivery date are required.",
    );
  }
  return {
    recipientName,
    recipientPhone,
    recipientEmail,
    deliveryAddress,
    deliveryDate,
    deliveryTimeWindow: text(data.deliveryTimeWindow, 120),
    recipientPrivacy: "protected",
    recipientValueVisibility: "sender_only",
  };
}

function localDateInTimeZone(now = new Date(), timeZone = "Europe/London") {
  const parts = new Intl.DateTimeFormat("en-CA", {timeZone, year: "numeric", month: "2-digit", day: "2-digit"}).formatToParts(now);
  const values = Object.fromEntries(parts.filter((part) => part.type !== "literal").map((part) => [part.type, part.value]));
  return `${values.year}-${values.month}-${values.day}`;
}

function normalizeBusinessDeliveryDate(value, {now = new Date(), timeZone = "Europe/London"} = {}) {
  const raw = text(value, 40);
  if (!raw) return "";
  const dateOnly = /^\d{4}-\d{2}-\d{2}$/.test(raw) ? raw : (() => {
    const parsed = new Date(raw);
    if (Number.isNaN(parsed.getTime())) return "";
    return localDateInTimeZone(parsed, timeZone);
  })();
  if (!/^\d{4}-\d{2}-\d{2}$/.test(dateOnly)) return "";
  if (dateOnly < localDateInTimeZone(now, timeZone)) return "";
  return dateOnly;
}

function memberRole(account = {}, uid, email) {
  const members = Array.isArray(account.teamMembers) ? account.teamMembers : [];
  const member = members.find((item) =>
    text(item.userId, 160) === uid || (email && text(item.email, 254).toLowerCase() === email));
  if (member) {
    if (["removed", "rejected", "inactive", "suspended"].includes(text(member.status, 40).toLowerCase())) return "";
    return text(member.role || "member", 40).toLowerCase();
  }
  const ids = Array.isArray(account.teamMemberIds) ? account.teamMemberIds.map((item) => text(item, 160).toLowerCase()) : [];
  if (text(account.ownerUid, 160) === uid || text(account.createdByUserId, 160) === uid || ids.includes(uid.toLowerCase()) || (email && ids.includes(email))) return "member";
  return "";
}

async function requireBusinessMember(db, businessId, context) {
  if (!context || !context.auth || !context.auth.uid) {
    throw new functions.https.HttpsError("unauthenticated", "Sign in to use Business Gifts.");
  }
  const snap = await db.collection("businessAccounts").doc(businessId).get();
  if (!snap.exists) throw new functions.https.HttpsError("not-found", "Business account not found.");
  const account = snap.data() || {};
  const email = context.auth.token && context.auth.token.email_verified === true ? text(context.auth.token.email, 254).toLowerCase() : "";
  const role = memberRole(account, context.auth.uid, email);
  if (!role) throw new functions.https.HttpsError("permission-denied", "You do not have access to this Business account.");
  const approval = text(account.approvalStatus || account.status || account.businessStatus, 40).toLowerCase();
  if (["rejected", "suspended", "inactive"].includes(approval)) {
    throw new functions.https.HttpsError("failed-precondition", "This Business account cannot create Gifts.");
  }
  if (approval && !["approved", "verified", "active"].includes(approval)) {
    throw new functions.https.HttpsError("failed-precondition", "This Business account is not approved to create Gifts.");
  }
  return {account, role};
}

function orderInvoice(order, account, now) {
  return {
    invoiceId: order.invoiceId,
    invoiceNumber: `CIR-BIZ-GIFT-${order.id.slice(-8).toUpperCase()}`,
    businessId: order.businessId,
    businessName: account.businessName || account.companyName || "Business",
    billingEmail: account.billingEmail || account.contactEmail || null,
    description: "Business Gift order",
    lineItems: [{description: "Business Gift order", amount: order.budgetGbp}],
    subtotal: order.budgetGbp,
    total: order.budgetGbp,
    amountPaid: 0,
    balanceDue: order.budgetGbp,
    currency: "GBP",
    status: "open",
    invoiceStatus: "open",
    paymentStatus: "unpaid",
    checkoutProtocolVersion: 1,
    source: "business_gift_order",
    sourceType: "business_gift_order",
    businessGiftOrderId: order.id,
    createdByUserId: order.createdByUserId,
    createdAt: now,
    updatedAt: now,
  };
}

async function createBusinessGiftOrderHandler(stripe, data, context, dependencies = {}) {
  const db = dependencies.db || getFirestore();
  const businessId = text(data && data.businessId, 160);
  const idempotencyKey = text(data && data.idempotencyKey, 160);
  const budgetGbp = money(data && (data.budgetGbp ?? data.amount));
  const rail = normalizeRail(data && (data.paymentRail || data.rail));
  if (!businessId || !idempotencyKey || !rail || budgetGbp < MIN_BUDGET_GBP || budgetGbp > MAX_BUDGET_GBP || !APPROVED_BUDGETS_GBP.includes(budgetGbp)) {
    throw new functions.https.HttpsError("invalid-argument", "Choose a valid Business Gift amount, payment rail, and idempotency key.");
  }
  if (!stripe && rail === "card") throw new functions.https.HttpsError("unavailable", "Business Gift card checkout is unavailable.");
  const {account} = await requireBusinessMember(db, businessId, context);
  const recipient = normalizeRecipient(data);
  const orderId = orderIdFor({businessId, uid: context.auth.uid, idempotencyKey});
  const orderRef = db.collection(ORDER_COLLECTION).doc(orderId);
  const invoiceRef = db.collection("businessInvoices").doc(`gift_${orderId}`);
  const now = FieldValue.serverTimestamp();
  const base = {
    id: orderId,
    orderId,
    businessId,
    createdByUserId: context.auth.uid,
    businessName: account.businessName || account.companyName || "Business",
    billingEmail: text(account.billingEmail || account.contactEmail || account.ownerEmail, 254).toLowerCase(),
    paymentRail: rail,
    budgetGbp,
    currency: "GBP",
    status: rail === "invoice" ? "awaiting_invoice" : "awaiting_payment",
    giftCreationStatus: "pending_payment",
    privacyState: "protected",
    recipient: {
      ...recipient,
      // Keep recipient details on the server-owned order; do not expose value to recipient surfaces.
    },
    recipientPrivacy: "protected",
    recipientValueVisibility: "sender_only",
    invoiceId: invoiceRef.id,
    idempotencyKey,
    createdAt: now,
    updatedAt: now,
  };
  let existing;
  await db.runTransaction(async (transaction) => {
    const [orderSnap, invoiceSnap] = await Promise.all([transaction.get(orderRef), transaction.get(invoiceRef)]);
    if (orderSnap.exists) {
      const current = orderSnap.data() || {};
      if (current.businessId !== businessId || current.createdByUserId !== context.auth.uid || money(current.budgetGbp) !== budgetGbp || current.paymentRail !== rail) {
        throw new functions.https.HttpsError("already-exists", "This Business Gift request key was already used.");
      }
      existing = {order: current, invoice: invoiceSnap.exists ? invoiceSnap.data() || {} : null};
      return;
    }
    transaction.create(orderRef, base);
    transaction.create(invoiceRef, orderInvoice({...base, id: orderId}, account, now));
    transaction.create(db.collection(EVENT_COLLECTION).doc(`created_${orderId}`), {
      eventId: `created_${orderId}`,
      orderId,
      businessId,
      action: "business_gift_order_created",
      paymentRail: rail,
      createdByUserId: context.auth.uid,
      createdAt: now,
    });
  });
  if (existing) {
    if (existing.order.status === "paid" && existing.order.giftRequestId) return {...existing.order, idempotent: true};
    if (existing.order.checkoutUrl) return {...existing.order, idempotent: true};
  }
  const order = existing ? {...base, ...existing.order} : base;
  if (rail === "invoice") {
    return {orderId, invoiceId: invoiceRef.id, status: order.status, paymentRail: rail, idempotent: Boolean(existing)};
  }
  if (rail === "roth") {
    const businessPayments = require("./business-payments");
    const paid = await businessPayments._private.payBusinessInvoiceAtomically({
      db,
      businessId,
      invoiceId: invoiceRef.id,
      cardAmount: 0,
      rothAmount: budgetGbp,
      method: "roth",
      paymentId: `business_gift_roth_${orderId}`,
      metadata: {source: "business_gift_order", businessGiftOrderId: orderId},
    });
    const finalized = await finalizePaidBusinessGiftOrder({db, orderId, payment: paid});
    return {...finalized, paymentRail: rail};
  }
  const checkout = await checkoutReservations.checkout({
    db,
    stripe,
    invoiceId: invoiceRef.id,
    businessId,
    uid: context.auth.uid,
    data: {
      useRoth: false,
      returnUrl: text(data.returnUrl, 500) || "https://circumuk.com/?app=business&section=gifts",
    },
  });
  await orderRef.set({
    checkoutReservationId: checkout.checkoutReservationId || null,
    checkoutSessionId: checkoutSessionIdFor(checkout),
    checkoutUrl: checkout.checkoutUrl || null,
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  return {orderId, invoiceId: invoiceRef.id, paymentRail: rail, status: "awaiting_payment", checkoutUrl: checkout.checkoutUrl || null, checkoutSessionId: checkoutSessionIdFor(checkout)};
}

async function finalizePaidBusinessGiftOrder({db = getFirestore(), orderId, payment = {}}) {
  const orderRef = db.collection(ORDER_COLLECTION).doc(text(orderId, 160));
  const giftRef = db.collection("giftRequests").doc(giftIdFor(text(orderId, 160)));
  const invoiceRef = db.collection("businessInvoices").doc(`gift_${text(orderId, 160)}`);
  return db.runTransaction(async (transaction) => {
    const [orderSnap, invoiceSnap, giftSnap] = await Promise.all([transaction.get(orderRef), transaction.get(invoiceRef), transaction.get(giftRef)]);
    if (!orderSnap.exists) return {handled: false, reason: "order_missing"};
    const order = orderSnap.data() || {};
    if (giftSnap.exists || order.giftCreationStatus === "created") return {handled: true, idempotent: true, orderId, giftRequestId: giftRef.id};
    if (!invoiceSnap.exists || !["paid", "paid_manually"].includes(text(invoiceSnap.data().status, 40).toLowerCase())) {
      return {handled: false, reason: "payment_not_final"};
    }
    const recipient = order.recipient || {};
    const deliveryDate = normalizeBusinessDeliveryDate(recipient.deliveryDate);
    if (!deliveryDate) {
      transaction.set(orderRef, {status: "action_required", giftCreationStatus: "action_required", actionRequiredReason: "delivery_date_in_past_or_invalid", updatedAt: FieldValue.serverTimestamp()}, {merge: true});
      return {handled: true, actionRequired: true, reason: "delivery_date_in_past_or_invalid", orderId};
    }
    const now = FieldValue.serverTimestamp();
    const invoice = invoiceSnap.data() || {};
    const paymentMethod = text(invoice.paymentMethod || (order.paymentRail === "roth" ? "roth" : "card"), 40);
    const gift = {
      giftRequestId: giftRef.id,
      giftId: giftRef.id,
      businessGiftOrderId: orderId,
      businessId: order.businessId,
      senderId: order.createdByUserId,
      senderEmail: order.billingEmail || null,
      senderName: order.businessName || "Business",
      recipientName: text(recipient.recipientName, 120),
      recipientPhone: text(recipient.recipientPhone, 40),
      recipientEmail: text(recipient.recipientEmail, 254).toLowerCase(),
      recipientContact: `${text(recipient.recipientPhone, 40)} · ${text(recipient.recipientEmail, 254).toLowerCase()}`,
      deliveryAddress: text(recipient.deliveryAddress, 500),
      deliveryDate: Timestamp.fromDate(new Date(`${deliveryDate}T00:00:00.000Z`)),
      deliveryTimeWindow: text(recipient.deliveryTimeWindow, 120),
      giftMode: "business_gift",
      status: "submitted_for_review",
      giftStatus: "submitted_for_review",
      paymentStatus: "paid",
      paymentMethod,
      grossGiftBudget: money(order.budgetGbp),
      cardAmount: money(invoice.paymentMethod === "roth" ? 0 : invoice.total),
      rothApplied: paymentMethod === "roth" ? money(order.budgetGbp) : 0,
      walletContributionGbp: paymentMethod === "roth" ? money(order.budgetGbp) : 0,
      remainingStripeAmountGbp: paymentMethod === "roth" ? 0 : money(order.budgetGbp),
      recipientPrivacy: "protected",
      recipientValueVisibility: "sender_only",
      createdAt: now,
      paidAt: now,
      updatedAt: now,
    };
    transaction.create(giftRef, gift);
    transaction.set(orderRef, {
      status: "paid",
      giftCreationStatus: "created",
      giftRequestId: giftRef.id,
      paymentMethod,
      paidAt: now,
      updatedAt: now,
    }, {merge: true});
    transaction.create(db.collection(EVENT_COLLECTION).doc(`paid_${orderId}`), {
      eventId: `paid_${orderId}`,
      orderId,
      giftRequestId: giftRef.id,
      businessId: order.businessId,
      action: "business_gift_order_paid",
      paymentMethod,
      createdAt: now,
    });
    transaction.create(db.collection("adminAuditLogs").doc(), {
      action: "business_gift_order_paid",
      actionType: "business_gift_order_paid",
      recordType: ORDER_COLLECTION,
      recordId: orderId,
      businessId: order.businessId,
      giftRequestId: giftRef.id,
      paymentMethod,
      createdAt: now,
    });
    return {handled: true, idempotent: false, orderId, giftRequestId: giftRef.id, paymentMethod};
  });
}

function createBusinessGiftOrder(stripe) {
  return functions.runWith({enforceAppCheck: true, secrets: ["STRIPE_SECRET_KEY"]})
      .https.onCall((data, context) => createBusinessGiftOrderHandler(stripe, data || {}, context));
}

module.exports = {
  createBusinessGiftOrder,
  createBusinessGiftOrderHandler,
  finalizePaidBusinessGiftOrder,
  normalizeRail,
  normalizeBusinessDeliveryDate,
  normalizeRecipient,
  orderIdFor,
  giftIdFor,
  RAILS,
  _private: {MIN_BUDGET_GBP, MAX_BUDGET_GBP, APPROVED_BUDGETS_GBP, memberRole, requireBusinessMember, orderInvoice, checkoutSessionIdFor},
};
