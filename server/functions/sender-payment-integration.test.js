/* eslint-disable max-len */
const test = require("node:test");
const assert = require("node:assert/strict");
const {_private} = require("./sender-booking");
const {calculateWalletCheckout} = require("./wallet-core");

test("Sender checkout keeps Roth plus external rail totals invariant", () => {
  for (const method of ["card", "apple_pay", "google_pay"]) {
    const split = calculateWalletCheckout({
      orderTotalGbp: 50,
      walletBalanceGbp: 20,
      selectedCurrency: "gbp",
    });
    const fallback = _private.normalizeSenderPaymentFallback({
      requestedFallback: method,
      stripeRequired: split.stripeRequired,
      webCheckout: false,
    });
    assert.equal(fallback, method);
    assert.equal(split.walletContributionGbp, 20);
    assert.equal(split.remainingGbp, 30);
    assert.equal(split.stripeAmountMinor, 3000);
    assert.equal(split.orderTotalGbp, split.walletContributionGbp + split.remainingGbp);
  }
});

test("Sender saved-card checkout binds the payment method id to the Stripe remainder", () => {
  const split = calculateWalletCheckout({
    orderTotalGbp: 50,
    walletBalanceGbp: 20,
    selectedCurrency: "gbp",
  });
  assert.equal(_private.normalizeSenderPaymentFallback({
    requestedFallback: "card",
    savedPaymentMethodId: "pm_card_123",
    stripeRequired: split.stripeRequired,
    webCheckout: false,
  }), "saved_card");
  assert.equal(_private.normalizeSenderPaymentFallback({
    requestedFallback: "saved_card",
    savedPaymentMethodId: "pm_card_123",
    stripeRequired: split.stripeRequired,
    webCheckout: false,
  }), "saved_card");
});

test("Sender Roth-only checkout never creates an external Stripe rail", () => {
  const split = calculateWalletCheckout({
    orderTotalGbp: 25,
    walletBalanceGbp: 40,
    selectedCurrency: "gbp",
  });
  assert.equal(split.walletContributionGbp, 25);
  assert.equal(split.remainingGbp, 0);
  assert.equal(split.stripeRequired, false);
  assert.equal(_private.normalizeSenderPaymentFallback({
    requestedFallback: "apple_pay",
    stripeRequired: split.stripeRequired,
    webCheckout: false,
  }), "roth");
});

test("Sender checkout rejects impossible Roth, saved-card, and native-wallet mixes", () => {
  const reject = (input) => assert.throws(
      () => _private.normalizeSenderPaymentFallback({
        stripeRequired: true,
        webCheckout: false,
        ...input,
      }),
      (error) => error.code === "invalid-argument",
  );

  reject({requestedFallback: "roth"});
  reject({requestedFallback: "saved_card"});
  reject({requestedFallback: "apple_pay", savedPaymentMethodId: "pm_card_123"});
  reject({requestedFallback: "google_pay", savedPaymentMethodId: "pm_card_123"});
  reject({requestedFallback: "cash"});
  reject({requestedFallback: "apple_pay", webCheckout: true});
});
