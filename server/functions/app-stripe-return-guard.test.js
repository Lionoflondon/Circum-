const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const {
  SENDER_APP_HOME,
  normalizeOrigin,
  normalizeSenderAppReturnBase,
  senderAppCancelUrl,
  senderAppCheckoutUrls,
} = require("./app-stripe-return-guard");

test("app Stripe cancellation always returns to Sender app home", () => {
  assert.equal(
      senderAppCancelUrl("https://circumuk.com/?app=sender&section=wallet", {
        wallet_topup: "cancelled",
      }),
      `${SENDER_APP_HOME}?wallet_topup=cancelled`,
  );
  assert.equal(
      senderAppCancelUrl("https://circum-2797c.web.app/send", {
        sender_payment: "cancelled",
        paymentSessionId: "pay_123",
      }),
      `${SENDER_APP_HOME}?sender_payment=cancelled&paymentSessionId=pay_123`,
  );
});

test("app Stripe success can keep app context but public web is not accepted as an app base", () => {
  assert.equal(
      normalizeSenderAppReturnBase("https://circum-app-2797c.web.app/#/sender-mobile/wallet", "/#/sender-mobile"),
      "https://circum-app-2797c.web.app/#/sender-mobile/wallet",
  );
  assert.equal(
      normalizeSenderAppReturnBase("https://circumuk.com/?app=business", "/#/sender-mobile/business"),
      "https://circum-app-2797c.web.app/#/sender-mobile/business",
  );
  assert.equal(
      normalizeOrigin("https://circumuk.com"),
      "https://circum-app-2797c.web.app",
  );
});

test("app checkout URL builder never gives Stripe a public-web cancel URL", () => {
  const urls = senderAppCheckoutUrls({
    returnUrl: "https://circumuk.com/?app=sender&section=wallet",
    successPath: "/#/sender-mobile/wallet",
    successParams: {wallet_topup: "success", session_id: "{CHECKOUT_SESSION_ID}"},
    cancelParams: {wallet_topup: "cancelled"},
  });
  assert.equal(
      urls.successUrl,
      "https://circum-app-2797c.web.app/#/sender-mobile/wallet?wallet_topup=success&session_id={CHECKOUT_SESSION_ID}",
  );
  assert.equal(
      urls.cancelUrl,
      "https://circum-app-2797c.web.app/#/sender-mobile?wallet_topup=cancelled",
  );
});

test("backend app Stripe session builders use the app cancellation guard", () => {
  const files = [
    "sender-finance.js",
    "roth-ledger.js",
    "sender-booking.js",
    "business-payments.js",
    "gifts-payment.js",
    "health-plus.js",
  ];
  for (const file of files) {
    const source = fs.readFileSync(path.join(__dirname, file), "utf8");
    assert.match(source, /senderAppCancelUrl|senderAppCheckoutUrls/u, file);
  }
  const backend = files.map((file) => fs.readFileSync(path.join(__dirname, file), "utf8")).join("\n");
  assert.doesNotMatch(backend, /cancel_url:\s*`?\$\{?baseUrl/u);
});
