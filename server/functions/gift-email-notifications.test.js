/* eslint-disable max-len */
const test = require("node:test");
const assert = require("node:assert/strict");
const emails = require("./gift-email-notifications");

test("delivery email is clear and excludes private delivery details", () => {
  const message = emails.giftDeliveryEmail({
    giftId: "gift-123",
    gift: {
      recipientName: "Alex & Sam",
      senderEmail: "sender@example.com",
      deliveryAddress: "1 Private Street, London",
      deliveredAt: "2026-09-22T13:00:00.000Z",
      giftStoryUnlocked: true,
      giftStoryStatus: "unlocked",
      giftStoryAccessToken: "privateSenderToken",
    },
  });
  assert.equal(message.subject, "Your CIRCUM Gift has been delivered");
  assert.match(message.text, /Alex & Sam/);
  assert.match(message.text, /View the Gift Story: https:\/\/circumuk\.com\/story\/privateSenderToken/);
  assert.doesNotMatch(message.text, /Private Street/);
  assert.match(message.html, /Alex &amp; Sam/);
  assert.doesNotMatch(message.html, /Private Street/);
});

test("delivery email identity is deterministic and email addresses are normalized", () => {
  assert.equal(emails.normalizeEmail(" Sender@Example.COM "), "sender@example.com");
  assert.equal(emails.normalizeEmail("not-an-email"), "");
  assert.equal(emails.emailNotificationId("gift/123", "gift_delivered"), "gift_gift_123_gift_delivered");
});

test("gift delivery publisher uses the canonical emailQueue identity", async () => {
  const writes = [];
  const db = {
    collection: (name) => ({
      doc: (id) => ({
        create: async (value) => writes.push({name, id, value}),
        get: async () => ({exists: false}),
      }),
    }),
  };
  const result = await emails.queueGiftDeliveryEmail({
    db,
    giftId: "gift-123",
    gift: {senderEmail: " Sender@Example.COM ", recipientName: "Alex", status: "delivered",
      giftStoryUnlocked: true, giftStoryStatus: "unlocked", giftStoryAccessToken: "privateSenderToken"},
  });
  assert.equal(result, "gift_gift-123_gift_delivered");
  assert.equal(writes.length, 1);
  assert.equal(writes[0].name, "emailQueue");
  assert.equal(writes[0].id, result);
  assert.equal(writes[0].value.sourceCollection, "giftRequests");
  assert.equal(writes[0].value.sourceRequiredStatus, "delivered");
  assert.equal(writes[0].value.sourceRecipientField, "senderEmail");
  assert.equal(writes[0].value.sourceStoryRole, "sender");
  assert.equal(writes[0].value.ctaUrl, "https://circumuk.com/story/privateSenderToken");
  assert.equal(writes[0].value.senderCategory, "gifts");
  assert.equal(writes[0].value.to, "sender@example.com");
});

test("delivered email waits for Story unlock", async () => {
  const db = {collection: () => {
throw new Error("email must not queue");
}};
  assert.equal(await emails.queueGiftDeliveryEmail({db, giftId: "gift-1", gift: {status: "delivered", senderEmail: "sender@example.test"}}), null);
});
