"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const Stripe = require("stripe");
const {handleStripeConnectWebhook} = require("./rider-connect");

test("Connect webhook rejects validly signed wrong-mode or mode-less events before Firestore access", async (t) => {
  const prior = process.env.STRIPE_CONNECT_WEBHOOK_SECRET;
  const secret = "whsec_local_security_fixture";
  process.env.STRIPE_CONNECT_WEBHOOK_SECRET = secret;
  t.after(() => {
    if (prior === undefined) delete process.env.STRIPE_CONNECT_WEBHOOK_SECRET;
    else process.env.STRIPE_CONNECT_WEBHOOK_SECRET = prior;
  });
  for (const [mode, livemode] of [["test", true], ["live", false], ["unknown", false], ["test", undefined]]) {
    const stripe = new Stripe("sk_test_local_security_fixture");
    stripe._circumStripeMode = mode;
    const rawBody = Buffer.from(JSON.stringify({id: "evt_wrong_mode", type: "transfer.reversed", livemode, data: {object: {id: "tr_wrong_mode"}}}));
    const signature = stripe.webhooks.generateTestHeaderString({payload: rawBody, secret});
    const res = {code: 200, status(code) {
      this.code = code; return this;
    }, send(body) {
      this.body = body;
    }};
    await handleStripeConnectWebhook(stripe)({rawBody, headers: {"stripe-signature": signature}}, res);
    assert.equal(res.code, 400);
    assert.equal(res.body, "Invalid signature");
  }
});
