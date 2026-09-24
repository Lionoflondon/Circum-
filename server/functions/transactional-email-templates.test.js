"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {IMPLEMENTED_TEMPLATE_EVENTS, renderTransactionalEmail} = require("./transactional-email-templates");

const contextFor = (eventType) => ({
  displayName: "Alex",
  amount: 5,
  reference: "INV-123",
  recipientName: "Alex & Sam",
  deliveredAt: "1 January 2026",
  decision: eventType === "rider_application_decision" ? "more_information_requested" : "",
  recipientRole: eventType === "gift_story_ready" ? "recipient" : "sender",
  storyUrl: eventType === "gift_story_ready" ? "https://circumuk.com/gift-story/secure-token" : "",
});

function visibleCopy(message) {
  return [message.subject, message.preheader, message.heading, ...(message.body || []), message.cta, message.footer]
      .filter(Boolean).join("\n");
}

function withoutAllowedTechnicalSyntax(value) {
  return value
      .replace(/https?:\/\/[^\s)]+/gi, "")
      .replace(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi, "");
}

test("every implemented transactional template renders the customer contract", () => {
  for (const eventType of IMPLEMENTED_TEMPLATE_EVENTS) {
    const message = renderTransactionalEmail(eventType, contextFor(eventType));
    assert.ok(message.subject, `${eventType} subject`);
    assert.ok(message.preheader, `${eventType} preheader`);
    assert.ok(message.heading, `${eventType} heading`);
    assert.ok(message.body.length > 0, `${eventType} body`);
    assert.ok(message.cta, `${eventType} CTA`);
    assert.ok(message.footer, `${eventType} footer`);
    assert.ok(message.text, `${eventType} text`);
  }
});

test("customer-visible copy contains no internal identifiers or developer strings", () => {
  for (const eventType of IMPLEMENTED_TEMPLATE_EVENTS) {
    const copy = withoutAllowedTechnicalSyntax(visibleCopy(renderTransactionalEmail(eventType, contextFor(eventType))));
    assert.doesNotMatch(copy, /\b[A-Za-z][A-Za-z0-9]*_[A-Za-z0-9_]+\b/, eventType);
    assert.doesNotMatch(copy, /emailQueue|walletTransactions|Firestore|sourceCollection|sender_|rider_|delivery_in_progress|roth_movement_completed/i, eventType);
  }
});

test("starter welcome is distinct from generic Roth activity", () => {
  const welcome = renderTransactionalEmail("sender_welcome", {displayName: "Alex"});
  const ordinary = renderTransactionalEmail("roth_movement_completed", {amount: 5});
  assert.equal(welcome.subject, "Welcome to CIRCUM");
  assert.match(welcome.text, /£5 Roth/);
  assert.doesNotMatch(welcome.text, /wallet has been updated/i);
  assert.match(ordinary.text, /wallet has been updated/i);
  assert.doesNotMatch(ordinary.text, /Welcome to CIRCUM/);
});
