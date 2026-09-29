/* eslint-disable max-len, require-jsdoc */
"use strict";

const {test, before, after} = require("node:test");
const assert = require("node:assert/strict");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");

const enabled = !!process.env.FIRESTORE_EMULATOR_HOST;
let app;
let db;

before(() => {
  if (enabled) {
    app = initializeApp({projectId: "circum-2797c"});
    db = getFirestore();
  }
});

after(async () => {
  if (app) await deleteApp(app);
});

test("Sender QA Web payment reuses canonical checkout/finalization and is idempotent", {skip: !enabled}, async () => {
  const objects = new Map();
  let sequence = 0;
  const stripe = {
    checkout: {
      sessions: {
        async create(params, options) {
          const existing = objects.get(options.idempotencyKey);
          if (existing) return existing;
          const object = {
            id: `cs_test_sender_${++sequence}`,
            url: `https://checkout.stripe.com/c/pay/cs_test_sender_${sequence}`,
            livemode: false,
            amount_total: params.line_items[0].price_data.unit_amount,
            currency: "gbp",
            payment_status: "unpaid",
            status: "open",
            metadata: params.metadata,
          };
          assert.ok(params.success_url.startsWith("https://circum-app-2797c.web.app/?sender_payment=success&"));
          assert.ok(params.cancel_url.startsWith("https://circum-app-2797c.web.app/?sender_payment=cancelled&"));
          objects.set(options.idempotencyKey, object);
          return object;
        },
        async retrieve(id) {
          return [...objects.values()].find((object) => object.id === id);
        },
        async expire(id) {
          const object = await this.retrieve(id);
          object.status = "expired";
          return object;
        },
      },
    },
    paymentIntents: {
      async retrieve(id) {
        const checkout = [...objects.values()].find((object) => object.payment_intent === id);
        return {id, livemode: false, currency: "gbp", amount_received: checkout.amount_total, metadata: checkout.metadata};
      },
    },
    refunds: {
      async list() { return {data: []}; },
      async create(params) { return {id: "re_test_sender", status: "succeeded", ...params}; },
    },
  };
  const env = {
    GCLOUD_PROJECT: "circum-2797c",
    STRIPE_MODE: "TEST",
    CIRCUM_QA_STRIPE_SECRET_KEY: "sk_test_sender_fixture",
    QA_LIFECYCLE_ENABLED: "true",
    QA_LIFECYCLE_ALLOWLIST: JSON.stringify({
      operators: ["qa_operator"],
      senders: ["qa_sender"],
      riders: ["qa_rider"],
    }),
  };
  const flow = require("./qa-special-flow")._test.factory({db, env, stripe});
  const operator = {auth: {uid: "qa_operator", token: {email: "operator@example.invalid"}}, app: {appId: "qa"}};
  const sender = {auth: {uid: "qa_sender", token: {email: "sender@example.invalid", name: "QA Sender"}}, app: {appId: "qa"}};
  const prepared = await flow.handle({action: "prepare", requestId: "lifecycle_sender_payment"}, operator);
  const fixtureId = prepared.fixtureId;
  await db.collection("senderBookingQuotes").doc("canonical_sender_quote").set({
    quoteId: "canonical_sender_quote",
    userId: "qa_sender",
    currency: "GBP",
    total: 10,
    amountDue: 10,
    finalAmount: 10,
    selectedSpeed: "standard",
    selectedVehicle: "motorbike",
    distanceMiles: 2,
    parcelAuthority: {description: "Books", weightKg: 1},
    route: {
      origin: {latitude: 51.5007, longitude: -0.1246},
      destination: {latitude: 51.5033, longitude: -0.1195},
    },
  });
  const qaQuote = await flow.handle({action: "sender_quote", quoteId: "canonical_sender_quote"}, sender);
  assert.equal(qaQuote.fixtureId, fixtureId);
  assert.equal(qaQuote.amountDue, 10);
  await assert.rejects(require("./sender-booking")._qa.createSenderPaymentSession(
      stripe, {quoteId: qaQuote.quoteId}, sender, {db},
  ), /QA payment requires its isolated provider/);
  const deliveryPayload = {
    requestId: "sender_qa_request",
    pickup: {address: "QA pickup", coordinates: {lat: 51.5007, lng: -0.1246}},
    dropoff: {address: "QA dropoff", coordinates: {lat: 51.5033, lng: -0.1195}},
    recipient: {name: "QA recipient"},
    parcel: {itemName: "Books", description: "Books", weightKg: 1},
    iris: {recommendedVehicle: "Motorbike"},
    deliveryTime: {type: "now"},
  };
  const session = await flow.handle({
    action: "sender_payment_session",
    fixtureId,
    quoteId: qaQuote.quoteId,
    requestId: "sender_qa_request",
    idempotencyKey: "sender_qa_request",
    fallbackMethod: "card",
    checkoutMode: "web_checkout",
    deliveryPayload,
  }, sender);
  assert.equal(session.qaOnly, true);
  assert.match(session.checkoutSessionId, /^cs_test_sender_/);
  const checkout = [...objects.values()][0];
  checkout.payment_status = "paid";
  checkout.status = "complete";
  checkout.payment_intent = "pi_test_sender_1";
  const first = await flow.handle({
    action: "sender_finalize",
    fixtureId,
    checkoutSessionId: session.checkoutSessionId,
    paymentSessionId: session.paymentSessionId,
  }, sender);
  const replay = await flow.handle({
    action: "sender_finalize",
    fixtureId,
    checkoutSessionId: session.checkoutSessionId,
    paymentSessionId: session.paymentSessionId,
  }, sender);
  assert.equal(first.qaOnly, true);
  assert.equal(first.dispatchStatus, "suppressed_qa");
  assert.equal(replay.idempotent, true);
  const delivery = (await db.collection("deliveryRequests").doc(first.deliveryId).get()).data();
  assert.equal(delivery.isSyntheticQa, true);
  assert.equal(delivery.qaFixtureId, fixtureId);
  assert.equal(delivery.realDispatch, false);
  assert.equal(delivery.excludeFromSettlement, true);
  assert.equal(delivery.paymentStatus, "paid");
  assert.equal((await db.collection("deliveryRequests").where("qaFixtureId", "==", fixtureId).get()).size, 1);
  // A TEST Roth payment must never read or debit the ordinary wallet, even
  // when the same QA identity has a larger balance in that namespace.
  const liveWallet = db.collection("wallets").doc("sender@example.invalid");
  const liveProjection = db.collection("senderWallets").doc("qa_sender");
  await liveWallet.set({balance: 999, sentinel: "unchanged"});
  await liveProjection.set({balance: 999, sentinel: "unchanged"});
  await flow.handle({action: "sender_roth_prepare", fixtureId}, sender);
  await db.collection("senderBookingQuotes").doc("canonical_roth_quote").set({
    ...(await db.collection("senderBookingQuotes").doc("canonical_sender_quote").get()).data(),
    quoteId: "canonical_roth_quote",
  });
  const rothQuote = await flow.handle({action: "sender_quote", quoteId: "canonical_roth_quote"}, sender);
  const rothArgs = {
    action: "sender_payment_session", fixtureId, quoteId: rothQuote.quoteId,
    rothEnabled: true, fallbackMethod: "card", checkoutMode: "web_checkout",
    idempotencyKey: "qa_roth_sender", deliveryPayload,
  };
  const roth = await flow.handle(rothArgs, sender);
  assert.equal(roth.paymentStatus, "succeeded");
  assert.equal(roth.rothAppliedAmount, 10);
  await flow.handle(rothArgs, sender);
  const qaRoot = db.collection("qaSpecialFlowFixtures").doc(fixtureId);
  assert.equal((await qaRoot.collection("wallets").doc("sender@example.invalid").get()).data().balance, 47);
  assert.equal((await qaRoot.collection("walletTransactions").get()).size, 1);
  assert.deepEqual((await liveWallet.get()).data(), {balance: 999, sentinel: "unchanged"});
  assert.deepEqual((await liveProjection.get()).data(), {balance: 999, sentinel: "unchanged"});
  assert.equal((await db.collection("walletTransactions").doc(`wallet_delivery_${roth.paymentSessionId}`).get()).exists, false);
  await flow.handle({action: "cleanup", fixtureId}, operator);
  assert.equal((await db.collection("deliveryRequests").where("qaFixtureId", "==", fixtureId).get()).size, 0);
  assert.equal((await db.collection("senderPaymentSessions").where("qaFixtureId", "==", fixtureId).get()).size, 0);
  assert.equal((await db.collection("qaSpecialFlowFixtures").doc(fixtureId).get()).data().archived, true);
});
