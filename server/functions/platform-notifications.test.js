const test = require("node:test");
const assert = require("node:assert/strict");
const {
  giftNotificationRecord,
  giftNotificationRecordsForTransition,
  _private,
} = require("./platform-notifications");

test("Gifts in-app notification record is always created", () => {
  const record = giftNotificationRecord({
    userId: "sender-1",
    email: "sender@example.com",
    giftId: "gift-1",
    giftType: "send_to_someone",
    eventType: "payment_succeeded",
    title: "Payment confirmed",
    body: "Your gift is secured.",
    channel: "in_app",
    createdAt: "now",
  });
  assert.equal(record.notificationId, "gift-1_payment_succeeded_in_app");
  assert.equal(record.deliveryStatus, "pending");
  assert.equal(record.channel, "in_app");
});

test("Gifts email and push mark skipped when providers are not configured", () => {
  const email = giftNotificationRecord({
    userId: "sender-1",
    email: "sender@example.com",
    giftId: "gift-1",
    giftType: "campaign",
    eventType: "campaign_match_found",
    title: "Match found",
    body: "A policy-safe match has been found.",
    channel: "email",
  });
  const push = giftNotificationRecord({
    userId: "sender-1",
    email: "sender@example.com",
    giftId: "gift-1",
    giftType: "campaign",
    eventType: "campaign_match_found",
    title: "Match found",
    body: "A policy-safe match has been found.",
    channel: "push",
  });
  assert.equal(email.deliveryStatus, "skipped");
  assert.equal(email.failureReason, "email_not_configured");
  assert.equal(push.deliveryStatus, "skipped");
  assert.equal(push.failureReason, "push_not_configured");
});

test("Gifts transition creates all channel records without private data", () => {
  const records = giftNotificationRecordsForTransition({
    userId: "sender-1",
    email: "sender@example.com",
    giftId: "gift-1",
    giftType: "anonymous",
    eventType: "story_unlocked",
    title: "Gift Story unlocked",
    body: "Your Gift Story is ready.",
    createdAt: "now",
  });
  assert.equal(records.length, 3);
  assert.deepEqual(records.map((record) => record.channel), ["in_app", "email", "push"]);
  assert.equal(records.some((record) => "matchedParticipantBudget" in record), false);
  assert.equal(records.some((record) => "internalNotes" in record), false);
});

test("Gift request statuses map to backend-owned notification events", () => {
  assert.deepEqual(
      _private.giftStatusNotification("submitted_for_review"),
      ["gift_submitted", "Gift submitted", "Your gift request has been sent to the Circum team."],
  );
  assert.deepEqual(
      _private.giftStatusNotification("paid_waiting_for_match"),
      ["campaign_waiting_for_match", "Gift match requested", "We are looking for a compatible gift match."],
  );
  assert.equal(_private.giftStatusNotification("draft"), null);
});

test("no-show lifecycle emits one canonical system message", () => {
  assert.equal(
      _private.deliverySystemMessage("sender_no_show_pickup"),
      "Pickup was marked as missed after the collection wait.",
  );
  assert.equal(_private.deliverySystemMessage("waiting"), null);
});

test("backend lifecycle messages do not emit duplicate chat notifications", () => {
  assert.equal(_private.isBackendSystemMessage({
    senderId: "circum-system",
    senderRole: "system",
    messageType: "system",
  }), true);
  assert.equal(_private.isBackendSystemMessage({
    senderId: "sender-1",
    senderRole: "sender",
    messageType: "text",
  }), false);
});
