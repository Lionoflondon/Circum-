/* eslint-disable max-len */
"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const Stripe = require("stripe");
const {createStripeWebhookProcessor} = require("./stripe-webhook-core");

const secret = "whsec_cloud_run_fixture";
const stripe = new Stripe("sk_test_cloud_run_fixture");

function signed(event, timestamp = Math.floor(Date.now() / 1000)) {
  const rawBody = Buffer.from(JSON.stringify(event));
  return {
    rawBody,
    signature: stripe.webhooks.generateTestHeaderString({payload: rawBody, secret, timestamp}),
  };
}

function dependencies(overrides = {}) {
  const ignored = async () => ({handled: false});
  return {
    stripe,
    resolveRuntimeConfig: () => ({webhookSecret: secret, mode: "test"}),
    assertEventMode: (event) => {
      if (event.livemode) throw new Error("mode mismatch");
    },
    db: {},
    messaging: {send: async () => "ok"},
    giftsPayment: {handleGiftCheckoutExpired: ignored, handleGiftPaymentIntent: ignored},
    ratingsTipping: {processStripeTipDispute: ignored, processStripeTipRefund: ignored, processStripeTipIntent: ignored},
    stripeRefunds: {syncChargeRefund: async () => ({handled: true})},
    senderBooking: {handleSenderPaymentIntent: ignored, handleSenderCheckoutSession: ignored},
    businessPayments: {},
    healthPlus: {},
    healthMembershipLifecycle: {handleHealthSubscriptionEvent: ignored, handleHealthInvoiceEvent: ignored, handleHealthMembershipCheckoutSession: ignored},
    rothLedger: {},
    routeCheckoutSessionCompleted: ignored,
    logger: {info() {}, log() {}, warn() {}, error() {}},
    ...overrides,
  };
}

function event(id = "evt_unknown", type = "circum.test.unknown") {
  return {id, type, livemode: false, data: {object: {id: "obj_1", metadata: {}}}};
}

test("signature verification uses exact raw bytes and accepts an unknown signed event", async () => {
  const processor = createStripeWebhookProcessor(dependencies());
  const request = signed(event());
  assert.deepEqual(await processor(request), {status: 200, body: {success: true, unsupported: true}});
  const mutated = {...request, rawBody: Buffer.concat([request.rawBody, Buffer.from(" ")])};
  assert.equal((await processor(mutated)).status, 400);
});

test("missing, malformed, wrong-secret, stale and random signatures fail without mutation", async () => {
  let mutations = 0;
  const processor = createStripeWebhookProcessor(dependencies({
    senderBooking: {handleSenderPaymentIntent: async () => {
 mutations += 1; return {handled: true};
}, handleSenderCheckoutSession: async () => ({handled: false})},
  }));
  const rawBody = Buffer.from(JSON.stringify(event("evt_invalid", "payment_intent.succeeded")));
  const attempts = [
    {rawBody},
    {rawBody, signature: "malformed"},
    {rawBody, signature: new Stripe("sk_test_other").webhooks.generateTestHeaderString({payload: rawBody, secret: "whsec_wrong"})},
    signed(event("evt_stale"), Math.floor(Date.now() / 1000) - 600),
    {rawBody: Buffer.from("not-json"), signature: "random"},
  ];
  for (const attempt of attempts) assert.equal((await processor(attempt)).status, 400);
  assert.equal(mutations, 0);
});

test("Gen 1 and Cloud Run processors share route idempotency for 100 replay deliveries", async () => {
  const claimed = new Set();
  let effects = 0;
  const handler = async (_stripe, _intent, eventId) => {
    if (claimed.has(eventId)) return {handled: true, duplicate: true};
    claimed.add(eventId);
    effects += 1;
    return {handled: true, duplicate: false};
  };
  const deps = dependencies({giftsPayment: {handleGiftCheckoutExpired: async () => ({handled: false}), handleGiftPaymentIntent: handler}});
  const oldProcessor = createStripeWebhookProcessor(deps);
  const cloudRunProcessor = createStripeWebhookProcessor(deps);
  const request = signed(event("evt_test_same_event", "payment_intent.succeeded"));
  const results = await Promise.all(Array.from({length: 100}, (_, index) => (index % 2 ? oldProcessor : cloudRunProcessor)(request)));
  assert.equal(results.every((result) => result.status === 200), true);
  assert.equal(claimed.size, 1);
  assert.equal(effects, 1);
});

test("temporary failure returns to the caller and retry can complete without duplicate effect", async () => {
  let attempts = 0;
  let effects = 0;
  const handler = async () => {
    attempts += 1;
    if (attempts === 1) throw new Error("simulated pre-commit crash");
    if (effects === 0) effects += 1;
    return {handled: true};
  };
  const processor = createStripeWebhookProcessor(dependencies({giftsPayment: {handleGiftCheckoutExpired: async () => ({handled: false}), handleGiftPaymentIntent: handler}}));
  const request = signed(event("evt_crash_retry", "payment_intent.succeeded"));
  const failed = await processor(request);
  assert.equal(failed.status, 500);
  assert.equal(failed.body.error, "gift_payment_intent_failed");
  assert.equal((await processor(request)).status, 200);
  assert.equal(effects, 1);
});
