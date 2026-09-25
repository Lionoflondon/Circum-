"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {reconcileGiftById, scanGiftRecoveryPage} = require("./gift-email-reconciliation");

function fakeDb(initial = {}) {
  const values = new Map(Object.entries(initial));
  const queryFor = (name, field, operator, expected, afterId = "", max = 50) => ({
    orderBy: () => queryFor(name, field, operator, expected, afterId, max),
    startAfter: (id) => queryFor(name, field, operator, expected, id, max),
    limit: (count) => queryFor(name, field, operator, expected, afterId, count),
    get: async () => ({docs: [...values.entries()].filter(([key, value]) => {
      if (!key.startsWith(`${name}/`) || key.slice(name.length + 1) <= afterId) return false;
      return operator === "in" ? expected.includes(value[field]) : value[field] === expected;
    }).sort(([a], [b]) => a.localeCompare(b)).slice(0, max).map(([key, value]) => ({
      id: key.slice(name.length + 1), data: () => value,
    }))}),
  });
  return {
    collection: (name) => ({where: (field, operator, expected) => queryFor(name, field, operator, expected), doc: (id) => ({
      get: async () => ({exists: values.has(`${name}/${id}`), data: () => values.get(`${name}/${id}`)}),
      create: async (value) => {
        const key = `${name}/${id}`;
        if (values.has(key)) throw Object.assign(new Error("Already exists"), {code: 6});
        values.set(key, value);
      },
      set: async (value, options = {}) => {
        const key = `${name}/${id}`;
        values.set(key, options.merge ? {...(values.get(key) || {}), ...value} : value);
      },
    })}),
    read: (name, id) => values.get(`${name}/${id}`),
    count: (name) => [...values.keys()].filter((key) => key.startsWith(`${name}/`)).length,
  };
}

test("targeted reconciliation detects and repairs missing payment communication without financial writes", async () => {
  const db = fakeDb({
    "giftRequests/g-1": {status: "submitted_for_review", paymentStatus: "paid", senderEmail: "sender@example.test",
      recipientName: "Maya", walletContributionGbp: 120, remainingStripeAmountGbp: 0},
    "walletTransactions/gift_roth_g-1": {status: "completed", amount: -120, referenceId: "g-1"},
  });
  const inspection = await reconcileGiftById({db, giftId: "g-1"});
  assert.equal(inspection.missingPayment, true);
  assert.equal(db.count("emailQueue"), 0);
  const first = await reconcileGiftById({db, giftId: "g-1", repair: true});
  assert.equal(first.paymentPublication, "queued");
  const second = await reconcileGiftById({db, giftId: "g-1", repair: true});
  assert.equal(second.missingPayment, false);
  assert.equal(db.count("emailQueue"), 1);
  assert.equal(db.read("walletTransactions", "gift_roth_g-1").amount, -120);
});

test("targeted reconciliation repairs missing Story messages with the original tokens", async () => {
  const senderToken = "s".repeat(43);
  const recipientToken = "r".repeat(43);
  const db = fakeDb({"giftRequests/g-2": {status: "delivered", giftStoryUnlocked: true,
    giftStoryStatus: "unlocked", senderEmail: "sender@example.test", recipientEmail: "recipient@example.test",
    giftStoryAccessToken: senderToken, recipientStoryToken: recipientToken, recipientName: "Maya"}});
  const result = await reconcileGiftById({db, giftId: "g-2", repair: true});
  assert.equal(result.storyPublication, "published");
  assert.equal(db.count("emailQueue"), 3);
  assert.equal(db.read("emailQueue", "gift_g-2_gift_delivered").ctaUrl, `https://circumuk.com/story/${senderToken}`);
  assert.equal(db.read("emailQueue", "gift_story_g-2_recipient").ctaUrl, `https://circumuk.com/story/${recipientToken}`);
  assert.equal((await reconcileGiftById({db, giftId: "g-2"})).missingStory, false);
});

test("targeted reconciliation identifies a completed delivery needing Story recovery", async () => {
  const db = fakeDb({
    "giftRequests/g-3": {status: "approved", deliveryId: "d-3"},
    "deliveryRequests/d-3": {status: "completed", sourceModule: "gifts", giftRequestId: "g-3"},
  });
  const result = await reconcileGiftById({db, giftId: "g-3"});
  assert.equal(result.completedDeliveryNeedsStory, true);
  assert.equal(db.count("emailQueue"), 0);
});

test("targeted recovery replays only due Gift queue IDs when explicitly requested", async () => {
  const db = fakeDb({
    "giftRequests/g-4": {status: "delivered", giftStoryStatus: "unlocked", giftStoryUnlocked: true},
    "emailQueue/gift_g-4_gift_delivered": {status: "retryable_failed", nextAttemptAt: {toMillis: () => 100}},
    "emailQueue/gift_story_g-4_sender": {status: "retryable_failed", nextAttemptAt: {toMillis: () => 5000}},
  });
  const seen = [];
  const result = await reconcileGiftById({db, giftId: "g-4", repair: true, replayStuck: true, nowMs: 1000,
    processRecord: async ({emailId}) => {
      seen.push(emailId);
      return {status: "sent"};
    }});
  assert.deepEqual(seen, ["gift_g-4_gift_delivered"]);
  assert.equal(result.replaySent, 1);
});

test("missing email contacts are terminal no-send, not endlessly missing queue candidates", async () => {
  const db = fakeDb({"giftRequests/no-contact": {paymentStatus: "paid", walletContributionGbp: 5,
    status: "delivered", giftStoryUnlocked: true, giftStoryStatus: "unlocked",
    giftStoryAccessToken: "s".repeat(43), recipientStoryToken: "r".repeat(43)}});
  const result = await reconcileGiftById({db, giftId: "no-contact", repair: true});
  assert.equal(result.recipientUnavailable, true);
  assert.equal(result.missingPayment, false);
  assert.equal(result.missingStory, false);
  assert.equal(db.count("emailQueue"), 0);
});

test("bounded read-only scans discover missed paid and completed-delivery recovery candidates", async () => {
  const db = fakeDb({
    "giftRequests/a": {paymentStatus: "paid", walletContributionGbp: 10, status: "submitted_for_review",
      senderEmail: "sender@example.test"},
    "giftRequests/b": {paymentStatus: "paid", walletContributionGbp: 0, status: "approved"},
    "deliveryRequests/d": {status: "completed", serviceType: "gifts", giftRequestId: "b"},
  });
  const first = await scanGiftRecoveryPage({db, kind: "paid", limit: 1});
  assert.equal(first.examined, 1);
  assert.equal(first.nextAfterId, "a");
  assert.deepEqual(first.candidates.map((item) => item.giftId), ["a"]);
  const second = await scanGiftRecoveryPage({db, kind: "paid", afterId: first.nextAfterId, limit: 1});
  assert.equal(second.examined, 1);
  assert.deepEqual(second.candidates, []);
  const delivery = await scanGiftRecoveryPage({db, kind: "deliveries", limit: 1});
  assert.deepEqual(delivery.candidates, [{giftId: "b", deliveryId: "d", completedDeliveryNeedsStory: true,
    missingGift: false}]);
  assert.equal(db.count("emailQueue"), 0);
  await assert.rejects(scanGiftRecoveryPage({db, kind: "paid", limit: 101}), /Scan limit/);
});
