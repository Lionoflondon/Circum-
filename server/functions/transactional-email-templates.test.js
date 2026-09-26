"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const templates = require("./transactional-email-templates");

function customerFields(copy) {
  return templates.visibleCustomerText(copy);
}

test("every transactional template has complete customer-facing structure", () => {
  const copies = [
    templates.welcome({displayName: "Vaughn Werner"}),
    templates.bookingConfirmed({reference: "booking-1"}),
    templates.deliveryCompleted({reference: "booking-1"}),
    templates.cancellationSettled({reference: "booking-1"}),
    templates.businessInvoicePaid({reference: "invoice-1"}),
    templates.businessPaymentProblem({reference: "invoice-1", state: "failed"}),
    templates.businessPaymentProblem({reference: "invoice-1", state: "unconfirmed"}),
    templates.rothActivity({movement: "credited", amount: 5, reference: "wallet-1"}),
    templates.rothActivity({movement: "debited", amount: 2.5, reference: "wallet-2"}),
    templates.rothActivity({movement: "refunded", amount: 1, reference: "wallet-3"}),
    templates.rothActivity({movement: "restored", amount: 1, reference: "wallet-4"}),
    templates.referralReward(),
    templates.riderDecision({decision: "approved"}),
    templates.riderDecision({decision: "rejected"}),
    templates.riderDecision({decision: "more_information_requested"}),
    ...Object.keys({
      scheduled: true,
      assigned: true,
      en_route_pickup: true,
      awaiting_pharmacy_collection: true,
      collected: true,
      out_for_delivery: true,
      delivered: true,
      prescription_not_ready: true,
      customer_unavailable: true,
      escalated: true,
      rescheduled: true,
      override_completed: true,
      reminder_24h: true,
      reminder_2h: true,
    }).map((type) => templates.healthUpdate({type})),
    templates.giftPaymentConfirmed({recipientName: "Alex", rothAmount: 120}),
    templates.giftPaymentConfirmed({recipientName: "Alex", rothAmount: 25, split: true}),
    templates.giftPaymentProblem({recipientName: "Alex", state: "failed"}),
    templates.giftPaymentProblem({recipientName: "Alex", state: "unconfirmed"}),
    templates.giftApproved({recipientName: "Alex"}),
    templates.giftRejected({recipientName: "Alex"}),
    templates.giftReadyForDelivery({recipientName: "Alex"}),
    templates.giftDelivered({recipientName: "Alex", storyUrl: "https://circumuk.com/story/senderToken"}),
    templates.giftStory({role: "sender", storyUrl: "https://circumuk.com/story/token"}),
    templates.giftStory({role: "recipient", storyUrl: "https://circumuk.com/story/token"}),
  ];
  for (const copy of copies) {
    assert.ok(copy.templateId);
    assert.ok(copy.subject);
    assert.ok(copy.preheader);
    assert.ok(copy.heading);
    assert.ok(copy.text);
    assert.ok(copy.html);
    assert.ok(copy.footer);
    assert.match(copy.html, /display:none/);
    assert.match(copy.html, /<h1(?:\s|>)/);
    assert.match(copy.html, /Reply to this email|contact Circum support|The Circum team|Contact Support|Team CIRCUM|Contact us/);
  }
});

test("rendered customer content rejects snake_case and internal labels", () => {
  const copy = templates.welcome({displayName: "A_User"});
  assert.doesNotMatch(customerFields(copy), /[a-z][a-z0-9]*_[a-z0-9_]+/i);
  for (const token of templates.FORBIDDEN_CUSTOMER_TOKENS) {
    assert.doesNotMatch(customerFields(copy).toLowerCase(), new RegExp(token.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"), "i"));
  }
  assert.throws(() => templates.assertCustomerFacingContent({subject: "roth_movement_completed"}), /snake_case|internal_token/);
  assert.throws(() => templates.assertCustomerFacingContent({subject: "delivery_in_progress"}), /snake_case|internal_token/);
});

test("technical URLs and email addresses are explicit forbidden-test exclusions", () => {
  const copy = templates.giftStory({role: "sender", storyUrl: "https://circumuk.com/story/private_token"});
  assert.match(copy.html, /private_token/);
  assert.doesNotMatch(customerFields(copy), /private_token/);
});

test("welcome copy explains the account, Starter Roth and next step without raw trigger names", () => {
  const copy = templates.welcome({displayName: "Vaughn Werner", amount: 5});
  assert.equal(copy.subject, "Welcome to CIRCUM — £5 Roth has been added to your wallet");
  assert.match(copy.heading, /Welcome to a better way to move things/);
  assert.match(copy.text, /(?:£5\.00 Roth has been added|we’ve added £5\.00 Roth) to your wallet/);
  assert.match(copy.text, /eligible Circum services and deliveries/);
  assert.match(copy.text, /Documents: Terms of Service and Privacy Policy/);
  assert.match(copy.html, /circum_wordmark\.png/);
  assert.match(copy.html, /Every delivery starts somewhere/);
  assert.match(copy.html, /Terms of Service/);
  assert.match(copy.html, /Privacy Policy/);
  assert.doesNotMatch(copy.html, /href="https:\/\/circumuk\.com\/support/);
  assert.doesNotMatch(customerFields(copy), /roth_movement_completed|sender_|starterRothGrantStatus|Firestore/i);
});

test("Business and Health+ emails use the approved branded layout and store links", () => {
  for (const copy of [templates.businessInvoicePaid({reference: "INV-2048"}),
    templates.healthUpdate({type: "scheduled"}), templates.healthUpdate({type: "rescheduled"})]) {
    assert.match(copy.html, /circum_wordmark\.png/);
    assert.match(copy.html, /download-on-the-app-store\.svg/);
    assert.match(copy.html, /en_badge_web_generic\.png/);
    assert.match(copy.html, /https:\/\/apps\.apple\.com\/gb\/app\/circum\/id6463644284/);
    assert.match(copy.html, /https:\/\/play\.google\.com\/store\/apps\/details\?id=com\.circum\.app/);
    assert.match(copy.text, /Download Circum on the App Store:/);
    assert.match(copy.text, /Get Circum on Google Play:/);
    assert.match(copy.html, /background:#(?:f0f5ff|edf8f3)/);
  }
  assert.match(templates.businessInvoicePaid({reference: "INV-2048"}).html, /INV-2048/);
  assert.match(templates.healthUpdate({type: "rescheduled"}).html, /rescheduled/);
});

test("Business payment-problem copy distinguishes failure from an unconfirmed payment", () => {
  const failed = templates.businessPaymentProblem({reference: "INV-2048", state: "failed"});
  const unconfirmed = templates.businessPaymentProblem({reference: "INV-2048", state: "unconfirmed"});
  assert.equal(failed.templateId, "business-payment-problem-failed");
  assert.equal(unconfirmed.templateId, "business-payment-problem-unconfirmed");
  assert.match(failed.text, /could not complete the payment/i);
  assert.match(unconfirmed.text, /could not confirm the payment/i);
  assert.doesNotMatch(unconfirmed.text, /you were not charged|refund|Stripe|Firestore|payment_failed|business_invoice_/i);
  assert.match(failed.html, /circum_wordmark\.png/);
  assert.match(unconfirmed.html, /download-on-the-app-store\.svg/);
});

test("all Gifts variants retain the approved wordmark, links and clean customer copy", () => {
  const variants = [
    templates.giftPaymentConfirmed({recipientName: "Maya", rothAmount: 120}),
    templates.giftPaymentConfirmed({recipientName: "Maya", rothAmount: 25, split: true}),
    templates.giftPaymentProblem({recipientName: "Maya", state: "failed"}),
    templates.giftPaymentProblem({recipientName: "Maya", state: "unconfirmed"}),
    templates.giftApproved({recipientName: "Maya"}),
    templates.giftRejected({recipientName: "Maya"}),
    templates.giftReadyForDelivery({recipientName: "Maya"}),
    templates.giftDelivered({recipientName: "Maya"}),
    templates.giftDelivered({recipientName: "Maya", storyUrl: "https://circumuk.com/story/senderToken"}),
    templates.giftStory({role: "sender", storyUrl: "https://circumuk.com/story/senderToken"}),
    templates.giftStory({role: "recipient", storyUrl: "https://circumuk.com/story/recipientToken"}),
  ];
  for (const copy of variants) {
    assert.equal(copy.senderCategory, "gifts");
    assert.match(copy.html, /circum_wordmark\.png/);
    assert.match(copy.html, /<a href="https:\/\/circumuk\.com\/privacy_policy"[^>]*>Privacy Policy<\/a>/);
    assert.match(copy.html, /<a href="https:\/\/circumuk\.com\/terms"[^>]*>Terms<\/a>/);
    assert.match(copy.html, /<a href="mailto:info@circumuk\.com"[^>]*>Contact us<\/a>/);
    assert.match(copy.html, /https:\/\/apps\.apple\.com\/gb\/app\/circum\/id6463644284/);
    assert.match(copy.html, /https:\/\/play\.google\.com\/store\/apps\/details\?id=com\.circum\.app/);
    assert.match(copy.html, /download-on-the-app-store\.svg/);
    assert.match(copy.html, /en_badge_web_generic\.png/);
    assert.match(copy.html, /<a href="https:\/\/x\.com\/circumuk"[^>]*>X<\/a>/);
    assert.match(copy.html, /<a href="https:\/\/www\.instagram\.com\/circumuk\/"[^>]*>Instagram<\/a>/);
    assert.match(copy.html, /<a href="https:\/\/www\.tiktok\.com\/@circumuk"[^>]*>TikTok<\/a>/);
    assert.match(copy.text, /Download Circum on the App Store:/);
    assert.match(copy.text, /Get Circum on Google Play:/);
    assert.match(copy.text, /Follow Circum on X: https:\/\/x\.com\/circumuk/);
    assert.doesNotMatch(customerFields(copy), /giftPaymentDrafts|gift_roth_|submitted_for_review|paymentStatus|gift_story_ready|payment-problem|Firestore|Eventarc|Cloud Run|queue IDs|provider IDs|refund/i);
    assert.doesNotMatch(customerFields(copy), /[a-z][a-z0-9]*_[a-z0-9_]+/i);
  }
  assert.match(variants[0].text, /120 Roth for your Gift to Maya/);
  const deliveredWithStory = variants.find((copy) => copy.templateId === "gift-delivered" && copy.ctaLabel === "View the Gift Story");
  const recipientStory = variants.find((copy) => copy.templateId === "gift-story-recipient");
  assert.match(deliveredWithStory.text, /This confirms the gift delivery/);
  assert.match(deliveredWithStory.text, /View the Gift Story: https:\/\/circumuk\.com\/story\/senderToken/);
  assert.doesNotMatch(recipientStory.text, /Roth|£/);
});

test("Gift payment-problem variants never make an unproven financial statement", () => {
  for (const state of ["failed", "unconfirmed"]) {
    const copy = templates.giftPaymentProblem({recipientName: "Maya", state});
    assert.match(copy.text, /review your Gift|see the next step/i);
    assert.doesNotMatch(copy.text, /weren't charged|not charged|refund|refunded|refund issued|charged again/i);
    assert.equal(copy.ctaUrl, "https://circumuk.com/?app=gifts");
  }
});
