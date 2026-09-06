/* eslint-disable max-len */
const test = require("node:test");
const assert = require("node:assert/strict");
const {assertTipIntent} = require("./ratings-tipping")._test;
const tip = {tipId: "d", deliveryId: "d", senderId: "s", riderId: "r", amountPence: 500, stripePaymentIntentId: "pi_tip", stripeCustomerId: "cus_sender"};
const intent = {id: "pi_tip", amount: 500, currency: "gbp", customer: "cus_sender", metadata: {paymentType: "delivery_tip", tipId: "d", deliveryId: "d", senderId: "s", riderId: "r"}};
test("tip confirmation binds money, intent, customer and all participants", () => {
  assert.doesNotThrow(() => assertTipIntent(tip, intent));
  for (const patch of [{amount: 501}, {currency: "usd"}, {id: "pi_other"}, {customer: "cus_other"}]) {
    assert.throws(() => assertTipIntent(tip, {...intent, ...patch}));
  }
  for (const field of Object.keys(intent.metadata)) {
    assert.throws(() => assertTipIntent(tip, {...intent, metadata: {...intent.metadata, [field]: "other"}}));
  }
});
