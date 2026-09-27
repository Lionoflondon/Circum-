/* eslint-disable max-len, require-jsdoc */
"use strict";

// Disposable Cloud Run Job entrypoint for the Business Gifts release gate.
// This file is never exported from index.js and cannot receive production traffic.

const crypto = require("node:crypto");
const {getFirestore, Timestamp} = require("firebase-admin/firestore");
const {getApps, initializeApp} = require("firebase-admin/app");
const Stripe = require("stripe");
const {createStripeWebhookProcessor} = require("./stripe-webhook-core");
const {assertStripeEventMode} = require("./stripe-config");
const {scopedDatabase} = require("./qa-lifecycle")._test;
const businessGifts = require("./business-gifts");
const businessPayments = require("./business-payments");
const businessReservations = require("./business-checkout-reservations");
const checkoutRouter = require("./checkout-session-router");
const giftRecurring = require("./gift-recurring");
const giftsPayment = require("./gifts-payment");

const ROOT = "qaSpecialFlowFixtures";
const EXTRA_COLLECTIONS = [
  "businessAccounts", "businessInvoices", "businessGiftOrders", "businessGiftOrderEvents",
  "businessCheckoutReservations", "businessInvoicePayments", "business_wallets",
  "giftRequests", "giftRecurringSeries", "giftRecurringRenewals", "giftPaymentEvents",
  "emailQueue", "adminAuditLogs", "notifications", "businessRothPurchases",
  "businessRothCheckoutIntents", "paymentArtifactReconciliations",
];
const GBP = "gbp";
const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const text = (value) => `${value || ""}`.trim();
const id = (prefix) => `${prefix}_${crypto.randomUUID().replaceAll("-", "")}`;

function must(value, message) {
  if (!value) throw new Error(message);
  return value;
}

function contextFor(uid, email) {
  return {auth: {uid, token: {uid, email}}, app: {appId: "circum-qa-business-gifts"}, rawRequest: {headers: {}}};
}

function marker(fixture, value) {
  return {...value, isSyntheticQa: true, qaFixtureId: fixture.id, qaCreatedBy: fixture.qaCreatedBy, qaCreatedAt: fixture.qaCreatedAt};
}

async function waitForEvent(stripe, {type, objectId, predicate = () => true, attempts = 30}) {
  for (let attempt = 0; attempt < attempts; attempt += 1) {
    const page = await stripe.events.list({type, limit: 100});
    const event = (page.data || []).find((candidate) => {
      const object = candidate.data && candidate.data.object || {};
      return (!objectId || object.id === objectId) && predicate(candidate, object);
    });
    if (event) return event;
    await wait(2000);
  }
  throw new Error(`Stripe TEST event timeout: ${type}${objectId ? `:${objectId}` : ""}`);
}

function webhookProcessor({stripe, db, webhookSecret}) {
  const logger = {info() {}, warn() {}, error() {}};
  const businessAdapter = {
    handleBusinessPaymentIntent: (args) => businessPayments.handleBusinessPaymentIntent(args),
    handleBusinessCheckoutExpired: (args) => businessPayments.handleBusinessCheckoutExpired(args),
    handleBusinessCheckoutSession: async (session, eventId) => {
      const metadata = session.metadata || {};
      if (metadata.type !== "business_invoice_payment" || !metadata.checkoutReservationId) return {handled: false};
      const settled = await businessReservations.settle({db, session, id: metadata.checkoutReservationId});
      if (!metadata.businessGiftOrderId) return settled;
      const gift = await businessGifts.finalizePaidBusinessGiftOrder({db, orderId: metadata.businessGiftOrderId, payment: settled});
      return {...settled, businessGift: gift};
    },
  };
  return createStripeWebhookProcessor({
    stripe,
    resolveRuntimeConfig: () => ({mode: "test", secretKey: "sk_test_runtime_guard", webhookSecret, firebaseProject: "circum-2797c"}),
    assertEventMode: assertStripeEventMode,
    db,
    messaging: {send: async () => ({})},
    giftsPayment,
    ratingsTipping: {processStripeTipIntent: async () => ({handled: false}), processStripeTipRefund: async () => ({handled: false}), processStripeTipDispute: async () => ({handled: false})},
    stripeRefunds: {syncChargeRefund: async () => ({handled: false})},
    senderBooking: {handleSenderPaymentIntent: async () => ({handled: false}), handleSenderCheckoutSession: async () => ({handled: false})},
    businessPayments: businessAdapter,
    healthPlus: {},
    healthMembershipLifecycle: {handleHealthSubscriptionEvent: async () => ({handled: false}), handleHealthInvoiceEvent: async () => ({handled: false}), handleHealthMembershipCheckoutSession: async () => ({handled: false})},
    rothLedger: {},
    routeCheckoutSessionCompleted: checkoutRouter.routeCheckoutSessionCompleted,
    logger,
  });
}

async function deliver(processor, stripe, event, webhookSecret) {
  const rawBody = Buffer.from(JSON.stringify(event));
  const signature = stripe.webhooks.generateTestHeaderString({payload: rawBody.toString(), secret: webhookSecret, timestamp: Math.floor(Date.now() / 1000)});
  const first = await processor({rawBody, signature, requestId: `qa-${event.id}`});
  const replay = await processor({rawBody, signature, requestId: `qa-replay-${event.id}`});
  if (first.status !== 200 || replay.status !== 200) throw new Error(`Webhook ${event.type} was not acknowledged.`);
  return {eventId: event.id, first: first.body, replay: replay.body};
}

async function createFixture(db, senderUid) {
  const fixtureId = id("business_gifts_cert");
  const now = Timestamp.now();
  const fixture = {id: fixtureId, isSyntheticQa: true, qaCreatedBy: senderUid, qaCreatedAt: now, expiresAt: Timestamp.fromMillis(now.toMillis() + 6 * 60 * 60 * 1000), archived: false};
  await db.collection(ROOT).doc(fixtureId).create(fixture);
  const qa = scopedDatabase(db, fixture, false, ROOT, EXTRA_COLLECTIONS);
  const businessId = "qa_business";
  await qa.collection("businessAccounts").doc(businessId).set(marker(fixture, {
    businessId, businessName: "CIRCUM TEST Business", companyName: "CIRCUM TEST Business", ownerUid: senderUid,
    teamMemberIds: [senderUid], approvalStatus: "approved", status: "approved", businessStatus: "approved",
    billingEmail: "qa-business@example.invalid", contactEmail: "qa-business@example.invalid",
  }));
  await qa.collection("business_wallets").doc(businessId).set(marker(fixture, {businessId, balance: 1000, availableBalance: 1000, reservedBalance: 0, status: "active"}));
  return {fixture, qa, businessId};
}

function recipient(suffix) {
  return {recipientName: `TEST Recipient ${suffix}`, recipientEmail: "qa-recipient@example.invalid", recipientPhone: "07000000000", deliveryAddress: "QA-only address", deliveryDate: "2099-01-15", deliveryTimeWindow: "09:00-12:00"};
}

async function checkoutAndWebhook({stripe, processor, webhookSecret, db, order, label, createdPaymentIntents}) {
  const session = await stripe.checkout.sessions.retrieve(must(order.checkoutSessionId, `${label} checkout session missing`));
  const reservationId = text(order.checkoutReservationId || session.metadata && session.metadata.checkoutReservationId);
  const reservationSnap = await db.collection("businessCheckoutReservations").doc(reservationId).get();
  const reservation = reservationSnap.data() || {};
  must(reservationId && reservation.externalAmount > 0, `${label} checkout reservation missing`);
  // Checkout Sessions do not receive a PaymentIntent until a browser completes
  // the hosted page. The job is headless, so create the TEST PaymentIntent with
  // the reservation metadata and deliver the canonical completed-session shape.
  const paymentIntent = await stripe.paymentIntents.create({
    amount: reservation.externalAmount,
    currency: GBP,
    payment_method_types: ["card"],
    payment_method: "pm_card_visa",
    confirm: true,
    metadata: session.metadata || {},
  }, {idempotencyKey: `${reservationId}:qa-payment-intent`});
  const paymentIntentId = paymentIntent.id;
  createdPaymentIntents.push(paymentIntentId);
  const successIntentEvent = await waitForEvent(stripe, {type: "payment_intent.succeeded", objectId: paymentIntentId});
  const checkoutEvent = {
    id: id("evt_qa_checkout"), object: "event", livemode: false, type: "checkout.session.completed", created: Math.floor(Date.now() / 1000),
    data: {object: {
      ...session,
      id: session.id,
      status: "complete",
      payment_status: "paid",
      payment_intent: paymentIntentId,
      amount_total: reservation.externalAmount,
      currency: GBP,
      metadata: session.metadata || {},
    }},
  };
  const intentDelivery = await deliver(processor, stripe, successIntentEvent, webhookSecret);
  const checkoutDelivery = await deliver(processor, stripe, checkoutEvent, webhookSecret);
  const orderSnap = await db.collection("businessGiftOrders").doc(order.orderId).get();
  const giftSnap = await db.collection("giftRequests").doc(`business_gift_${order.orderId}`).get();
  if (!orderSnap.exists || orderSnap.data().status !== "paid" || !giftSnap.exists) throw new Error(`${label} did not create one paid Gift.`);
  return {sessionId: session.id, paymentIntentId, successEventId: successIntentEvent.id, checkoutEventId: checkoutEvent.id, checkoutEventSynthetic: true, intentDelivery, checkoutDelivery, giftId: giftSnap.id};
}

async function run() {
  const stripeSecret = must(process.env.CIRCUM_QA_STRIPE_SECRET_KEY, "CIRCUM_QA_STRIPE_SECRET_KEY missing");
  const webhookSecret = must(process.env.STRIPE_WEBHOOK_TEST_SECRET, "STRIPE_WEBHOOK_TEST_SECRET missing");
  if (!stripeSecret.startsWith("sk_test_")) throw new Error("Certification requires an sk_test_ key.");
  if (!webhookSecret.startsWith("whsec_")) throw new Error("Certification requires a test webhook secret.");
  if (process.env.GCLOUD_PROJECT !== "circum-2797c") throw new Error("Unexpected Firebase project.");
  const credentials = JSON.parse(must(process.env.CIRCUM_QA_CERTIFICATION_CREDENTIALS, "QA credentials missing"));
  const senderUid = must(credentials.identities && credentials.identities.sender && credentials.identities.sender.uid, "QA Sender identity missing");
  const senderEmail = credentials.identities.sender.email || "qa-sender@example.invalid";
  if (!getApps().length) initializeApp({projectId: process.env.GCLOUD_PROJECT});
  const rootDb = getFirestore();
  const {fixture, qa, businessId} = await createFixture(rootDb, senderUid);
  const stripe = new Stripe(stripeSecret, {timeout: 30000, maxNetworkRetries: 1});
  const processor = webhookProcessor({stripe, db: qa, webhookSecret});
  const context = contextFor(senderUid, senderEmail);
  const result = {sourceSha: process.env.CIRCUM_SOURCE_SHA || "unknown", stripeMode: "TEST", fixtureId: fixture.id, noLiveStripeKey: true, noCampaignSend: true};
  const createdSessions = [];
  const createdPaymentIntents = [];
  const createdSubscriptions = [];
  const createdCustomers = [];
  const createdPaymentMethods = [];
  const createdProducts = [];
  try {
    const cardRequest = {businessId, idempotencyKey: `${fixture.id}:card`, budgetGbp: 50, paymentRail: "card", ...recipient("CARD")};
    const cardOrder = await businessGifts.createBusinessGiftOrderHandler(stripe, cardRequest, context, {db: qa});
    const cardReplayOrder = await businessGifts.createBusinessGiftOrderHandler(stripe, cardRequest, context, {db: qa});
    if (cardReplayOrder.orderId !== cardOrder.orderId || cardReplayOrder.idempotent !== true) throw new Error("Business card order idempotency failed.");
    const cardDoc = (await qa.collection("businessGiftOrders").doc(cardOrder.orderId).get()).data();
    createdSessions.push(cardDoc.checkoutSessionId);
    const card = await checkoutAndWebhook({stripe, processor, webhookSecret, db: qa, order: {...cardOrder, checkoutReservationId: cardDoc.checkoutReservationId}, label: "Business card", createdPaymentIntents});
    const cardReplaySnap = await qa.collection("giftRequests").doc(card.giftId).get();
    if (!cardReplaySnap.exists || cardReplaySnap.data().recipientValueVisibility !== "sender_only" || cardReplaySnap.data().recipientPrivacy !== "protected") throw new Error("Business card recipient privacy failed.");
    result.businessCard = {status: "PASS", ...card, orderIdempotentReplay: true};

    const failedOrder = await businessGifts.createBusinessGiftOrderHandler(stripe, {businessId, idempotencyKey: `${fixture.id}:failed`, budgetGbp: 50, paymentRail: "card", ...recipient("FAILED")}, context, {db: qa});
    const failedOrderDoc = (await qa.collection("businessGiftOrders").doc(failedOrder.orderId).get()).data();
    createdSessions.push(failedOrderDoc.checkoutSessionId);
    const failedReservation = (await qa.collection("businessCheckoutReservations").doc(failedOrderDoc.checkoutReservationId).get()).data();
    const failedMetadata = {type: "business_invoice_payment", businessId, invoiceId: failedOrder.invoiceId, checkoutReservationId: failedOrderDoc.checkoutReservationId, qaFixtureId: fixture.id};
    let failedIntent;
    try {
    failedIntent = await stripe.paymentIntents.create({amount: failedReservation.externalAmount, currency: GBP, payment_method_data: {type: "card", card: {number: "4000000000000002", exp_month: 12, exp_year: 2034, cvc: "123"}}, confirm: true, return_url: "https://example.invalid/qa", metadata: failedMetadata}, {idempotencyKey: `${fixture.id}:failed-intent`});
    } catch (error) {
      failedIntent = error.payment_intent;
    }
    let failedEvent;
    try {
      failedEvent = await waitForEvent(stripe, {type: "payment_intent.payment_failed", objectId: failedIntent && failedIntent.id, predicate: (_event, object) => object.metadata && object.metadata.checkoutReservationId === failedOrderDoc.checkoutReservationId});
    } catch (error) {
      if (!failedIntent || !failedIntent.id) throw error;
      failedEvent = {id: id("evt_qa_failed"), object: "event", livemode: false, type: "payment_intent.payment_failed", created: Math.floor(Date.now() / 1000), data: {object: failedIntent}};
    }
    const failedDelivery = await deliver(processor, stripe, failedEvent, webhookSecret);
    const paymentAfterFailure = (await qa.collection("businessInvoicePayments").doc(failedOrderDoc.checkoutReservationId).get()).data();
    if (!paymentAfterFailure || paymentAfterFailure.paymentOutcome !== "failed") throw new Error("Business payment failure did not persist exactly once.");
    const businessFailureEmailQueue = await qa.collection("emailQueue").get();
    result.webhookFailure = {status: "PASS", paymentIntentId: failedEvent.data.object.id, eventId: failedEvent.id, eventSynthetic: !failedEvent.created || failedEvent.id.startsWith("evt_qa_"), replayed: true, paymentOutcome: paymentAfterFailure.paymentOutcome, emailQueueCountBeforeRecurring: businessFailureEmailQueue.size, delivery: failedDelivery};

    const recurringGiftId = `qa_initial_${fixture.id}`;
    const recurringCustomer = await stripe.customers.create({email: senderEmail, metadata: {qaFixtureId: fixture.id, purpose: "gift_recurring"}});
    createdCustomers.push(recurringCustomer.id);
    const recurringPaymentMethod = await stripe.paymentMethods.create({type: "card", card: {token: "tok_visa"}}, {idempotencyKey: `${fixture.id}:recurring-payment-method`});
    await stripe.paymentMethods.attach(recurringPaymentMethod.id, {customer: recurringCustomer.id});
    createdPaymentMethods.push(recurringPaymentMethod.id);
    const initialIntent = await stripe.paymentIntents.create({amount: 5000, currency: GBP, customer: recurringCustomer.id, payment_method: recurringPaymentMethod.id, setup_future_usage: "off_session", confirm: true, return_url: "https://example.invalid/qa", metadata: {qaFixtureId: fixture.id, purpose: "gift_recurring_initial"}}, {idempotencyKey: `${fixture.id}:recurring-initial`});
    createdPaymentIntents.push(initialIntent.id);
    const initialGiftRef = qa.collection("giftRequests").doc(recurringGiftId);
    await initialGiftRef.set(marker(fixture, {giftRequestId: recurringGiftId, giftId: recurringGiftId, senderId: senderUid, senderEmail, giftMode: "gift_myself", selfGiftFrequency: "monthly", grossGiftBudget: 50, cardAmount: 50, remainingStripeAmountGbp: 50, deliveryDate: Timestamp.fromDate(new Date(Date.now() + 3 * 24 * 60 * 60 * 1000)), deliveryTimeWindow: "09:00-12:00", recurringConsentAccepted: true, recurringConsentCopy: "QA consent", paidAt: Timestamp.now(), paymentStatus: "paid", recipientPrivacy: "protected", recipientValueVisibility: "sender_only"}));
    const recurring = await giftRecurring.ensureSeriesAfterInitialPayment({db: qa, stripe, giftId: recurringGiftId, payment: {customerId: recurringCustomer.id, paymentIntentId: initialIntent.id, paymentMethodId: recurringPaymentMethod.id}, eventId: `qa-${initialIntent.id}`});
    createdSubscriptions.push(recurring.stripeSubscriptionId);
    const recurringCreatedEvent = await waitForEvent(stripe, {type: "customer.subscription.created", objectId: recurring.stripeSubscriptionId});
    const recurringCreatedDelivery = await deliver(processor, stripe, recurringCreatedEvent, webhookSecret);
    const canceledSubscription = await stripe.subscriptions.update(recurring.stripeSubscriptionId, {cancel_at_period_end: true}, {idempotencyKey: `${fixture.id}:cancel`});
    const recurringCanceledEvent = await waitForEvent(stripe, {type: "customer.subscription.updated", objectId: canceledSubscription.id, predicate: (_event, object) => object.cancel_at_period_end === true});
    const recurringCanceledDelivery = await deliver(processor, stripe, recurringCanceledEvent, webhookSecret);
    const series = (await qa.collection("giftRecurringSeries").doc(recurring.seriesId).get()).data();
    const queuedAfterCancel = await qa.collection("emailQueue").get();
    if (!series || series.cancellationState !== "pending_period_end" || queuedAfterCancel.size !== 1) throw new Error("Recurring cancellation/idempotency failed.");
    result.recurring = {status: "PASS", subscriptionId: recurring.stripeSubscriptionId, createdEventId: recurringCreatedEvent.id, canceledEventId: recurringCanceledEvent.id, cancellationState: series.cancellationState, emailQueueCountAfterReplay: queuedAfterCancel.size, createdDelivery: recurringCreatedDelivery, canceledDelivery: recurringCanceledDelivery};

    const failureSeriesId = `qa_failure_series_${fixture.id}`;
    const failureCustomer = await stripe.customers.create({email: senderEmail, metadata: {qaFixtureId: fixture.id, purpose: "gift_recurring_failure"}});
    createdCustomers.push(failureCustomer.id);
    const failureProduct = await stripe.products.create({name: "CIRCUM QA recurring failure", metadata: {qaFixtureId: fixture.id, purpose: "gift_recurring_failure"}}, {idempotencyKey: `${fixture.id}:failure-product`});
    createdProducts.push(failureProduct.id);
    const failurePaymentMethod = await stripe.paymentMethods.create({type: "card", card: {token: "tok_chargeDeclined"}}, {idempotencyKey: `${fixture.id}:recurring-failure-payment-method`});
    await stripe.paymentMethods.attach(failurePaymentMethod.id, {customer: failureCustomer.id});
    createdPaymentMethods.push(failurePaymentMethod.id);
    const failureSubscription = await stripe.subscriptions.create({customer: failureCustomer.id, items: [{price_data: {currency: GBP, unit_amount: 5000, product: failureProduct.id, recurring: {interval: "month"}}, quantity: 1}], collection_method: "charge_automatically", payment_behavior: "default_incomplete", default_payment_method: failurePaymentMethod.id, metadata: {giftRecurringSeriesId: failureSeriesId, qaFixtureId: fixture.id}}, {idempotencyKey: `${fixture.id}:recurring-failure`});
    createdSubscriptions.push(failureSubscription.id);
    await qa.collection("giftRecurringSeries").doc(failureSeriesId).set(marker(fixture, {id: failureSeriesId, seriesId: failureSeriesId, senderId: senderUid, senderEmail, stripeCustomerId: failureCustomer.id, stripeSubscriptionId: failureSubscription.id, frequency: "monthly", budgetGbp: 50, status: "active", originalDeliveryPattern: {valid: true, dayOfMonth: 15, timezone: "Europe/London", timeWindow: "09:00-12:00"}, nextExpectedRenewalAt: Date.now() + 86400000}));
    if (failureSubscription.latest_invoice) {
      try {
        await stripe.invoices.pay(failureSubscription.latest_invoice, {payment_method: "pm_card_chargeDeclined"});
      } catch (_) {
        // The declined payment is expected for this fixture.
      }
    }
    const recurringFailureEvent = await waitForEvent(stripe, {type: "invoice.payment_failed", predicate: (_event, object) => object.subscription === failureSubscription.id});
    const recurringFailureDelivery = await deliver(processor, stripe, recurringFailureEvent, webhookSecret);
    const failedSeries = (await qa.collection("giftRecurringSeries").doc(failureSeriesId).get()).data();
    const queuedAfterFailure = await qa.collection("emailQueue").get();
    if (!failedSeries || !["past_due", "failed"].includes(failedSeries.status) || queuedAfterFailure.size !== 2) throw new Error("Recurring failure/replay/email idempotency failed.");
    result.recurringFailure = {status: "PASS", subscriptionId: failureSubscription.id, invoiceId: recurringFailureEvent.data.object.id, eventId: recurringFailureEvent.id, seriesStatus: failedSeries.status, emailQueueCountAfterReplay: queuedAfterFailure.size, delivery: recurringFailureDelivery};

    result.status = "PASS";
    console.log(JSON.stringify(result));
  } finally {
    for (const sessionId of createdSessions.filter(Boolean)) {
      try {
        const session = await stripe.checkout.sessions.retrieve(sessionId);
        if (session.status === "open") await stripe.checkout.sessions.expire(session.id);
      } catch (_) {
        // Cleanup is best effort and bounded to this fixture's test object.
      }
    }
    for (const paymentIntentId of createdPaymentIntents.filter(Boolean)) {
      try {
        const intent = await stripe.paymentIntents.retrieve(paymentIntentId);
        if (intent.livemode || intent.currency !== GBP || intent.status !== "succeeded") continue;
        const refunds = await stripe.refunds.list({payment_intent: intent.id, limit: 100});
        const refunded = (refunds.data || []).filter((refund) => refund.status === "succeeded").reduce((sum, refund) => sum + refund.amount, 0);
        if (refunded < intent.amount_received) await stripe.refunds.create({payment_intent: intent.id, amount: intent.amount_received - refunded}, {idempotencyKey: `${fixture.id}:refund:${intent.id}`});
      } catch (_) {
        // Cleanup is best effort and bounded to this fixture's test object.
      }
    }
    for (const subscriptionId of createdSubscriptions.filter(Boolean)) {
      try {
        const subscription = await stripe.subscriptions.retrieve(subscriptionId);
        if (!["canceled", "incomplete_expired"].includes(subscription.status)) await stripe.subscriptions.cancel(subscriptionId);
      } catch (_) {
        // Cleanup is best effort and bounded to this fixture's test object.
      }
    }
    for (const paymentMethodId of createdPaymentMethods.filter(Boolean)) {
      try {
        await stripe.paymentMethods.detach(paymentMethodId);
      } catch (_) {
        // Cleanup is best effort and bounded to this fixture's test object.
      }
    }
    for (const customerId of createdCustomers.filter(Boolean)) {
      try {
        await stripe.customers.del(customerId);
      } catch (_) {
        // Cleanup is best effort and bounded to this fixture's test object.
      }
    }
    for (const productId of createdProducts.filter(Boolean)) {
      try {
        await stripe.products.del(productId);
      } catch (_) {
        // Cleanup is best effort and bounded to this fixture's test object.
      }
    }
    await rootDb.collection(ROOT).doc(fixture.id).set({archived: true, closedAt: Timestamp.now(), cleanup: "stripe_test_objects_refunded_or_canceled"}, {merge: true});
  }
}

run().catch((error) => {
  console.error(JSON.stringify({status: "FAIL", message: error.message || "certification_failed", stack: error.stack || ""}));
  process.exitCode = 1;
});
