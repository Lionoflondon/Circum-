/* eslint-disable max-len */
"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const finance = fs.readFileSync(path.join(__dirname, "sender-finance.js"), "utf8");
const referrals = fs.readFileSync(path.join(__dirname, "referrals.js"), "utf8");
const index = fs.readFileSync(path.join(__dirname, "index.js"), "utf8");

test("Sender saved-card management uses Stripe Setup mode and Sender Wallet returns", () => {
  assert.match(finance, /exports\.createSenderSetupCheckoutSession/);
  assert.match(finance, /mode:\s*"setup"/);
  assert.match(finance, /payment_method_types:\s*\["card"\]/);
  assert.match(finance, /#\/sender-mobile\/wallet\?card_setup=success/);
  assert.match(finance, /#\/sender-mobile\/wallet\?card_setup=cancelled/);
  assert.doesNotMatch(finance, /#\/send\/business|BusinessView|business_wallet/u);
  assert.match(index, /exports\.createSenderSetupCheckoutSession/);
});

test("Sender payment method projection and removal use PaymentMethod ID authority", () => {
  assert.match(finance, /new Map\(methods\.data\.map\(\(item\) => \[item\.id,/);
  assert.match(finance, /function stripeCustomerId/);
  assert.match(finance, /ownerCustomerId !== customerId/);
  assert.match(finance, /alreadyDetached: true/);
  assert.doesNotMatch(finance, /brand\s*\+\s*last4|last4\s*\+\s*brand/u);
});

test("Sender referral dashboard is callable-owned, not client Firestore authority", () => {
  assert.match(referrals, /exports\.getReferralDashboard/);
  assert.match(referrals, /ensureReferralCodeForUid/);
  assert.match(referrals, /where\("referrerUserId", "==", uid\)/);
  assert.match(referrals, /rothEarned/);
  assert.match(index, /exports\.getReferralDashboard/);
});
