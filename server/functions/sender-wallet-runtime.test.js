"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const rothLedger = require("./roth-ledger");
const senderFinance = require("./sender-finance");

test("fresh Sender Wallet reads the authoritative legacy balance without writing", () => {
  const view = rothLedger._private.senderWalletReadView({
    uid: "sender-1",
    legacy: {balance: 17.35, updatedAt: {toMillis: () => 200}},
    projection: {balance: 99, status: "active", version: 4, updatedAt: {toMillis: () => 100}},
    role: {balance: 4},
    profile: {senderWalletOnboardingCompleted: true},
  });

  assert.deepEqual(view, {
    userId: "sender-1",
    balance: 17.35,
    currency: "ROTH",
    status: "active",
    version: 4,
    onboardingCompleted: true,
    updatedAt: "1970-01-01T00:00:00.200Z",
    source: "wallet",
  });
});

test("new and malformed wallet records fall back safely to zero or a valid projection", () => {
  assert.equal(rothLedger._private.senderWalletReadView({uid: "new"}).balance, 0);
  assert.equal(rothLedger._private.senderWalletReadView({
    uid: "repair",
    legacy: {balance: "not-a-number", rothCredit: "also-invalid"},
    projection: {balance: 8.4},
  }).balance, 8.4);
});

function fakeDb(user, preference = {}) {
  const doc = (value) => ({
    async get() {
      return {exists: Object.keys(value).length > 0, data: () => value};
    },
  });
  return {
    collection(name) {
      assert.equal(name, "users");
      return {
        doc(uid) {
          assert.equal(uid, "sender-1");
          return {
            get: () => doc(user).get(),
            collection(child) {
              assert.equal(child, "finance");
              return {doc: (id) => {
                assert.equal(id, "checkoutPreferences");
                return doc(preference);
              }};
            },
          };
        },
      };
    },
  };
}

test("payment-method read is read-only and returns a truthful no-customer state", async () => {
  let stripeCalls = 0;
  const result = await senderFinance._private.readSenderPaymentMethodsForContext({
    customers: {retrieve: async () => ++stripeCalls},
    paymentMethods: {list: async () => ++stripeCalls},
  }, {auth: {uid: "sender-1", token: {email: "sender@example.invalid"}}}, fakeDb({}, {preference: "roth_first"}));

  assert.deepEqual(result, {
    customerId: null,
    defaultPaymentMethodId: null,
    preference: "roth_first",
    paymentMethods: [],
    walletCompatible: true,
    applePaySupported: true,
    googlePaySupported: true,
  });
  assert.equal(stripeCalls, 0);
});

test("payment-method read verifies the stored customer and exposes only safe card fields", async () => {
  const calls = [];
  const result = await senderFinance._private.readSenderPaymentMethodsForContext({
    customers: {retrieve: async (id) => {
      calls.push(["customer", id]);
      return {id, invoice_settings: {default_payment_method: "pm_default"}};
    }},
    paymentMethods: {list: async (params) => {
      calls.push(["list", params]);
      return {data: [{id: "pm_default", type: "card", card: {brand: "visa", last4: "4242", exp_month: 9, exp_year: 2030}, secret: "must-not-leak"}]};
    }},
  }, {auth: {uid: "sender-1", token: {email: "sender@example.invalid"}}}, fakeDb({stripeCustomerId: "cus_sender"}));

  assert.equal(result.customerId, "cus_sender");
  assert.deepEqual(result.paymentMethods, [{
    id: "pm_default",
    type: "card",
    brand: "visa",
    last4: "4242",
    expMonth: 9,
    expYear: 2030,
    isDefault: true,
  }]);
  assert.deepEqual(calls, [
    ["customer", "cus_sender"],
    ["list", {customer: "cus_sender", type: "card"}],
  ]);
});

test("payment-method provider outages map to safe retryable failures", async () => {
  const error = Object.assign(new Error("provider detail"), {code: "api_connection_error"});
  await assert.rejects(
      senderFinance._private.readSenderPaymentMethodsForContext({
        customers: {
          retrieve: async () => {
            throw error;
          },
        },
      }, {auth: {uid: "sender-1", token: {email: "sender@example.invalid"}}}, fakeDb({customerId: "cus_sender"})),
      (failure) => failure.code === "unavailable" && failure.message === "Payment methods are temporarily unavailable.",
  );
});
