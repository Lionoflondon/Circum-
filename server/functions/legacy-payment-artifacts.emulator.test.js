/* eslint-disable max-len, require-jsdoc */
const {test, before, after} = require("node:test");
const assert = require("node:assert/strict");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const legacy = require("./legacy-payment-artifacts");
const health = require("./health-checkout-authority");
const enabled = Boolean(process.env.FIRESTORE_EMULATOR_HOST);
let app;
let db;
before(() => {
  if (enabled) {
    app = initializeApp({projectId: "demo-legacy-payments"});
    db = getFirestore();
  }
});
after(async () => {
  if (app) await deleteApp(app);
});
function provider(rows = []) {
  const sessions = new Map(rows.map((r) => [r.id, r]));
  const keys = new Map();
  let creates = 0;
  let ambiguous = false;
  return {
    sessions,
    keys,
    creates: () => creates,
    failNext: () => {
      ambiguous = true;
    },
    checkout: {
      sessions: {
        list: async () => ({data: [...sessions.values()], has_more: false}),
        retrieve: async (id) => sessions.get(id),
        expire: async (id) => {
          const s = sessions.get(id);
          s.status = "expired";
          return s;
        },
        create: async (params, {idempotencyKey}) => {
          if (keys.has(idempotencyKey)) {
            assert.deepEqual(keys.get(idempotencyKey).params, params);
            return keys.get(idempotencyKey).session;
          }
          const session = {
            id: `new_${++creates}`,
            status: "open",
            payment_status: "unpaid",
            url: "https://example.invalid",
            metadata: params.metadata,
          };
          keys.set(idempotencyKey, {params, session});
          sessions.set(session.id, session);
          if (ambiguous) {
            ambiguous = false;
            throw new Error("network timeout");
          }
          return session;
        },
      },
    },
    paymentIntents: {
      retrieve: async () => ({
        id: "pi_legacy",
        status: "requires_payment_method",
      }),
      cancel: async () => ({status: "canceled"}),
    },
  };
}
test(
  "legacy Health checkout discovers orphan session, expires it and requires fresh booking",
  {skip: !enabled},
  async () => {
    const stripe = provider([
      {
        id: "old",
        status: "open",
        payment_status: "unpaid",
        metadata: {type: "health_plus_payment", bookingId: "health-old"},
      },
    ]);
    await assert.rejects(
      health.legacyGate({
        stripe,
        db,
        bookingId: "health-old",
        booking: {},
        payment: {},
      }),
      /fresh route price/,
    );
    assert.equal(stripe.sessions.get("old").status, "expired");
    assert.equal(stripe.creates(), 0);
    assert.equal(
      (await db.doc("prescriptionPickups/health-old").get()).data()
        .paymentRegenerationRequired,
      true,
    );
  },
);
test(
  "paid legacy Health session cannot be silently replaced or dispatched",
  {skip: !enabled},
  async () => {
    const stripe = provider([
      {
        id: "paid",
        status: "complete",
        payment_status: "paid",
        metadata: {type: "health_plus_payment", bookingId: "health-paid"},
      },
    ]);
    await assert.rejects(
      health.legacyGate({
        stripe,
        db,
        bookingId: "health-paid",
        booking: {},
        payment: {checkoutSessionId: "paid"},
      }),
      /reconciliation/,
    );
    assert.equal(
      (
        await db.doc("paymentArtifactReconciliations/health_health-paid").get()
      ).data().status,
      "review_required",
    );
    assert.equal(stripe.creates(), 0);
  },
);
test(
  "Health regeneration freezes price/split/provider parameters across concurrent retries and ambiguous failure",
  {skip: !enabled},
  async () => {
    const paymentRef = db.doc("healthPlusPayments/fresh");
    const booking = {routeAuthorityVersion: 2, senderId: "sender", profileId: "profile", pharmacyAddress: "Pharmacy", deliveryAddress: "Home", status: "scheduled", pricingInputs: {distanceMiles: 2, medicationWeightKg: 1}};
    await db.doc("prescriptionPickups/fresh").set(booking);
    const stripe = provider();
    const authorities = await Promise.all(
      [1, 2, 3].map((n) =>
        health.reserve({
          booking,
          db,
          paymentRef,
          candidate: {amountPence: n * 1000, rothAmount: n, cardAmount: n * 9},
        }),
      ),
    );
    assert.deepEqual(authorities[0], authorities[1]);
    assert.deepEqual(authorities[1], authorities[2]);
    const params = {
      mode: "payment",
      expires_at: authorities[0].expiresAt,
      metadata: {bookingId: "fresh"},
      amount: authorities[0].amountPence,
    };
    stripe.failNext();
    await assert.rejects(
      health.create({
        booking,
        db,
        stripe,
        paymentRef,
        params,
        record: {status: "pending_verification"},
      }),
      /timeout/,
    );
    const result = await Promise.all(
      [1, 2, 3].map((n) =>
        health.create({
          booking,
          db,
          stripe,
          paymentRef,
          params: {...params, success_url: `https://example.invalid/${n}`},
          record: {status: "pending_verification"},
        }),
      ),
    );
    assert.equal(new Set(result.map((r) => r.id)).size, 1);
    assert.equal(stripe.creates(), 1);
    assert.deepEqual([...stripe.keys.values()][0].params, params);
  },
);
test(
  "Sender quote missing parcel authority expires payable artifacts before requiring regeneration",
  {skip: !enabled},
  async () => {
    const stripe = provider([
      {
        id: "sender-old",
        status: "open",
        payment_status: "unpaid",
        metadata: {quoteId: "old", userId: "sender"},
      },
    ]);
    await db
      .doc("senderPaymentSessions/old")
      .set({stripePaymentIntentId: "pi_legacy"});
    await assert.rejects(
      legacy.rejectLegacySenderQuote({
        db,
        stripe,
        quote: {},
        quoteId: "old",
        senderId: "sender",
      }),
      /new parcel safety check/,
    );
    assert.equal(stripe.sessions.get("sender-old").status, "expired");
    assert.equal(
      (await db.doc("senderBookingQuotes/old").get()).data()
        .paymentRegenerationRequired,
      true,
    );
    await legacy.rejectLegacySenderQuote({
      db,
      stripe: null,
      quote: {parcelAuthority: {weightKg: 1}},
      quoteId: "new",
      senderId: "sender",
    });
  },
);
test(
  "already-paid legacy Sender quote is held for reconciliation without another charge",
  {skip: !enabled},
  async () => {
    await db
      .doc("senderPaymentSessions/paid")
      .set({paymentStatus: "succeeded"});
    const stripe = provider();
    await assert.rejects(
      legacy.rejectLegacySenderQuote({
        db,
        stripe,
        quote: {},
        quoteId: "paid",
        senderId: "sender",
      }),
      /reconciliation/,
    );
    assert.equal(
      (await db.doc("paymentArtifactReconciliations/sender_paid").get()).data()
        .status,
      "review_required",
    );
    assert.equal(stripe.creates(), 0);
  },
);
