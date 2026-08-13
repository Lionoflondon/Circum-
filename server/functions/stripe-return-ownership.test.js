/* eslint-disable max-len */
"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {
  RETURN_FLOWS,
  RETURN_OWNERS,
  resolveReturnOwner,
  stripeReturnBase,
  stripeReturnUrls,
} = require("./stripe-return-ownership");

test("return owner requires one of the two explicit product owners", () => {
  assert.throws(
      () => resolveReturnOwner(),
      (error) => error.code === "invalid-argument" && /returnOwner/.test(error.message),
  );
  assert.equal(resolveReturnOwner("website"), RETURN_OWNERS.WEBSITE);
  assert.equal(resolveReturnOwner("sender_app"), RETURN_OWNERS.SENDER_APP);
  assert.throws(
      () => resolveReturnOwner("https://attacker.example"),
      (error) => error.code === "invalid-argument" && /returnOwner/.test(error.message),
  );
  assert.throws(() => resolveReturnOwner("rider"), /returnOwner/);
});

test("every shared checkout flow uses fixed owner-specific hosts", () => {
  const flows = [
    RETURN_FLOWS.BUSINESS_INVOICE,
    RETURN_FLOWS.BUSINESS_ROTH,
    RETURN_FLOWS.GIFT,
    RETURN_FLOWS.HEALTH_PLUS,
    RETURN_FLOWS.SENDER_DELIVERY,
    RETURN_FLOWS.WALLET_TOP_UP,
  ];
  for (const flow of flows) {
    assert.match(
        stripeReturnBase(flow, RETURN_OWNERS.SENDER_APP),
        /^https:\/\/circum-app-2797c\.web\.app\//,
    );
    assert.match(
        stripeReturnBase(flow, RETURN_OWNERS.WEBSITE),
        /^https:\/\/circumuk\.com\//,
    );
  }
});

test("fixed URLs preserve each product route and Stripe placeholder", () => {
  const invoice = stripeReturnUrls(RETURN_FLOWS.BUSINESS_INVOICE, {
    returnOwner: RETURN_OWNERS.SENDER_APP,
    invoiceId: "invoice 1",
    businessId: "business&1",
    paymentId: "payment/1",
  });
  assert.equal(
      invoice.successUrl,
      "https://circum-app-2797c.web.app/?app=business&section=invoicing&paymentStatus=payment-success&invoiceId=invoice%201&businessId=business%261&paymentId=payment%2F1&checkoutSessionId={CHECKOUT_SESSION_ID}",
  );
  assert.equal(
      invoice.cancelUrl,
      "https://circum-app-2797c.web.app/?app=business&section=invoicing&paymentStatus=payment-cancelled&invoiceId=invoice%201&businessId=business%261&paymentId=payment%2F1",
  );

  const delivery = stripeReturnUrls(RETURN_FLOWS.SENDER_DELIVERY, {
    returnOwner: RETURN_OWNERS.SENDER_APP,
    paymentSessionId: "session_123",
  });
  assert.equal(
      delivery.cancelUrl,
      "https://circum-app-2797c.web.app/send?app=sender&tab=1&sender_payment=cancelled&paymentSessionId=session_123",
  );

  const health = stripeReturnUrls(RETURN_FLOWS.HEALTH_PLUS, {
    returnOwner: RETURN_OWNERS.WEBSITE,
    bookingId: "health 1",
  });
  assert.deepEqual(health, {
    successUrl:
      "https://circumuk.com/send/health?health=success&bookingId=health%201",
    cancelUrl:
      "https://circumuk.com/send/health?health=cancelled&bookingId=health%201",
  });

  const websiteGift = stripeReturnUrls(RETURN_FLOWS.GIFT, {
    returnOwner: RETURN_OWNERS.WEBSITE,
    giftDraftId: "gift 1",
  });
  assert.equal(
      websiteGift.cancelUrl,
      "https://circumuk.com/gifts?gift_payment=cancelled&giftDraftId=gift%201",
  );

  const websiteWallet = stripeReturnUrls(RETURN_FLOWS.WALLET_TOP_UP, {
    returnOwner: RETURN_OWNERS.WEBSITE,
  });
  assert.equal(
      websiteWallet.cancelUrl,
      "https://circumuk.com/send/profile?section=wallet&wallet_topup=cancelled",
  );
});

test("production Stripe callsites cannot pass caller, config, or env URLs", () => {
  const root = __dirname;
  const files = [
    "business-payments.js",
    "sender-booking.js",
    "health-plus.js",
    "roth-ledger.js",
    "gifts-payment.js",
    "gifts-payment-core.js",
  ];
  const source = files.map((file) => fs.readFileSync(path.join(root, file), "utf8")).join("\n");
  assert.doesNotMatch(source, /data\.returnUrl|req\.body\.successUrl|req\.body\.cancelUrl/);
  assert.doesNotMatch(source, /config\.success_url|config\.cancel_url/);

  const rider = fs.readFileSync(path.join(root, "rider-connect.js"), "utf8");
  assert.match(rider, /const appBaseUrl = "https:\/\/circum-rider-2797c\.web\.app"/);
  assert.doesNotMatch(rider, /RIDER_APP_BASE_URL|safeConfig\.rider\.base_url/);
});
