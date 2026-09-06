/* eslint-disable max-len, require-jsdoc */
"use strict";
const functions = require("firebase-functions/v1");
const {getFirestore, Timestamp, FieldValue} = require("firebase-admin/firestore");
const {createHash} = require("node:crypto");
const {config, authorize, assertFixture, scopedDatabase} = require("./qa-lifecycle")._test;
const {providerForFixture, paymentProviderForFixture} = require("./qa-special-provider");
const qaLifecycle = require("./qa-lifecycle")._test;
const health = require("./health-plus")._qaHandlers;
const business = require("./business-payments")._qaHandlers;
const businessReservations = require("./business-checkout-reservations");
const movement = require("./movement-ledger");
const ROOT = "qaSpecialFlowFixtures";
const COLLECTIONS = ["healthPlusProfiles", "prescriptionPickups", "healthPlusPayments", "healthPlusBookingIdempotency", "healthPlusUsageEvents", "healthPlusNotifications", "notifications", "businessAccounts", "businessInvoices", "businessCheckoutReservations", "businessInvoicePayments", "business_wallets", "adminAuditLogs", "wallets", "paymentArtifactReconciliations", "deliveryRequests"];
const fail = (message) => {
throw new functions.https.HttpsError("failed-precondition", message);
};
function factory({db, env = process.env, stripe}) {
  const provider = (fixture) => providerForFixture({stripe, registry: db.collection(ROOT).doc(fixture.id).collection("qaCheckoutProviderObjects"), fixtureId: fixture.id, secret: env.STRIPE_SECRET_KEY});
  const paidProvider = (fixture, qa) => paymentProviderForFixture({stripe, qa, fixture, secret: env.STRIPE_SECRET_KEY});
  const lifecycle = qaLifecycle.factory({db, env, providerFactory: (qa, fixture) => paymentProviderForFixture({stripe, qa, fixture, secret: env.STRIPE_SECRET_KEY})});
  async function cleanup(fixture) {
    const ref = db.collection(ROOT).doc(fixture.id);
    // Operations may not race cleanup: one lease covers all external effects.
    await db.runTransaction(async (tx) => {
      const s = await tx.get(ref); const current = s.data();
      if (current.leaseUntil && current.leaseUntil > Date.now()) fail("QA operation still running; retry cleanup.");
      tx.update(ref, {closing: true});
    });
    if (fixture.lifecycleFixtureId) await lifecycle.handle({action: "cleanup", fixtureId: fixture.lifecycleFixtureId}, {auth: {uid: fixture.qaCreatedBy, token: {}}, app: {appId: "qa-cleanup"}});
    const testStripe = provider(fixture);
    const result = await testStripe.cleanup();
    const qa = scopedDatabase(db, fixture, true, ROOT, COLLECTIONS);
    const paidResult = await paidProvider(fixture, qa).cleanup();
    const reservations = await qa.collection("businessCheckoutReservations").get();
    for (const snap of reservations.docs) {
      await require("./business-checkout-reservations").terminate({db: qa, stripe: testStripe, reservation: snap.data()});
    }
    await ref.set({archived: true, cleanupResult: result, cleanedAt: Timestamp.now()}, {merge: true});
    return {...result, ...paidResult};
  }
  async function handle(data, context) {
    const lists = config(env); const uid = authorize(context, lists);
    const lifecycleActions = new Set(["book", "pay", "read", "accept", "start_heading_to_pickup", "arrived_at_pickup", "verify_collection_pin", "confirm_collected", "start_delivery", "near_dropoff", "arrived_at_dropoff", "capture_tip", "send_message", "cancel"]);
    if (!data || !["prepare", "health", "health_finalize", "business", "business_finalize", "cleanup"].includes(data.action) && !lifecycleActions.has(data.action)) fail("Unknown QA action.");
    // Fixed participant-scoped identity prevents an operator from accumulating live fixtures.
    if (["prepare", "health", "health_finalize", "business", "business_finalize", "cleanup"].includes(data.action) && (!lists.operators.includes(uid) || !lists.senders.includes(uid))) fail("QA Sender operator required.");
    const id = createHash("sha256").update(`special-v2:${lists.operators[0]}`).digest("hex");
    const ref = db.collection(ROOT).doc(id);
    if (data.action === "prepare") {
      const created = await lifecycle.handle({action: "create", requestId: `special_v2_${lists.operators[0]}`, senderId: lists.senders[0], riderId: lists.riders[0]}, context);
      await db.runTransaction(async (tx) => {
        const current = await tx.get(ref); if (current.exists) return;
        const now = Timestamp.now();
        tx.create(ref, {id, isSyntheticQa: true, qaCreatedBy: uid, qaCreatedAt: now, senderId: uid, riderId: lists.riders[0], lifecycleFixtureId: created.fixtureId, expiresAt: Timestamp.fromMillis(now.toMillis() + 3600000), archived: false});
        tx.create(ref.collection("businessAccounts").doc("qa_business"), {ownerUid: uid, isSyntheticQa: true, qaFixtureId: id});
        // An unpaid, fixed synthetic invoice is setup data, not a payment transition.
        tx.create(ref.collection("businessInvoices").doc("qa_invoice"), {businessId: "qa_business", total: 5, balanceDue: 5, amountPaid: 0, status: "issued", checkoutProtocolVersion: 1, isSyntheticQa: true, qaFixtureId: id});
      });
      return {fixtureId: id};
    }
    const fixture = (await ref.get()).data(); assertFixture(fixture, lists, uid, Date.now(), data.action === "cleanup");
    if (data.action === "cleanup") return cleanup(fixture);
    if (lifecycleActions.has(data.action)) {
      const payload = {...data, fixtureId: fixture.lifecycleFixtureId}; delete payload.profileOverride; delete payload.status;
      return lifecycle.handle(payload, context);
    }
    const leaseId = require("node:crypto").randomUUID();
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref); const current = snap.data();
      assertFixture(current, lists, uid);
      if (current.leaseUntil > Date.now()) fail("QA operation in progress; retry.");
      tx.update(ref, {leaseId, leaseUntil: Date.now() + 300000});
    });
    try {
      const qa = scopedDatabase(db, fixture, false, ROOT, COLLECTIONS); const testStripe = provider(fixture);
      const actual = paidProvider(fixture, qa);
      if (data.action === "health_finalize") {
        const payments = await qa.collection("healthPlusPayments").limit(2).get();
        if (payments.size !== 1) fail("One canonical Health+ checkout is required.");
        const payment = payments.docs[0].data(); const bookingId = payments.docs[0].id;
        const deliveryId = `health_${bookingId}`;
        await qa.doc(`deliveryRequests/${deliveryId}`).set({deliveryId, senderId: fixture.senderId, status: "booked", paymentStatus: "unpaid", serviceType: "health_plus", isSyntheticQa: true, qaFixtureId: fixture.id}, {merge: true});
        const intent = await actual.paymentIntents.create({amount: Math.round(payment.cardAmount * 100), currency: "gbp", payment_method: "pm_card_visa", payment_method_types: ["card"], confirm: true, metadata: {isSyntheticQa: "true", qaFixtureId: fixture.id, deliveryId, paymentType: "health_plus_payment"}}, {idempotencyKey: `health_${bookingId}`});
        const session = {id: payment.checkoutSessionId, livemode: false, payment_status: "paid", status: "complete", amount_total: intent.amount_received, currency: "gbp", payment_intent: intent.id, metadata: {bookingId, profileId: payment.profileId, userId: payment.senderId, userEmail: payment.userEmail || ""}};
        await health.handleHealthPlusCheckoutSessionHandler(session, `qa_${intent.id}`, {db: qa});
        const pickup = (await qa.doc(`prescriptionPickups/${bookingId}`).get()).data();
        await movement.projectHealth(qa, bookingId, pickup);
        await qa.doc(`deliveryRequests/${deliveryId}`).set({profileId: FieldValue.delete()}, {merge: true});
        return {paid: true, providerId: intent.id, deliveryId, amountPence: intent.amount_received};
      }
      if (data.action === "business") {
        const result = await business.createBusinessInvoiceCheckoutHandler(testStripe, {invoiceId: "qa_invoice", businessId: "qa_business", useRoth: false}, context, {db: qa});
        return {fixtureId: id, sessionId: result.sessionId, reservationId: result.checkoutReservationId, cardAmount: result.cardAmount, rothApplied: result.rothApplied};
      }
      if (data.action === "business_finalize") {
        const reservations = await qa.collection("businessCheckoutReservations").limit(2).get();
        if (reservations.size !== 1) fail("One canonical Business checkout is required.");
        const reservation = reservations.docs[0].data(); const deliveryId = "business_qa_invoice";
        await qa.doc(`deliveryRequests/${deliveryId}`).set({deliveryId, senderId: fixture.senderId, status: "booked", paymentStatus: "unpaid", serviceType: "business", isBusiness: true, businessMode: true, trustPointsAwarded: 3, pickupAddress: "Synthetic QA Business pickup", dropoffAddress: "Synthetic QA Business dropoff", routeDistanceMetres: 2400, routeDurationSeconds: 720}, {merge: true});
        const intent = await actual.paymentIntents.create({amount: reservation.externalAmount, currency: "gbp", payment_method: "pm_card_visa", payment_method_types: ["card"], confirm: true, metadata: {isSyntheticQa: "true", qaFixtureId: fixture.id, deliveryId, paymentType: "business_invoice_payment"}}, {idempotencyKey: `business_${reservation.checkoutReservationId}`});
        const session = {id: reservation.providerSessionId, livemode: false, payment_status: "paid", status: "complete", amount_total: intent.amount_received, currency: "gbp", payment_intent: intent.id, metadata: {type: "business_invoice_payment", checkoutReservationId: reservation.checkoutReservationId, invoiceId: reservation.invoiceId, businessId: reservation.businessId}};
        await businessReservations.settle({db: qa, session, id: reservation.checkoutReservationId});
        await qa.doc(`deliveryRequests/${deliveryId}`).set({status: "requested", paymentStatus: "paid", stripePaymentIntentId: intent.id}, {merge: true});
        return {paid: true, providerId: intent.id, deliveryId, amountPence: intent.amount_received};
      }
      const booking = await health.createHealthPlusBookingHandler({
        consentConfirmed: true, fullName: "Synthetic QA", email: context.auth.token.email, phoneNumber: "07000000000",
        pharmacyAddress: "10 Downing Street, London SW1A 2AA", deliveryAddress: "Trafalgar Square, London WC2N 5DN", preferredPickupTime: "12:00", frequency: "one_off",
        pricingInputs: {medicationWeightKg: 0.5}, subscriptionPlan: "priority", idempotencyKey: `qa_health_${id}`,
      }, context, {db: qa});
      let code = 200; let body;
      const res = {set() {
return this;
}, setHeader() {}, status(value) {
code = value; return this;
}, send(value) {
body = value; return this;
}, json(value) {
body = value; return this;
}};
      await health.createHealthPlusCheckoutHandler({method: "POST", headers: context.rawRequest.headers, body: {bookingId: booking.pickupId, profileId: booking.profileId, useRoth: false}}, res, {db: qa, stripe: testStripe});
      if (code !== 200) fail(`Canonical QA checkout rejected (${code}).`);
      const payment = (await qa.doc(`healthPlusPayments/${booking.pickupId}`).get()).data();
      return {fixtureId: id, bookingId: booking.pickupId, amountPence: booking.amountPence, sessionId: payment.checkoutSessionId || body.sessionId, routeAuthority: (await qa.doc(`prescriptionPickups/${booking.pickupId}`).get()).data().routeAuthorityVersion};
    } finally {
      await db.runTransaction(async (tx) => {
        const snap = await tx.get(ref); if (snap.data().leaseId === leaseId) tx.update(ref, {leaseUntil: 0});
      });
    }
  }
  async function expire() {
    config(env);
    const all = await db.collection(ROOT).where("archived", "==", false).get();
    const results = [];
    for (const doc of all.docs) {
if (doc.data().expiresAt.toMillis() <= Date.now()) {
      try {
results.push(await cleanup(doc.data()));
} catch (error) {
console.error("QA cleanup remains pending", {fixtureId: doc.id, message: error.message});
}
    }
}
    return {processed: results.length};
  }
  return {handle, expire};
}
function instance() {
  const secret = process.env.STRIPE_SECRET_KEY;
  if (!secret || !secret.startsWith("sk_test_")) fail("TEST provider required.");
  return factory({db: getFirestore(), stripe: require("stripe")(secret, {timeout: 20000, maxNetworkRetries: 1})});
}
exports.callable = () => functions.runWith({enforceAppCheck: true, timeoutSeconds: 180, secrets: ["STRIPE_SECRET_KEY", "GOOGLE_MAPS_DIRECTIONS_API_KEY"]}).https.onCall((data, context) => instance().handle(data, context));
exports.scheduled = () => functions.runWith({timeoutSeconds: 180, secrets: ["STRIPE_SECRET_KEY"]}).pubsub.schedule("every 10 minutes").onRun(() => instance().expire());
exports._test = {factory};
