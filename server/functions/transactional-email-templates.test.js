"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const templates = require("./transactional-email-templates");

function customerFields(copy) {
  return [copy.subject, copy.preheader, copy.heading, copy.text, copy.html, copy.ctaLabel, copy.footer]
      .filter(Boolean).join(" ");
}

test("every transactional template has complete customer-facing structure", () => {
  const copies = [
    templates.welcome({displayName: "Vaughn Werner"}),
    templates.bookingConfirmed({reference: "booking-1"}),
    templates.deliveryCompleted({reference: "booking-1"}),
    templates.cancellationSettled({reference: "booking-1"}),
    templates.businessInvoicePaid({reference: "invoice-1"}),
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
    templates.giftDelivered({giftId: "gift-1", recipientName: "Alex", deliveredAt: "24 September 2026"}),
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
    assert.match(copy.html, /<h1>/);
    assert.match(copy.html, /Reply to this email|contact Circum support|The Circum team/);
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

test("welcome copy explains the account, Starter Roth and next step without raw trigger names", () => {
  const copy = templates.welcome({displayName: "Vaughn Werner", amount: 5});
  assert.equal(copy.subject, "Welcome to Circum — £5 Roth has been added to your wallet");
  assert.match(copy.heading, /Welcome to Circum, Vaughn/);
  assert.match(copy.text, /(?:£5\.00 Roth has been added|we’ve added £5\.00 Roth) to your wallet/);
  assert.match(copy.text, /eligible Circum services and deliveries/);
  assert.match(copy.text, /Explore Circum/);
  assert.match(copy.text, /The Circum team/);
  assert.match(copy.html, /circum-welcome\.png/);
  assert.match(copy.html, /alt="Welcome to Circum"/);
  assert.doesNotMatch(customerFields(copy), /roth_movement_completed|sender_|starterRothGrantStatus|Firestore/i);
});
