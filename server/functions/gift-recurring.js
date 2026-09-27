/* eslint-disable max-len, require-jsdoc */
"use strict";

const functions = require("firebase-functions/v1");
const {FieldValue, Timestamp, getFirestore} = require("firebase-admin/firestore");
const {senderPaymentCallable} = require("./sender-app-check");
const emailQueue = require("./email-queue");
const templates = require("./transactional-email-templates");
const core = require("./gift-recurring-core");

const SERIES_COLLECTION = "giftRecurringSeries";
const RENEWAL_COLLECTION = "giftRecurringRenewals";

function text(value, max = 500) {
  return `${value || ""}`.trim().slice(0, max);
}

function money(value) {
  const amount = Number(value);
  return Number.isFinite(amount) ? Math.round(amount * 100) / 100 : 0;
}

function seriesRef(db, seriesId) {
  return db.collection(SERIES_COLLECTION).doc(seriesId);
}

function renewalRef(db, renewalId) {
  return db.collection(RENEWAL_COLLECTION).doc(renewalId);
}

function invoiceSubscriptionId(invoice = {}) {
  return text(invoice.subscription) || text(invoice.parent && invoice.parent.subscription_details && invoice.parent.subscription_details.subscription);
}

function validateRenewalInvoice(invoice = {}, series = {}) {
  const reasons = [];
  const expectedSubscriptionId = text(series.stripeSubscriptionId);
  const subscriptionId = invoiceSubscriptionId(invoice);
  if (!expectedSubscriptionId || subscriptionId !== expectedSubscriptionId) reasons.push("subscription_mismatch");
  if (text(invoice.currency).toLowerCase() !== "gbp") reasons.push("currency_mismatch");
  const amountPaid = Number(invoice.amount_paid == null ? invoice.total : invoice.amount_paid);
  const expectedAmount = Math.round(money(series.budgetGbp) * 100);
  if (!Number.isFinite(amountPaid) || amountPaid !== expectedAmount) reasons.push("amount_mismatch");
  if (text(invoice.billing_reason).toLowerCase() !== "subscription_cycle") reasons.push("billing_reason_mismatch");
  const periodStart = Number(invoice.period_start);
  const periodEnd = Number(invoice.period_end);
  if (!Number.isFinite(periodStart) || !Number.isFinite(periodEnd) || periodStart <= 0 || periodEnd <= periodStart) reasons.push("billing_period_mismatch");
  return {valid: reasons.length === 0, reasons, expectedAmount, expectedSubscriptionId};
}

async function findSeriesBySubscription(db, subscriptionId) {
  const id = text(subscriptionId);
  if (!id) return null;
  const snapshot = await db.collection(SERIES_COLLECTION).where("stripeSubscriptionId", "==", id).limit(1).get();
  if (snapshot.empty) return null;
  return {ref: snapshot.docs[0].ref, data: snapshot.docs[0].data() || {}};
}

function giftIsRecurringSelfGift(gift = {}) {
  const mode = text(gift.giftMode || gift.mode || gift.giftType).toLowerCase();
  return ["gift_myself", "send_to_me", "myself", "self"].includes(mode) && core.isRecurringFrequency(gift.selfGiftFrequency);
}

function paymentMethodIdFromIntent(intent) {
  if (!intent) return "";
  return typeof intent.payment_method === "string" ? intent.payment_method : text(intent.payment_method && intent.payment_method.id);
}

function initialGiftSubscriptionMetadata({seriesId, giftId, senderId, frequency, renewalBudget}) {
  return {
    type: "gift_recurring_subscription",
    giftRecurringSeriesId: seriesId,
    initialGiftId: giftId,
    senderId,
    frequency,
    renewalBudgetGbp: `${renewalBudget}`,
  };
}

function recurringTemplate(kind, options) {
  if (kind === "payment_failed") return templates.giftRecurringPaymentProblem(options);
  if (kind === "cancellation_scheduled") return templates.giftRecurringCancellationScheduled(options);
  throw new Error("Unsupported recurring Gift communication.");
}

async function queueRecurringCommunication(db, {kind, series, invoiceId = ""}) {
  const template = recurringTemplate(kind, {
    amount: series.budgetGbp,
    frequency: core.intervalFor(series.frequency).label,
    nextChargeAt: series.nextExpectedRenewalAt,
    ctaUrl: "https://circumuk.com/?app=gifts",
  });
  return emailQueue.enqueueEmail(db, {
    id: emailQueue.emailQueueId(["gift_recurring", kind, series.id, invoiceId]),
    to: series.senderEmail,
    subject: template.subject,
    textBody: template.text,
    htmlBody: template.html,
    eventType: `gift_recurring_${kind}`,
    sourceCollection: SERIES_COLLECTION,
    sourceDocumentId: series.id,
    sourceRequiredStatus: kind === "payment_failed" ? "past_due" : "cancellation_pending",
    senderCategory: "gifts",
    recipientRole: "sender",
    tags: template.providerTags,
    extra: {invoiceId: invoiceId || null, templateId: template.templateId},
  });
}

async function ensureSeriesAfterInitialPayment({db = getFirestore(), stripe, giftId, payment, eventId = ""}) {
  const giftRef = db.collection("giftRequests").doc(text(giftId));
  const giftSnap = await giftRef.get();
  if (!giftSnap.exists) return {handled: false, reason: "initial_gift_missing"};
  const gift = giftSnap.data() || {};
  if (!giftIsRecurringSelfGift(gift)) return {handled: false, reason: "not_recurring_self_gift"};
  const frequency = core.normalizeFrequency(gift.selfGiftFrequency);
  const interval = core.intervalFor(frequency);
  const budgetGbp = money(gift.grossGiftBudget || gift.grossBudget || gift.budget);
  const cardAmount = money(gift.cardAmount == null ? gift.remainingStripeAmountGbp : gift.cardAmount);
  const customerId = text(payment.customerId || gift.stripeCustomerId);
  if (!customerId || cardAmount <= 0) throw new Error("Recurring Gift requires a saved card-backed initial payment.");
  const pattern = gift.recurringDeliveryPattern || core.buildDeliveryPattern(gift.deliveryDate, {
    timeWindow: gift.deliveryTimeWindow,
    flexible: gift.flexibleDelivery,
  });
  if (pattern.valid !== true) throw new Error("Recurring Gift delivery pattern requires action.");
  const seriesId = core.seriesIdForGift(giftId);
  const ref = seriesRef(db, seriesId);
  const initialPaidAt = core.toDate(gift.paidAt) || new Date();
  const nextExpectedRenewalAt = core.nextRenewalAt({from: initialPaidAt, frequency});
  const base = {
    id: seriesId,
    seriesId,
    senderId: text(gift.senderId),
    senderEmail: text(gift.senderEmail).toLowerCase(),
    initialGiftId: text(giftId),
    stripeCustomerId: customerId,
    stripeSubscriptionId: null,
    frequency,
    interval: interval.interval,
    intervalCount: interval.interval_count,
    budgetGbp,
    originalDeliveryPattern: pattern,
    status: "creating",
    cancelAtPeriodEnd: false,
    cancellationState: "none",
    nextExpectedRenewalAt,
    consentAccepted: gift.recurringConsentAccepted === true,
    consentCopy: text(gift.recurringConsentCopy) || core.CONSENT_COPY,
    initialPaymentId: text(payment.paymentIntentId || payment.providerId),
    initialPaymentEventId: text(eventId),
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };
  let existingSeries;
  await db.runTransaction(async (transaction) => {
    const snap = await transaction.get(ref);
    existingSeries = snap.exists ? snap.data() || {} : null;
    if (existingSeries && existingSeries.stripeSubscriptionId) return;
    if (existingSeries && existingSeries.senderId !== base.senderId) throw new Error("Recurring Gift ownership changed.");
    transaction.set(ref, {...base, ...(snap.exists ? {createdAt: snap.data().createdAt} : {})}, {merge: true});
  });

  if (existingSeries && existingSeries.stripeSubscriptionId) {
    return {handled: true, seriesId, stripeSubscriptionId: existingSeries.stripeSubscriptionId, status: existingSeries.status || "active", idempotent: true};
  }

  if (stripe.subscriptions && typeof stripe.subscriptions.list === "function") {
    const existing = await stripe.subscriptions.list({customer: customerId, status: "all", limit: 100});
    const recovered = (existing.data || []).find((subscription) =>
      text(subscription.metadata && subscription.metadata.giftRecurringSeriesId) === seriesId,
    );
    if (recovered) {
      await ref.set({
        stripeSubscriptionId: recovered.id,
        stripeSubscriptionStatus: recovered.status,
        status: core.subscriptionState(recovered.status, recovered.cancel_at_period_end),
        cancelAtPeriodEnd: recovered.cancel_at_period_end === true,
        currentPeriodStart: recovered.current_period_start ? recovered.current_period_start * 1000 : null,
        currentPeriodEnd: recovered.current_period_end ? recovered.current_period_end * 1000 : null,
        recoveredAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
      return {handled: true, seriesId, stripeSubscriptionId: recovered.id, status: recovered.status, recovered: true};
    }
  }

  let paymentMethodId = text(payment.paymentMethodId);
  if (!paymentMethodId && payment.paymentIntentId) {
    const intent = await stripe.paymentIntents.retrieve(payment.paymentIntentId);
    paymentMethodId = paymentMethodIdFromIntent(intent);
  }
  if (paymentMethodId && stripe.customers && stripe.customers.update) {
    await stripe.customers.update(customerId, {invoice_settings: {default_payment_method: paymentMethodId}}, {idempotencyKey: `gift_series_default_pm_${seriesId}`});
  }
  const subscription = await stripe.subscriptions.create({
    customer: customerId,
    items: [{price_data: {
      currency: "gbp",
      unit_amount: Math.round(budgetGbp * 100),
      product_data: {name: "CIRCUM Self Gift renewal"},
      recurring: {interval: interval.interval, interval_count: interval.interval_count},
    }, quantity: 1}],
    ...(paymentMethodId ? {default_payment_method: paymentMethodId} : {}),
    trial_end: Math.floor(nextExpectedRenewalAt / 1000),
    collection_method: "charge_automatically",
    payment_behavior: "default_incomplete",
    payment_settings: {save_default_payment_method: "on_subscription"},
    metadata: initialGiftSubscriptionMetadata({seriesId, giftId, senderId: gift.senderId, frequency, renewalBudget: budgetGbp}),
  }, {idempotencyKey: `gift_subscription_${seriesId}`});

  await db.runTransaction(async (transaction) => {
    const snap = await transaction.get(ref);
    const current = snap.data() || {};
    if (current.stripeSubscriptionId && current.stripeSubscriptionId !== subscription.id) throw new Error("Recurring Gift subscription identity changed.");
    transaction.set(ref, {
      stripeSubscriptionId: subscription.id,
      stripeSubscriptionStatus: subscription.status,
      status: core.subscriptionState(subscription.status, subscription.cancel_at_period_end),
      cancelAtPeriodEnd: subscription.cancel_at_period_end === true,
      currentPeriodStart: subscription.current_period_start ? subscription.current_period_start * 1000 : null,
      currentPeriodEnd: subscription.current_period_end ? subscription.current_period_end * 1000 : null,
      nextExpectedRenewalAt: nextExpectedRenewalAt,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    transaction.set(giftRef, {
      recurringSeriesId: seriesId,
      stripeSubscriptionId: subscription.id,
      stripeCustomerId: customerId,
      recurringFrequency: frequency,
      recurringConsentAccepted: true,
      recurringConsentCopy: text(gift.recurringConsentCopy) || core.CONSENT_COPY,
      recurringDeliveryPattern: pattern,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  });
  return {handled: true, seriesId, stripeSubscriptionId: subscription.id, status: subscription.status};
}

async function handleGiftSubscriptionEvent({db = getFirestore(), event}) {
  const subscription = event && event.data && event.data.object || {};
  const metadata = subscription.metadata || {};
  const found = text(metadata.giftRecurringSeriesId) ? {ref: seriesRef(db, text(metadata.giftRecurringSeriesId))} : await findSeriesBySubscription(db, subscription.id);
  if (!found) return {handled: false};
  const ref = found.ref;
  const status = core.subscriptionState(subscription.status, subscription.cancel_at_period_end === true);
  await db.runTransaction(async (transaction) => {
    const snap = await transaction.get(ref);
    if (!snap.exists) return;
    const patch = {
      stripeSubscriptionId: subscription.id,
      stripeSubscriptionStatus: text(subscription.status),
      status,
      cancelAtPeriodEnd: subscription.cancel_at_period_end === true,
      cancellationState: subscription.cancel_at_period_end === true ? "pending_period_end" : event.type === "customer.subscription.deleted" ? "ended" : "none",
      currentPeriodStart: subscription.current_period_start ? subscription.current_period_start * 1000 : null,
      currentPeriodEnd: subscription.current_period_end ? subscription.current_period_end * 1000 : null,
      cancelAt: subscription.cancel_at ? subscription.cancel_at * 1000 : null,
      ...(event.type === "customer.subscription.deleted" ? {endedAt: FieldValue.serverTimestamp()} : {}),
      updatedAt: FieldValue.serverTimestamp(),
    };
    transaction.set(ref, patch, {merge: true});
  });
  if (event.type === "customer.subscription.updated" && subscription.cancel_at_period_end === true) {
    const snap = await ref.get();
    if (snap.exists && snap.data().senderEmail) await queueRecurringCommunication(db, {kind: "cancellation_scheduled", series: {id: ref.id, ...snap.data()}});
  }
  return {handled: true, seriesId: ref.id, status};
}

async function fulfillPaidRenewal({db = getFirestore(), seriesRefValue, invoice, eventId = ""}) {
  const subscriptionId = invoiceSubscriptionId(invoice);
  const renewalId = core.renewalIdForInvoice(subscriptionId, invoice.id);
  const giftId = core.renewalGiftIdForInvoice(subscriptionId, invoice.id);
  const claim = renewalRef(db, renewalId);
  const giftRef = db.collection("giftRequests").doc(giftId);
  return db.runTransaction(async (transaction) => {
    const seriesSnap = await transaction.get(seriesRefValue);
    const seriesData = seriesSnap.exists ? seriesSnap.data() || {} : {};
    const initialGiftId = text(seriesData.initialGiftId);
    const [claimSnap, initialSnap, giftSnap] = await Promise.all([
      transaction.get(claim),
      initialGiftId ? transaction.get(db.collection("giftRequests").doc(initialGiftId)) : Promise.resolve({exists: false}),
      transaction.get(giftRef),
    ]);
    if (claimSnap.exists || giftSnap.exists) return {handled: true, idempotent: true, renewalId, giftId};
    if (!seriesSnap.exists) return {handled: false, reason: "series_missing"};
    const series = seriesData;
    const validation = validateRenewalInvoice(invoice, series);
    if (!validation.valid) {
      transaction.create(claim, {
        renewalId,
        seriesId: seriesSnap.id,
        invoiceId: invoice.id,
        status: "action_required",
        reason: "renewal_invoice_validation_failed",
        validationReasons: validation.reasons,
        eventId,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      transaction.set(seriesRefValue, {status: "action_required", lastActionRequiredRenewalId: renewalId, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
      return {handled: true, actionRequired: true, renewalId, reason: "renewal_invoice_validation_failed", validationReasons: validation.reasons};
    }
    const initialGift = initialSnap.exists ? initialSnap.data() || {} : {};
    if (!initialSnap.exists || !initialGiftId) {
      transaction.create(claim, {renewalId, seriesId: seriesSnap.id, invoiceId: invoice.id, status: "action_required", reason: "initial_gift_missing", eventId, createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()});
      transaction.set(seriesRefValue, {status: "action_required", lastActionRequiredRenewalId: renewalId, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
      return {handled: true, actionRequired: true, renewalId};
    }
    const periodStart = invoice.period_start ? new Date(invoice.period_start * 1000) : null;
    const periodEnd = invoice.period_end ? new Date(invoice.period_end * 1000) : null;
    const delivery = core.deliveryDateForPeriod({pattern: series.originalDeliveryPattern, periodStart, periodEnd, now: new Date()});
    if (delivery.status !== "scheduled") {
      transaction.create(claim, {renewalId, seriesId: seriesSnap.id, invoiceId: invoice.id, status: "action_required", reason: delivery.reason, eventId, createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()});
      transaction.set(seriesRefValue, {status: "action_required", lastActionRequiredRenewalId: renewalId, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
      return {handled: true, actionRequired: true, renewalId, reason: delivery.reason};
    }
    const gift = {...initialGift};
    for (const field of ["stripeCheckoutSessionId", "stripePaymentIntentId", "stripePaymentEventId", "giftCheckoutReservationId", "paymentKey", "paidAt", "createdAt", "updatedAt"]) delete gift[field];
    const now = FieldValue.serverTimestamp();
    transaction.create(claim, {
      renewalId,
      seriesId: seriesSnap.id,
      invoiceId: invoice.id,
      status: "fulfilled",
      giftId,
      eventId,
      periodStart: invoice.period_start ? invoice.period_start * 1000 : null,
      periodEnd: invoice.period_end ? invoice.period_end * 1000 : null,
      createdAt: now,
      updatedAt: now,
    });
    transaction.create(giftRef, {
      ...gift,
      giftRequestId: giftId,
      giftId,
      recurringSeriesId: seriesSnap.id,
      recurringRenewalId: renewalId,
      initialGiftId,
      stripeSubscriptionId: subscriptionId,
      stripeInvoiceId: invoice.id,
      paymentProvenance: {provider: "stripe", type: "subscription_invoice", invoiceId: invoice.id, subscriptionId},
      paymentStatus: "paid",
      paymentMethod: "saved_card",
      walletContributionGbp: 0,
      rothApplied: 0,
      cardAmount: money(series.budgetGbp),
      remainingStripeAmountGbp: money(series.budgetGbp),
      grossGiftBudget: money(series.budgetGbp),
      deliveryDate: Timestamp.fromDate(new Date(delivery.date)),
      deliveryTimeWindow: delivery.timeWindow || initialGift.deliveryTimeWindow || "",
      recurringDeliveryPattern: series.originalDeliveryPattern,
      giftStatus: "submitted_for_review",
      status: "submitted_for_review",
      createdAt: now,
      updatedAt: now,
    });
    transaction.set(seriesRefValue, {
      status: "active",
      lastFulfilledInvoiceId: invoice.id,
      lastFulfilledRenewalId: renewalId,
      lastFulfilledPeriodEnd: invoice.period_end ? invoice.period_end * 1000 : null,
      nextExpectedRenewalAt: core.nextRenewalAt({from: periodEnd || new Date(), frequency: series.frequency}),
      updatedAt: now,
    }, {merge: true});
    return {handled: true, renewalId, giftId, idempotent: false};
  });
}

async function handleGiftSubscriptionInvoice({db = getFirestore(), stripe, event}) {
  const invoice = event && event.data && event.data.object || {};
  const subscriptionId = invoiceSubscriptionId(invoice);
  const found = await findSeriesBySubscription(db, subscriptionId);
  if (!found) return {handled: false};
  if (event.type === "invoice.paid") return fulfillPaidRenewal({db, seriesRefValue: found.ref, invoice, eventId: event.id});
  if (event.type === "invoice.payment_failed") {
    const state = text(invoice.status).toLowerCase() === "uncollectible" ? "failed" : "past_due";
    await found.ref.set({status: state, lastFailedInvoiceId: invoice.id, lastPaymentFailureAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()}, {merge: true});
    const snapshot = await found.ref.get();
    if (snapshot.exists) await queueRecurringCommunication(db, {kind: "payment_failed", series: {id: found.ref.id, ...snapshot.data()}, invoiceId: invoice.id});
    return {handled: true, state, renewalId: core.renewalIdForInvoice(subscriptionId, invoice.id)};
  }
  return {handled: false};
}

async function reconcileGiftRecurringRenewalsCore({db = getFirestore(), stripe, limit = 25, nowMs = Date.now()}) {
  if (!stripe || !stripe.invoices || typeof stripe.invoices.list !== "function") throw new Error("Recurring Gift reconciliation requires Stripe invoice access.");
  const boundedLimit = Math.max(1, Math.min(Number(limit) || 25, 25));
  const snapshot = await db.collection(SERIES_COLLECTION)
      .where("status", "in", ["active", "cancellation_pending", "past_due"])
      .where("nextExpectedRenewalAt", "<=", nowMs + 24 * 60 * 60 * 1000)
      .orderBy("nextExpectedRenewalAt")
      .limit(boundedLimit)
      .get();
  const counts = {examined: snapshot.size, paidInvoices: 0, fulfilled: 0, idempotent: 0, actionRequired: 0};
  for (const document of snapshot.docs) {
    const series = document.data() || {};
    const invoicePage = await stripe.invoices.list({subscription: series.stripeSubscriptionId, limit: 10});
    for (const invoice of invoicePage.data || []) {
      if (!core.successfulInvoice(invoice)) continue;
      counts.paidInvoices += 1;
      const result = await fulfillPaidRenewal({db, seriesRefValue: document.ref, invoice, eventId: `gift-recurring-reconcile-${invoice.id}`});
      if (result.idempotent) counts.idempotent += 1;
      else if (result.actionRequired) counts.actionRequired += 1;
      else if (result.giftId) counts.fulfilled += 1;
    }
  }
  return counts;
}

function requireAuth(context) {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Sign in to manage recurring Gifts.");
}

function createGiftRecurringCallables(stripe) {
  const cancel = senderPaymentCallable(async (data, context) => {
    requireAuth(context);
    const db = getFirestore();
    const id = text(data.seriesId);
    const ref = seriesRef(db, id);
    const snap = await ref.get();
    if (!snap.exists || snap.data().senderId !== context.auth.uid) throw new functions.https.HttpsError("not-found", "Recurring Gift not found.");
    const series = snap.data();
    if (series.cancelAtPeriodEnd === true || series.status === "ended") return {seriesId: id, status: series.status, idempotent: true};
    const subscription = await stripe.subscriptions.update(series.stripeSubscriptionId, {cancel_at_period_end: true}, {idempotencyKey: `gift_cancel_${id}`});
    await ref.set({status: core.subscriptionState(subscription.status, true), cancelAtPeriodEnd: true, cancellationState: "pending_period_end", cancelAt: subscription.cancel_at ? subscription.cancel_at * 1000 : subscription.current_period_end * 1000, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
    return {seriesId: id, status: "cancellation_pending", cancelAtPeriodEnd: true, cancelAt: subscription.cancel_at || subscription.current_period_end};
  });
  const portal = senderPaymentCallable(async (data, context) => {
    requireAuth(context);
    const db = getFirestore();
    const snap = await seriesRef(db, text(data.seriesId)).get();
    if (!snap.exists || snap.data().senderId !== context.auth.uid) throw new functions.https.HttpsError("not-found", "Recurring Gift not found.");
    const returnUrl = /^https:\/\/circumuk\.com(?:[/?#].*)?$/.test(text(data.returnUrl)) ? text(data.returnUrl) : "https://circumuk.com/?app=gifts";
    const session = await stripe.billingPortal.sessions.create({customer: snap.data().stripeCustomerId, return_url: returnUrl});
    return {url: session.url};
  });
  const status = senderPaymentCallable(async (data, context) => {
    requireAuth(context);
    const snap = await seriesRef(getFirestore(), text(data.seriesId)).get();
    if (!snap.exists || snap.data().senderId !== context.auth.uid) throw new functions.https.HttpsError("not-found", "Recurring Gift not found.");
    const value = snap.data() || {};
    return {seriesId: snap.id, frequency: value.frequency, budgetGbp: value.budgetGbp, status: value.status, cancelAtPeriodEnd: value.cancelAtPeriodEnd === true, cancellationState: value.cancellationState || "none", nextExpectedRenewalAt: value.nextExpectedRenewalAt || null, stripeSubscriptionId: value.stripeSubscriptionId};
  });
  return {cancel, portal, status};
}

module.exports = {
  createGiftRecurringCallables,
  ensureSeriesAfterInitialPayment,
  fulfillPaidRenewal,
  handleGiftSubscriptionEvent,
  handleGiftSubscriptionInvoice,
  validateRenewalInvoice,
  invoiceSubscriptionId,
  reconcileGiftRecurringRenewalsCore,
  reconcileGiftRecurringRenewals: (stripe) => functions.runWith({secrets: ["STRIPE_SECRET_KEY"]}).pubsub.schedule("every 15 minutes").onRun(() => reconcileGiftRecurringRenewalsCore({stripe})),
  _private: {giftIsRecurringSelfGift, initialGiftSubscriptionMetadata, queueRecurringCommunication},
};
