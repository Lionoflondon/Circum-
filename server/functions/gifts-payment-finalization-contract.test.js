/* eslint-disable max-len */
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const source = fs.readFileSync(path.join(__dirname, "gifts-payment.js"), "utf8");
const router = fs.readFileSync(path.join(__dirname, "checkout-session-router.js"), "utf8");
const index = fs.readFileSync(path.join(__dirname, "index.js"), "utf8");

test("Gift finalization verifies authoritative Stripe session state", () => {
  assert.match(source, /payment\.status !== "succeeded"/);
  assert.match(source, /payment\.currency !== "gbp"/);
  assert.match(source, /Number\(payment\.amountPence \|\| 0\) !== Math\.round\(externalAmount \* 100\)/);
  assert.match(source, /payment\.providerId !== gift\.stripeCheckoutSessionId/);
  assert.match(source, /gift\.senderId !== actorUid/);
});

test("Gift finalization verifies voice-note storage before attaching to Gift request", () => {
  assert.match(source, /verifyGiftVoiceStorageObject/);
  assert.match(source, /checkedVoiceNote \? \{voiceNote: checkedVoiceNote\} : \{\}/);
  assert.match(source, /giftVoiceMediaAudit/);
  assert.match(source, /gift_voice_media_attached/);
});

test("native Gift wallets use a server PaymentIntent and retain the selected method", () => {
  assert.match(source, /checkoutMode\) === "payment_intent"/);
  assert.match(source, /stripe\.paymentIntents\.create/);
  assert.match(source, /automatic_payment_methods: \{enabled: true\}/);
  assert.match(source, /paymentMethod: requestedMethod/);
  assert.match(source, /type: "gift_payment_intent"/);
  assert.doesNotMatch(source, /clientSecret:\s*intent\.client_secret,[\s\S]*?ref\.set/);
});

test("Gift totals reconcile exactly and Roth debit is deterministic", () => {
  assert.match(source, /roundMoney\(rothApplied \+ externalAmount\) !== gross/);
  assert.match(source, /doc\(`gift_roth_\$\{giftDraftId\}`\)/);
  assert.match(source, /walletTransactionSnap && walletTransactionSnap\.exists/);
  assert.match(source, /balanceAfter: after/);
});

test("PaymentIntent webhook finalizes Gift authority before generic Sender routing", () => {
  assert.match(source, /exports\.handleGiftPaymentIntent/);
  assert.match(index, /giftsPayment\.handleGiftPaymentIntent/);
  assert.match(index, /gift_payment_intent_failed/);
});

test("Gift finalization is idempotent for duplicate webhook or client recovery", () => {
  assert.match(source, /existingGiftSnap\.exists/);
  assert.match(source, /existing\.paymentStatus === "paid"/);
  assert.match(source, /giftPaymentEvents/);
  assert.match(source, /eventId \? "stripe_webhook" : "client_recovery"/);
});

test("Gift client retries preserve one immutable backend draft and PaymentIntent", () => {
  assert.match(source, /draftFingerprint/);
  assert.match(source, /existingData\.draftFingerprint !== draftFingerprint/);
  assert.match(source, /existingIntentId/);
  assert.match(source, /requiresConfirmation: intent\.status !== "succeeded"/);
  assert.match(source, /authoritativeQuoteId: quoteId/);
});

test("Gift client payload cannot supply payment, dispatch, or assignment authority", () => {
  assert.match(source, /function clientGiftPayload/);
  assert.match(source, /"paymentStatus"/);
  assert.match(source, /"dispatchEligible"/);
  assert.match(source, /"assignedRiderId"/);
});

test("Gift budget authority rejects values outside the canonical product range", () => {
  assert.match(source, /function authoritativeGiftBudget/);
  assert.match(source, /amount < 50 \|\| amount > 1500/);
  assert.match(source, /!Number\.isInteger\(amount\)/);
});

test("Stripe Checkout webhook routes gift_experience through the Gift finalizer", () => {
  assert.match(router, /type === "gift_experience"/);
  assert.match(router, /finalizeGiftPaymentFromCheckoutSession/);
  assert.match(index, /giftsPayment,/);
});

test("abandoned Gift voice draft cleanup is exported for scheduled execution", () => {
  assert.match(source, /cleanupExpiredGiftVoiceDrafts/);
  assert.match(index, /exports\.cleanupExpiredGiftVoiceDrafts/);
});

test("deleted Gift requests clean owned voice media", () => {
  assert.match(source, /onGiftRequestVoiceMediaDeleted/);
  assert.match(index, /exports\.onGiftRequestVoiceMediaDeleted/);
});
