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
    },
  });
  assert.equal(message.subject, "Your Circum gift was delivered");
  assert.match(message.text, /Alex & Sam/);
  assert.match(message.text, /Gift reference: gift-123/);
  assert.doesNotMatch(message.text, /Private Street/);
  assert.match(message.html, /Alex &amp; Sam/);
  assert.doesNotMatch(message.html, /Private Street/);
});

test("delivery email identity is deterministic and email addresses are normalized", () => {
  assert.equal(emails.normalizeEmail(" Sender@Example.COM "), "sender@example.com");
  assert.equal(emails.normalizeEmail("not-an-email"), "");
  assert.equal(emails.emailNotificationId("gift/123", "gift_delivered"), "gift_gift_123_gift_delivered");
});

test("Resend transport sends a transactional payload with idempotency", async () => {
  const previousKey = process.env.RESEND_API_KEY;
  const previousFrom = process.env.GIFTS_EMAIL_FROM;
  process.env.RESEND_API_KEY = "test-key";
  process.env.GIFTS_EMAIL_FROM = "Circum Gifts <gifts@example.com>";
  let request;
  try {
    const result = await emails.sendResendEmail({
      to: "sender@example.com",
      subject: "Your Circum gift was delivered",
      textBody: "Delivered.",
      htmlBody: "<p>Delivered.</p>",
      idempotencyKey: "gift_gift-123_gift_delivered",
      fetchImpl: async (_url, options) => {
        request = options;
        return {ok: true, status: 200, json: async () => ({id: "email-1"})};
      },
    });
    assert.deepEqual(result, {status: "sent", providerId: "email-1"});
    assert.equal(request.headers.Authorization, "Bearer test-key");
    assert.equal(request.headers["Idempotency-Key"], "gift_gift-123_gift_delivered");
    const payload = JSON.parse(request.body);
    assert.deepEqual(payload.to, ["sender@example.com"]);
    assert.equal(payload.tags[0].value, "gifts");
    assert.equal(payload.tags[1].value, "gift_delivered");
  } finally {
    if (previousKey === undefined) delete process.env.RESEND_API_KEY;
    else process.env.RESEND_API_KEY = previousKey;
    if (previousFrom === undefined) delete process.env.GIFTS_EMAIL_FROM;
    else process.env.GIFTS_EMAIL_FROM = previousFrom;
  }
});

test("unconfigured email provider fails closed without pretending to send", async () => {
  const previousKey = process.env.RESEND_API_KEY;
  delete process.env.RESEND_API_KEY;
  try {
    assert.deepEqual(await emails.sendResendEmail({
      to: "sender@example.com",
      subject: "Subject",
      textBody: "Body",
      htmlBody: "<p>Body</p>",
      idempotencyKey: "idempotent",
      fetchImpl: () => {
        throw new Error("network must not be called");
      },
    }), {status: "skipped", reason: "email_provider_not_configured"});
  } finally {
    if (previousKey === undefined) delete process.env.RESEND_API_KEY;
    else process.env.RESEND_API_KEY = previousKey;
  }
});
