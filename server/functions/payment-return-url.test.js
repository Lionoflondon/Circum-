const test = require("node:test");
const assert = require("node:assert/strict");
const {
  DEFAULTS,
  paymentReturnBase,
} = require("./payment-return-url");

test("Stripe return URLs default to app routes, not public Website routes", () => {
  assert.equal(
      paymentReturnBase("senderWallet"),
      "https://circum-app-2797c.web.app/#/sender-mobile/wallet",
  );
  assert.equal(
      paymentReturnBase("business"),
      "https://circum-app-2797c.web.app/#/sender-mobile/business",
  );
  assert.equal(
      paymentReturnBase("gifts"),
      "https://circum-app-2797c.web.app/#/sender-mobile/gifts/payment",
  );
});

test("public Website and cross-product return URLs are rejected", () => {
  assert.equal(
      paymentReturnBase(
          "senderWallet",
          "https://circumuk.com/?app=sender&section=wallet",
      ),
      DEFAULTS.senderWallet,
  );
  assert.equal(
      paymentReturnBase(
          "business",
          "https://circum-app-2797c.web.app/#/sender-mobile/wallet",
      ),
      DEFAULTS.business,
  );
  assert.equal(
      paymentReturnBase("gifts", "https://example.com/checkout-return"),
      DEFAULTS.gifts,
  );
});

test("legacy app host is normalized to the Sender app host", () => {
  assert.equal(
      paymentReturnBase(
          "senderDelivery",
          "https://circum-2797c.web.app/#/sender-mobile/send?old=true",
      ),
      DEFAULTS.senderDelivery,
  );
});

test("approved product app routes are preserved without stale query strings", () => {
  assert.equal(
      paymentReturnBase(
          "healthPlus",
          "https://circum-app-2797c.web.app/#/sender-mobile/health?health=cancelled",
      ),
      DEFAULTS.healthPlus,
  );
});
