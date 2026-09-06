/* eslint-disable max-len, require-jsdoc */
"use strict";
const functions = require("firebase-functions/v1");
const {getFirestore, Timestamp} = require("firebase-admin/firestore");
const {createHash} = require("node:crypto");
const {config, authorize, assertFixture, scopedDatabase} = require("./qa-lifecycle")._test;
const {providerForFixture} = require("./qa-special-provider");
const health = require("./health-plus")._qaHandlers;
const business = require("./business-payments")._qaHandlers;
const ROOT = "qaSpecialFlowFixtures";
const COLLECTIONS = ["healthPlusProfiles", "prescriptionPickups", "healthPlusPayments", "healthPlusBookingIdempotency", "healthPlusUsageEvents", "healthPlusNotifications", "notifications", "businessAccounts", "businessInvoices", "businessCheckoutReservations", "businessInvoicePayments", "business_wallets", "adminAuditLogs", "wallets", "paymentArtifactReconciliations"];
const fail = (message) => {
throw new functions.https.HttpsError("failed-precondition", message);
};
function factory({db, env = process.env, stripe}) {
  const provider = (fixture) => providerForFixture({stripe, registry: db.collection(ROOT).doc(fixture.id).collection("qaProviderObjects"), fixtureId: fixture.id, secret: env.STRIPE_SECRET_KEY});
  async function cleanup(fixture) {
    const ref = db.collection(ROOT).doc(fixture.id);
    // Operations may not race cleanup: one lease covers all external effects.
    await db.runTransaction(async (tx) => {
      const s = await tx.get(ref); const current = s.data();
      if (current.leaseUntil && current.leaseUntil > Date.now()) fail("QA operation still running; retry cleanup.");
      tx.update(ref, {closing: true});
    });
    const testStripe = provider(fixture);
    const result = await testStripe.cleanup();
    const qa = scopedDatabase(db, fixture, true, ROOT, COLLECTIONS);
    const reservations = await qa.collection("businessCheckoutReservations").get();
    for (const snap of reservations.docs) {
      await require("./business-checkout-reservations").terminate({db: qa, stripe: testStripe, reservation: snap.data()});
    }
    await ref.set({archived: true, cleanupResult: result, cleanedAt: Timestamp.now()}, {merge: true});
    return result;
  }
  async function handle(data, context) {
    const lists = config(env); const uid = authorize(context, lists);
    if (!data || !["prepare", "health", "business", "cleanup"].includes(data.action)) fail("Unknown QA action.");
    // Fixed participant-scoped identity prevents an operator from accumulating live fixtures.
    if (!lists.operators.includes(uid) || !lists.senders.includes(uid)) fail("QA Sender operator required.");
    const id = createHash("sha256").update(`special-v1:${uid}`).digest("hex");
    const ref = db.collection(ROOT).doc(id);
    if (data.action === "prepare") {
      await db.runTransaction(async (tx) => {
        const current = await tx.get(ref); if (current.exists) return;
        const now = Timestamp.now();
        tx.create(ref, {id, isSyntheticQa: true, qaCreatedBy: uid, qaCreatedAt: now, senderId: uid, riderId: lists.riders[0], expiresAt: Timestamp.fromMillis(now.toMillis() + 3600000), archived: false});
        tx.create(ref.collection("businessAccounts").doc("qa_business"), {ownerUid: uid, isSyntheticQa: true, qaFixtureId: id});
        // An unpaid, fixed synthetic invoice is setup data, not a payment transition.
        tx.create(ref.collection("businessInvoices").doc("qa_invoice"), {businessId: "qa_business", total: 5, balanceDue: 5, amountPaid: 0, status: "issued", checkoutProtocolVersion: 1, isSyntheticQa: true, qaFixtureId: id});
      });
      return {fixtureId: id};
    }
    const fixture = (await ref.get()).data(); assertFixture(fixture, lists, uid, Date.now(), data.action === "cleanup");
    if (data.action === "cleanup") return cleanup(fixture);
    const leaseId = require("node:crypto").randomUUID();
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref); const current = snap.data();
      assertFixture(current, lists, uid);
      if (current.leaseUntil > Date.now()) fail("QA operation in progress; retry.");
      tx.update(ref, {leaseId, leaseUntil: Date.now() + 300000});
    });
    try {
      const qa = scopedDatabase(db, fixture, false, ROOT, COLLECTIONS); const testStripe = provider(fixture);
      if (data.action === "business") {
        const result = await business.createBusinessInvoiceCheckoutHandler(testStripe, {invoiceId: "qa_invoice", businessId: "qa_business", useRoth: false}, context, {db: qa});
        return {fixtureId: id, sessionId: result.sessionId, reservationId: result.checkoutReservationId, cardAmount: result.cardAmount, rothApplied: result.rothApplied};
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
