const test = require("node:test");
const assert = require("node:assert/strict");
const {
  CheckoutClaimError,
  checkoutClaim,
  checkoutFingerprint,
  checkoutLogicalKey,
  createStripeCheckoutOnce,
  stripeCheckoutIdempotencyKey,
} = require("./checkout-idempotency-core");

function fakeStripe() {
  const sessions = new Map();
  let sequence = 0;
  return {
    checkout: {
      sessions: {
        async create(params, {idempotencyKey}) {
          await new Promise((resolve) => setImmediate(resolve));
          const serialized = JSON.stringify(params);
          const prior = sessions.get(idempotencyKey);
          if (prior && prior.serialized !== serialized) {
            const error = new Error("Keys for idempotent requests can only be used with the same parameters");
            error.code = "idempotency_key_in_use";
            throw error;
          }
          if (prior) return prior.session;
          sequence += 1;
          const session = {id: `cs_test_${sequence}`, url: `https://checkout.stripe.test/${sequence}`};
          sessions.set(idempotencyKey, {serialized, session});
          return session;
        },
      },
    },
    get createCount() {
      return sequence;
    },
  };
}

test("checkout fingerprints are canonical and logical keys are stable", () => {
  assert.equal(
      checkoutFingerprint({b: 2, nested: {z: true, a: [1, 2]}, a: 1}),
      checkoutFingerprint({a: 1, nested: {a: [1, 2], z: true}, b: 2}),
  );
  const logical = checkoutLogicalKey("Health+", {bookingId: "booking-1", senderId: "sender-1"});
  assert.match(logical, /^health_[a-f0-9]{40}$/);
  assert.match(stripeCheckoutIdempotencyKey(logical), /^circum_checkout_[a-f0-9]{64}$/);
});

test("same-owner retries resume the one claimed Checkout Session", () => {
  const logicalKey = checkoutLogicalKey("gift", {giftDraftId: "gift-1"});
  const requestFingerprint = checkoutFingerprint({amountPence: 5000, senderId: "sender-1"});
  const claimed = checkoutClaim({}, {logicalKey, requestFingerprint, returnOwner: "sender_app"});
  const resumed = checkoutClaim({
    ...claimed.claim,
    paymentStatus: "payment_pending",
    checkoutSessionId: "cs_test_same",
    checkoutUrl: "https://checkout.stripe.test/same",
  }, {logicalKey, requestFingerprint, returnOwner: "sender_app"});
  assert.equal(resumed.kind, "reuse");
  assert.equal(resumed.sessionId, "cs_test_same");
});

test("claimed checkout fails closed across product owners or changed payment details", () => {
  const logicalKey = checkoutLogicalKey("sender_delivery", {quoteId: "quote-1"});
  const fingerprint = checkoutFingerprint({amountPence: 1200, payload: "one"});
  const existing = {
    ...checkoutClaim({}, {
      logicalKey,
      requestFingerprint: fingerprint,
      returnOwner: "sender_app",
    }).claim,
    checkoutSessionId: "cs_test_owner",
    checkoutUrl: "https://checkout.stripe.test/owner",
  };
  assert.throws(
      () => checkoutClaim(existing, {
        logicalKey,
        requestFingerprint: fingerprint,
        returnOwner: "website",
      }),
      (error) => error instanceof CheckoutClaimError && error.reason === "owner_mismatch",
  );
  assert.throws(
      () => checkoutClaim(existing, {
        logicalKey,
        requestFingerprint: checkoutFingerprint({amountPence: 1300, payload: "two"}),
        returnOwner: "sender_app",
      }),
      (error) => error instanceof CheckoutClaimError && error.reason === "request_mismatch",
  );
});

test("concurrent logical retries cannot produce two chargeable Stripe Session IDs", async () => {
  const flows = [
    ["gift", {giftDraftId: "gift-1"}],
    ["sender_delivery", {quoteId: "quote-1"}],
    ["health_plus", {bookingId: "health-1"}],
    ["business_invoice", {invoiceId: "invoice-1", balancePence: 2000}],
  ];
  for (const [flow, identity] of flows) {
    const stripe = fakeStripe();
    const logicalKey = checkoutLogicalKey(flow, identity);
    const params = {
      mode: "payment",
      line_items: [{amount: 1000}],
      success_url: "https://owner.example/success",
      cancel_url: "https://owner.example/cancel",
    };
    const sessions = await Promise.all(
        Array.from({length: 12}, () => createStripeCheckoutOnce({stripe, logicalKey, params})),
    );
    assert.equal(new Set(sessions.map((session) => session.id)).size, 1, flow);
    assert.equal(stripe.createCount, 1, flow);
  }
});

test("conflicting concurrent requests share a Stripe key and one fails instead of creating a second Session", async () => {
  const stripe = fakeStripe();
  const logicalKey = checkoutLogicalKey("business_invoice", {
    invoiceId: "invoice-2",
    balancePence: 5000,
  });
  const results = await Promise.allSettled([
    createStripeCheckoutOnce({
      stripe,
      logicalKey,
      params: {amount: 5000, success_url: "https://circumuk.com/send/business"},
    }),
    createStripeCheckoutOnce({
      stripe,
      logicalKey,
      params: {amount: 4000, success_url: "https://circum-app-2797c.web.app/?app=business"},
    }),
  ]);
  assert.equal(results.filter((result) => result.status === "fulfilled").length, 1);
  assert.equal(results.filter((result) => result.status === "rejected").length, 1);
  assert.equal(stripe.createCount, 1);
});
