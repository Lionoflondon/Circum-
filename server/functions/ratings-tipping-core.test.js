/* eslint-disable max-len */
"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const core = require("./ratings-tipping-core");

const delivery = {
  status: "completed",
  senderId: "sender-1",
  riderId: "rider-1",
  completedAt: new Date(),
};

test("completed delivery ownership and rider are required", () => {
  assert.equal(core.assertCompletedDelivery(delivery, "sender-1").riderId, "rider-1");
  assert.throws(() => core.assertCompletedDelivery(delivery, "sender-2"), /delivery-not-owned/);
  assert.throws(() => core.assertCompletedDelivery({...delivery, status: "in_transit"}, "sender-1"), /delivery-not-completed/);
});

test("rating is integral, bounded and feedback is server limited", () => {
  assert.deepEqual(core.normalizeRatingInput({stars: 5, feedback: "Careful", feedbackTags: ["Careful Handling"]}), {
    stars: 5, feedback: "Careful", feedbackTags: ["Careful Handling"],
  });
  assert.throws(() => core.normalizeRatingInput({stars: 4.5}), /invalid-rating/);
  assert.throws(() => core.normalizeRatingInput({stars: 5, feedback: "x".repeat(501)}), /feedback-too-long/);
});

test("tip methods and pence limits are canonical", () => {
  assert.deepEqual(core.normalizeTipInput({amountPence: 500, paymentMethod: "Apple Pay"}), {
    amountPence: 500, amount: 5, paymentMethod: "apple_pay",
  });
  assert.throws(() => core.normalizeTipInput({amountPence: 0, paymentMethod: "roth"}), /invalid-tip-amount/);
  assert.throws(() => core.normalizeTipInput({amountPence: 500, paymentMethod: "cash"}), /invalid-payment-method/);
});

test("rating distribution and tip averages update without client math", () => {
  assert.deepEqual(core.nextRatingStats({averageRating: 4, totalRatings: 2, fiveStarCount: 1}, 5), {
    ratingSum: 13, averageRating: 4.33, rating: 4.33, totalRatings: 3, fiveStarCount: 2,
  });
  assert.deepEqual(core.nextTipStats({tipTotal: 5, tipCount: 1}, 3), {
    tipTotal: 8, tipsTotal: 8, tipCount: 2, averageTip: 4,
  });
});

 test("ratings reject coerced and out-of-range stars and invalid tags", () => {
  for (const stars of [0, 6, -1, 4.5, NaN, Infinity, true, "5", null]) {
    assert.throws(() => core.normalizeRatingInput({stars}), /invalid-rating/);
  }
  assert.throws(() => core.normalizeRatingInput({stars: 5, feedbackTags: ["forged"]}), /invalid-feedback-tag/);
});

test("tip input rejects non-integer money and currency mismatch", () => {
  for (const amountPence of [-1, 10001, 100.5, NaN, Infinity, "500", true]) {
    assert.throws(() => core.normalizeTipInput({amountPence, paymentMethod: "card"}), /invalid-tip-amount/);
  }
  assert.throws(() => core.normalizeTipInput({amountPence: 500, paymentMethod: "card", currency: "USD"}), /invalid-tip-currency/);
});

test("safe category labels support every delivery family and combinations without projecting payloads", () => {
  const cases = [
    [{serviceType: "standard"}, ["Standard"]], [{serviceType: "health_plus"}, ["Health+"]],
    [{serviceType: "gift"}, ["Gift"]], [{businessMode: true}, ["Business"]],
    [{isScheduled: true}, ["Scheduled"]], [{serviceType: "vanguard"}, ["Vanguard"]],
    [{serviceType: "heavy"}, ["Heavy"]], [{serviceType: "health_plus", isScheduled: true}, ["Health+", "Scheduled"]],
    [{serviceType: "gift", isScheduled: true}, ["Gift", "Scheduled"]],
    [{businessMode: true, isScheduled: true}, ["Business", "Scheduled"]],
    [{serviceType: "health_plus", vanguard: true}, ["Health+", "Vanguard"]],
  ];
  for (const [delivery, expected] of cases) {
    assert.deepEqual(core.ratingCategories({...delivery, prescription: "secret", giftStory: "secret", voiceNote: "secret", invoice: "secret", address: "secret"}), expected);
  }
});

test("completion cannot be inferred from an ordinary update or conflicting assignment", () => {
  assert.throws(() => core.assertCompletedDelivery({...delivery, completedAt: null, updatedAt: new Date()}, "sender-1"), /rating-window-closed/);
  assert.throws(() => core.assertCompletedDelivery({...delivery, assignedRiderId: "other"}, "sender-1"), /delivery-rider-mismatch/);
});

test("feedback rejects non-text payloads and malformed tag lists", () => {
  for (const feedback of [null, 12, {}, []]) assert.throws(() => core.normalizeRatingInput({stars: 5, feedback}), /invalid-feedback/);
  assert.throws(() => core.normalizeRatingInput({stars: 5, feedbackTags: "Safety concern"}), /invalid-feedback-tag/);
});

test("canonical booking timing and Vanguard protocol fields label combined ratings", () => {
  assert.deepEqual(core.ratingCategories({sourceModule: "health_plus", deliveryTime: {type: "scheduled"}, vanguardProtocolEnabled: true}), ["Health+", "Scheduled", "Vanguard"]);
});
