/* eslint-disable max-len */
const assert = require("node:assert/strict");
const test = require("node:test");
const {routeCheckoutSessionCompleted} = require("./checkout-session-router");

test("business Roth checkout uses Business finalizer", async () => {
  const calls = [];
  const result = await routeCheckoutSessionCompleted(
      {id: "cs_business_roth", metadata: {type: "business_roth_purchase"}},
      "evt_1",
      {
        businessPayments: {
          handleBusinessCheckoutSession: async (session, eventId) => {
            calls.push({session, eventId});
          },
        },
      },
  );

  assert.deepEqual(result, {handled: true, type: "business_roth_purchase"});
  assert.equal(calls.length, 1);
  assert.equal(calls[0].session.id, "cs_business_roth");
  assert.equal(calls[0].eventId, "evt_1");
});

test("business invoice checkout uses Business finalizer", async () => {
  const calls = [];
  const result = await routeCheckoutSessionCompleted(
      {id: "cs_business_invoice", metadata: {type: "business_invoice_payment"}},
      "evt_2",
      {
        businessPayments: {
          handleBusinessCheckoutSession: async (session, eventId) => {
            calls.push({session, eventId});
          },
        },
      },
  );

  assert.deepEqual(result, {handled: true, type: "business_invoice_payment"});
  assert.equal(calls.length, 1);
  assert.equal(calls[0].session.id, "cs_business_invoice");
  assert.equal(calls[0].eventId, "evt_2");
});

test("wallet top-up checkout uses Roth ledger finalizer", async () => {
  const calls = [];
  const result = await routeCheckoutSessionCompleted(
      {id: "cs_wallet", metadata: {type: "wallet_top_up"}},
      "evt_3",
      {
        rothLedger: {
          recordWalletTopUpFromStripeSession: async (session, eventId) => {
            calls.push({session, eventId});
          },
        },
      },
  );

  assert.deepEqual(result, {handled: true, type: "wallet_top_up"});
  assert.equal(calls.length, 1);
  assert.equal(calls[0].session.id, "cs_wallet");
  assert.equal(calls[0].eventId, "evt_3");
});

test("gift checkout uses the Gifts finalizer for lost redirect recovery", async () => {
  const calls = [];
  const result = await routeCheckoutSessionCompleted(
      {id: "cs_gift", metadata: {type: "gift_experience", giftDraftId: "gift-1"}},
      "evt_gift",
      {
        giftsPayment: {
          finalizeGiftPaymentFromCheckoutSession: async (payload) => {
            calls.push(payload);
          },
        },
      },
  );

  assert.deepEqual(result, {handled: true, type: "gift_experience"});
  assert.equal(calls.length, 1);
  assert.equal(calls[0].giftDraftId, "gift-1");
  assert.equal(calls[0].session.id, "cs_gift");
  assert.equal(calls[0].eventId, "evt_gift");
});

test("Health+ checkout uses the Health+ finalizer for Roth and card settlement", async () => {
  const calls = [];
  const result = await routeCheckoutSessionCompleted(
      {id: "cs_health", metadata: {type: "health_plus_payment", bookingId: "hp_1"}},
      "evt_health",
      {
        healthPlus: {
          handleHealthPlusCheckoutSession: async (session, eventId) => {
            calls.push({session, eventId});
          },
        },
      },
  );

  assert.deepEqual(result, {handled: true, type: "health_plus_payment"});
  assert.equal(calls.length, 1);
  assert.equal(calls[0].session.id, "cs_health");
  assert.equal(calls[0].eventId, "evt_health");
});

test("legacy Health+ checkout metadata still reaches the Health+ finalizer", async () => {
  const calls = [];
  const result = await routeCheckoutSessionCompleted(
      {id: "cs_health_legacy", metadata: {feature: "health_plus", bookingId: "hp_2"}},
      "evt_health_legacy",
      {
        healthPlus: {
          handleHealthPlusCheckoutSession: async (session, eventId) => {
            calls.push({session, eventId});
          },
        },
      },
  );

  assert.deepEqual(result, {handled: true, type: "health_plus_payment"});
  assert.equal(calls.length, 1);
  assert.equal(calls[0].session.id, "cs_health_legacy");
  assert.equal(calls[0].eventId, "evt_health_legacy");
});

test("unknown checkout session metadata is ignored safely", async () => {
  const logs = [];
  const result = await routeCheckoutSessionCompleted(
      {id: "cs_unknown", metadata: {type: "other"}},
      "evt_4",
      {logger: {info: (...args) => logs.push(args)}},
  );

  assert.deepEqual(result, {handled: false, type: "other"});
  assert.equal(logs.length, 1);
});

test("finalizer errors propagate so Stripe can retry the webhook", async () => {
  await assert.rejects(
      routeCheckoutSessionCompleted(
          {id: "cs_wallet_error", metadata: {type: "wallet_top_up"}},
          "evt_5",
          {
            rothLedger: {
              recordWalletTopUpFromStripeSession: async () => {
                throw new Error("transient write failure");
              },
            },
          },
      ),
      /transient write failure/,
  );
});
