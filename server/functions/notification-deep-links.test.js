const assert = require("node:assert/strict");
const test = require("node:test");
const {
  canonicalDeepLink,
  normalizeDeepLink,
  safeId,
} = require("./notification-deep-links");

test("the currently emitted Sender families use one allowlisted contract", () => {
  const cases = [
    ["delivery_created", {deliveryId: "delivery-1"}, "tracking"],
    ["delivery_accepted", {bookingId: "delivery-1"}, "tracking"],
    ["delivery_completed", {requestId: "delivery-1"}, "tracking"],
    ["delivery_cancelled", {deliveryId: "delivery-1"}, "tracking"],
    ["delivery_adjustment_review", {requestId: "delivery-1", adjustmentId: "adjustment-1"}, "tracking"],
    ["delivery_adjustment", {bookingId: "delivery-1", adjustmentId: "adjustment-1"}, "tracking"],
    ["rider_unavailable", {deliveryId: "delivery-1"}, "tracking"],
    ["connection", {requestId: "delivery-1"}, "tracking"],
    ["chat_message", {chatId: "chat-1", bookingId: "delivery-1"}, "conversation"],
    ["payment_successful", {bookingId: "delivery-1"}, "tracking"],
    ["payment_failed", {bookingId: "delivery-1"}, "tracking"],
    ["wallet_payment", {transactionId: "wallet-tx-1"}, "wallet"],
    ["roth_purchase_completed", {transactionId: "roth-tx-1"}, "wallet"],
    ["referral_reward", {referralId: "referral-1"}, "wallet"],
    ["gift_submitted", {giftId: "gift-1"}, "gift"],
    ["gift_story_ready", {giftId: "gift-1", action: "story"}, "gift"],
    ["business_invoice_payment", {businessId: "business-1", invoiceId: "invoice-1"}, "business"],
    ["health_plus_status", {healthPickupId: "pickup-1"}, "health"],
    ["sender_trust_updated", {route: "profile"}, "profile"],
    ["system_announcement", {}, "notifications"],
  ];
  for (const [type, data, route] of cases) {
    const destination = canonicalDeepLink(type, data, "sender");
    assert.equal(destination.version, 1, type);
    assert.equal(destination.route, route, type);
  }
});

test("legacy fields normalize into canonical entity keys", () => {
  assert.deepEqual(normalizeDeepLink(null, {
    type: "gift_story_ready",
    data: {giftId: "gift-1"},
  }), {version: 1, route: "gift", giftId: "gift-1"});
  assert.deepEqual(normalizeDeepLink({route: "tracking", bookingId: "delivery-1"}, {
    type: "delivery_completed",
    data: {},
  }), {version: 1, route: "tracking", deliveryId: "delivery-1", bookingId: "delivery-1"});
});

test("unsafe ids, arbitrary URLs, and missing references never become actions", () => {
  assert.equal(safeId("delivery/other"), "");
  assert.deepEqual(canonicalDeepLink("delivery_completed", {
    deliveryId: "delivery/other",
    route: "https://example.invalid",
  }), {version: 1, route: "activity"});
  assert.deepEqual(canonicalDeepLink("chat_message", {}), {version: 1, route: "notifications"});
  assert.deepEqual(canonicalDeepLink("delivery_completed", {}), {version: 1, route: "activity"});
});
