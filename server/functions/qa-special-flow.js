/* eslint-disable max-len, require-jsdoc */
"use strict";
const functions = require("firebase-functions/v1");
const {getFirestore, Timestamp, FieldValue} = require("firebase-admin/firestore");
const {createHash} = require("node:crypto");
const {config, authorize, assertFixture, scopedDatabase} = require("./qa-lifecycle")._test;
const {providerForFixture, paymentProviderForFixture} = require("./qa-special-provider");
const qaLifecycle = require("./qa-lifecycle")._test;
const qaPublic = require("./qa-public-delivery");
const health = require("./health-plus")._qaHandlers;
const business = require("./business-payments")._qaHandlers;
const businessReservations = require("./business-checkout-reservations");
const movement = require("./movement-ledger");
const qaRoth = require("./qa-roth-certification");
const {normalizeEmail} = require("./wallet-core");
const irisQa = require("./qa-iris-certification");
const senderBooking = require("./sender-booking")._qa;
const ROOT = "qaSpecialFlowFixtures";
const QA_STRIPE_SECRET = "CIRCUM_QA_STRIPE_SECRET_KEY";
const COLLECTIONS = ["healthPlusProfiles", "prescriptionPickups", "healthPlusPayments", "healthPlusBookingIdempotency", "healthPlusUsageEvents", "healthPlusNotifications", "notifications", "businessAccounts", "businessInvoices", "businessCheckoutReservations", "businessInvoicePayments", "business_wallets", "adminAuditLogs", "wallets", "senderWallets", "walletTransactions", "giftPaymentDrafts", "giftCheckoutOrigins", "giftCheckoutReservations", "giftRequests", "giftPaymentEvents", "giftRecurringSeries", "giftRecurringRenewals", "paymentArtifactReconciliations", "deliveryRequests", "irisPhotoAnalyses"];
const fail = (message, code = "failed-precondition") => {
 throw new functions.https.HttpsError(code, message);
};
const senderActions = new Set(["sender_capability", "sender_quote", "sender_roth_prepare", "sender_roth_balance", "sender_payment_session", "sender_finalize", "sender_read", "sender_cancel"]);
function fixtureIdForRequest(uid, requestId) {
  if (typeof requestId !== "string" || !/^lifecycle_[A-Za-z0-9_-]{1,64}$/.test(requestId)) fail("A bounded QA request ID is required.");
  return createHash("sha256").update(`special-v5:${uid}:${requestId}`).digest("hex");
}
function requiredFixtureId(value) {
  if (typeof value !== "string" || !/^[a-f0-9]{64}$/.test(value)) fail("A valid QA fixture ID is required.");
  return value;
}
function factory({db, env = process.env, stripe}) {
  const provider = (fixture) => providerForFixture({stripe, registry: db.collection(ROOT).doc(fixture.id).collection("qaCheckoutProviderObjects"), fixtureId: fixture.id, secret: env.CIRCUM_QA_STRIPE_SECRET_KEY});
  const paidProvider = (fixture, qa) => paymentProviderForFixture({stripe, qa, fixture, secret: env.CIRCUM_QA_STRIPE_SECRET_KEY});
  const lifecycle = qaLifecycle.factory({db, env, providerFactory: (qa, fixture) => paymentProviderForFixture({stripe, qa, fixture, secret: env.CIRCUM_QA_STRIPE_SECRET_KEY})});
  async function cleanup(fixture) {
    const ref = db.collection(ROOT).doc(fixture.id);
    // Operations may not race cleanup: one lease covers all external effects.
    await db.runTransaction(async (tx) => {
      const s = await tx.get(ref); const current = s.data();
      if (current.leaseUntil && current.leaseUntil > Date.now()) fail("QA operation still running; retry cleanup.");
      tx.update(ref, {closing: true});
    });
    if (fixture.lifecycleFixtureId) await lifecycle.handle({action: "cleanup", fixtureId: fixture.lifecycleFixtureId}, {auth: {uid: fixture.qaCreatedBy, token: {}}, app: {appId: "qa-cleanup"}});
    await qaPublic.cleanup({db, fixture});
    const senderResult = await senderBooking.cleanupQaSenderFixture(db, fixture);
    const testStripe = provider(fixture);
    const result = await testStripe.cleanup();
    const qa = scopedDatabase(db, fixture, true, ROOT, COLLECTIONS);
    const paidResult = await paidProvider(fixture, qa).cleanup();
    const reservations = await qa.collection("businessCheckoutReservations").get();
    for (const snap of reservations.docs) {
      await require("./business-checkout-reservations").terminate({db: qa, stripe: testStripe, reservation: snap.data()});
    }
    await ref.set({archived: true, cleanupResult: result, cleanedAt: Timestamp.now()}, {merge: true});
    return {...result, ...paidResult, sender: senderResult};
  }
  async function activeSenderFixture(uid) {
    const snapshot = await db.collection(ROOT)
        .where("senderId", "==", uid)
        .where("archived", "==", false)
        .limit(2)
        .get();
    const active = snapshot.docs
        .map((doc) => ({id: doc.id, ...doc.data()}))
        .find((fixture) => fixture.isSyntheticQa === true &&
          !fixture.closing && fixture.expiresAt && fixture.expiresAt.toMillis() > Date.now());
    return active || null;
  }
  function senderContext(uid, token = {}) {
    return {auth: {uid, token}, app: {appId: "qa-sender-web"}};
  }
  async function createSenderQuote(fixture, uid, data) {
    const sourceQuoteId = `${data.quoteId || ""}`.trim();
    if (!sourceQuoteId || sourceQuoteId.length > 160) fail("A canonical Sender quote is required.", "invalid-argument");
    const sourceRef = db.collection("senderBookingQuotes").doc(sourceQuoteId);
    const sourceSnap = await sourceRef.get();
    const source = sourceSnap.data();
    if (!sourceSnap.exists || !source || source.userId !== uid) fail("Booking quote not found.", "not-found");
    if (source.isSyntheticQa === true && source.qaFixtureId !== fixture.id) fail("Quote is outside the QA fixture.", "permission-denied");
    if (!source.parcelAuthority) fail("This quote requires a fresh parcel safety check.");
    const quoteId = `qa_sender_${fixture.id.slice(0, 24)}_${createHash("sha256").update(sourceQuoteId).digest("hex").slice(0, 24)}`;
    const marker = {isSyntheticQa: true, qaNamespace: ROOT, qaFixtureId: fixture.id, qaImmutable: true, sourceQuoteId};
    const ref = db.collection("senderBookingQuotes").doc(quoteId);
    const existing = await ref.get();
    if (existing.exists) {
      const current = existing.data() || {};
      if (current.userId !== uid || current.sourceQuoteId !== sourceQuoteId || current.qaFixtureId !== fixture.id) fail("QA quote binding changed.");
    } else {
      await ref.create({...source, ...marker, quoteId, userId: uid, createdAt: Timestamp.now()});
    }
    await db.collection(ROOT).doc(fixture.id).set({
      senderQuoteId: quoteId,
      senderSourceQuoteId: sourceQuoteId,
      senderSourceQuoteCreatedAt: source.createdAt || null,
    }, {merge: true});
    const quote = (await ref.get()).data();
    return {fixtureId: fixture.id, quoteId, amountDue: quote.amountDue || quote.total, currency: quote.currency || "GBP", quote};
  }
  async function handle(data, context) {
    const lists = config(env);
    // Capability discovery is safe for any authenticated, App Check-attested
    // Sender. It must return disabled for ordinary users so their normal Roth
    // balance and live payment path remain available; every mutating QA action
    // still goes through the strict allowlist authorization below.
    if (data && data.action === "sender_capability" && context && context.auth && context.auth.uid && context.app &&
        ![...lists.operators, ...lists.senders, ...lists.riders].includes(context.auth.uid)) {
      return {enabled: false};
    }
    const uid = authorize(context, lists);
    const lifecycleActions = new Set(["book", "pay", "read", "accept", "seed_legacy_status", "publish_location", "start_heading_to_pickup", "arrived_at_pickup", "verify_collection_pin", "confirm_collected", "start_delivery", "near_dropoff", "arrived_at_dropoff", "verify_receiver_pin", "capture_tip", "send_message", "cancel"]);
    if (!data || !["prepare", "health", "health_finalize", "business", "business_finalize", "public_delivery", "roth", "iris", "cleanup"].includes(data.action) && !lifecycleActions.has(data.action) && !senderActions.has(data.action)) fail("Unknown QA action.");
    if (data.action === "sender_capability") {
      if (!lists.senders.includes(uid)) return {enabled: false};
      const active = await activeSenderFixture(uid);
      return active ? {enabled: true, fixtureId: active.id, qaOnly: true, paymentFamily: "sender_delivery"} : {enabled: false};
    }
    if (data.action === "sender_quote") {
      if (!lists.senders.includes(uid)) fail("QA Sender required.", "permission-denied");
      const fixture = await activeSenderFixture(uid);
      if (!fixture) fail("No active QA Sender fixture is available.");
      return createSenderQuote(fixture, uid, data);
    }
    // Fixed participant-scoped identity prevents an operator from accumulating live fixtures.
    if (["prepare", "cleanup"].includes(data.action) && !lists.operators.includes(uid)) fail("QA operator required.", "permission-denied");
    if (["health", "health_finalize", "business", "business_finalize", "public_delivery", "roth", "iris", ...senderActions].includes(data.action) && !lists.senders.includes(uid)) fail("QA Sender required.", "permission-denied");
    const id = data.action === "prepare" ?
      fixtureIdForRequest(uid, data.requestId) : requiredFixtureId(data.fixtureId);
    const ref = db.collection(ROOT).doc(id);
    if (data.action === "prepare") {
      const previous = await ref.get();
      if (previous.exists && previous.data().archived === true) fail("This QA request was archived. Use a new request ID.");
      const created = await lifecycle.handle({action: "create", requestId: `special_v5_${data.requestId}`, senderId: lists.senders[0], riderId: lists.riders[0]}, context);
      await db.runTransaction(async (tx) => {
        const current = await tx.get(ref); if (current.exists) return;
        const now = Timestamp.now();
        tx.create(ref, {id, isSyntheticQa: true, qaCreatedBy: uid, qaCreatedAt: now, senderId: lists.senders[0], riderId: lists.riders[0], lifecycleFixtureId: created.fixtureId, expiresAt: Timestamp.fromMillis(now.toMillis() + 3600000), archived: false});
        tx.create(ref.collection("businessAccounts").doc("qa_business"), {ownerUid: lists.senders[0], isSyntheticQa: true, qaFixtureId: id});
        // An unpaid, fixed synthetic invoice is setup data, not a payment transition.
        tx.create(ref.collection("businessInvoices").doc("qa_invoice"), {businessId: "qa_business", total: 5, balanceDue: 5, amountPaid: 0, status: "issued", checkoutProtocolVersion: 1, isSyntheticQa: true, qaFixtureId: id});
      });
      return {fixtureId: id};
    }
    const fixture = (await ref.get()).data(); assertFixture(fixture, lists, uid, Date.now(), data.action === "cleanup");
    if (data.action === "cleanup") return cleanup(fixture);
    if (senderActions.has(data.action)) {
      if (uid !== fixture.senderId) fail("QA Sender required.", "permission-denied");
      const qaContext = {fixtureId: fixture.id, isSyntheticQa: true};
      if (data.action === "sender_quote") return createSenderQuote(fixture, uid, data);
      if (data.action === "sender_roth_prepare") {
        const email = normalizeEmail(context.auth.token.email);
        if (!email) fail("QA Sender email is required.", "permission-denied");
        const qa = scopedDatabase(db, fixture, false, ROOT, COLLECTIONS);
        return {...await qaRoth.seed({qa, fixture, uid, email}), qaOnly: true, fixtureId: fixture.id};
      }
      if (data.action === "sender_roth_balance") {
        const email = normalizeEmail(context.auth.token.email);
        if (!email) fail("QA Sender email is required.", "permission-denied");
        const qa = scopedDatabase(db, fixture, false, ROOT, COLLECTIONS);
        const wallet = (await qa.collection("wallets").doc(email).get()).data();
        if (!wallet || wallet.uid !== uid || wallet.qaFixtureId !== fixture.id) {
          fail("QA Roth fixture is not prepared.", "failed-precondition");
        }
        return {qaOnly: true, fixtureId: fixture.id, balance: Number(wallet.balance || 0), availableRoth: Number(wallet.balance || 0), currency: "ROTH"};
      }
      if (data.action === "sender_payment_session") {
        const result = await senderBooking.createSenderPaymentSession(
            provider(fixture),
            {...data, quoteId: `${data.quoteId || ""}`, checkoutMode: "web_checkout", returnUrl: "https://circum-2797c.web.app/send"},
            senderContext(uid, context.auth.token),
            {db, qaContext},
        );
        return {...result, qaOnly: true, fixtureId: fixture.id};
      }
      if (data.action === "sender_finalize") {
        const paymentSessionId = `${data.paymentSessionId || ""}`;
        const checkoutSessionId = `${data.checkoutSessionId || ""}`;
        if (!paymentSessionId || !checkoutSessionId) fail("Confirmed QA checkout is required.", "invalid-argument");
        const session = await provider(fixture).checkout.sessions.retrieve(checkoutSessionId);
        if (`${session.metadata && session.metadata.paymentSessionId || ""}` !== paymentSessionId) {
          fail("QA checkout does not match the payment session.", "permission-denied");
        }
        const result = await senderBooking.finalizeSenderCheckoutSession(
            provider(fixture),
            session,
            `qa_${paymentSessionId}`,
            {db, qaContext},
        );
        return {...result, qaOnly: true, fixtureId: fixture.id};
      }
      if (data.action === "sender_read") {
        const deliveryId = `${data.deliveryId || ""}`;
        const snapshot = await db.collection("deliveryRequests").doc(deliveryId).get();
        if (!snapshot.exists || snapshot.data().qaFixtureId !== fixture.id || snapshot.data().isSyntheticQa !== true) fail("QA delivery not found.", "not-found");
        return {qaOnly: true, fixtureId: fixture.id, delivery: {id: snapshot.id, ...snapshot.data()}};
      }
      if (data.action === "sender_cancel") {
        const deliveryId = `${data.deliveryId || ""}`;
        const ref = db.collection("deliveryRequests").doc(deliveryId);
        const snapshot = await ref.get();
        if (!snapshot.exists || snapshot.data().qaFixtureId !== fixture.id || snapshot.data().isSyntheticQa !== true) fail("QA delivery not found.", "not-found");
        await ref.set({status: "cancelled", deliveryStatus: "cancelled", dispatchStatus: "suppressed_qa", cancellationReason: "qa_cleanup", updatedAt: Timestamp.now()}, {merge: true});
        return {qaOnly: true, cancelled: true, deliveryId};
      }
    }
    if (data.action === "public_delivery") {
      if (uid !== fixture.senderId) fail("QA Sender required.", "permission-denied");
      return qaPublic.createPublicDelivery({db, fixture, actorUid: uid});
    }
    if (lifecycleActions.has(data.action)) {
      const payload = {...data, fixtureId: fixture.lifecycleFixtureId}; delete payload.profileOverride;
      if (data.action !== "publish_location") delete payload.status;
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
      if (data.action === "roth") {
        if (!qaRoth.ACTIONS.has(data.scenario)) fail("Unknown QA Roth scenario.", "invalid-argument");
        const email = context.auth.token.email;
        if (typeof email !== "string" || !email.includes("@")) fail("QA Sender email is required.", "permission-denied");
        const args = {qa, fixture, uid, email, stripe: actual};
        if (data.scenario === "prepare") return qaRoth.seed(args);
        if (data.scenario === "roth_only" || data.scenario === "split") return qaRoth.pay({...args, type: data.scenario});
        if (data.scenario === "insufficient") return qaRoth.insufficient(args);
        if (data.scenario === "read") return qaRoth.read(args);
        return qaRoth.reconcile(args);
      }
      if (data.action === "iris") {
        if (typeof data.scenario !== "string" || !Object.hasOwn(irisQa.SCENARIOS, data.scenario)) fail("Unknown synthetic IRIS scenario.", "invalid-argument");
        const result = irisQa.analyse({uid, scenario: data.scenario});
        if (!result.photo) return result;
        const photoRef = qa.collection("irisPhotoAnalyses").doc(result.photo.analysisId);
        const idempotent = await qa.runTransaction(async (tx) => {
          const existing = await tx.get(photoRef);
          if (!existing.exists) tx.create(photoRef, {...result.photo, createdAt: FieldValue.serverTimestamp(), expiresAt: Timestamp.fromMillis(Date.now() + 24 * 60 * 60 * 1000)});
          return existing.exists;
        });
        const safePhoto = {...result.photo};
        delete safePhoto.imageHash; delete safePhoto.descriptionHash;
        return {scenario: result.scenario, iris: result.iris, photo: safePhoto, idempotent};
      }
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
  const secret = process.env.CIRCUM_QA_STRIPE_SECRET_KEY;
  if (!secret || !secret.startsWith("sk_test_")) fail("TEST provider required.");
  return factory({db: getFirestore(), stripe: require("stripe")(secret, {timeout: 20000, maxNetworkRetries: 1})});
}
exports.callable = () => functions.runWith({enforceAppCheck: true, timeoutSeconds: 180, secrets: [QA_STRIPE_SECRET, "GOOGLE_MAPS_DIRECTIONS_API_KEY"]}).https.onCall((data, context) => instance().handle(data, context));
exports.scheduled = () => functions.runWith({timeoutSeconds: 180, secrets: [QA_STRIPE_SECRET]}).pubsub.schedule("every 10 minutes").onRun(() => instance().expire());
exports._test = {factory, fixtureIdForRequest, requiredFixtureId};
