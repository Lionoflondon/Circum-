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
    averageRating: 4.33, rating: 4.33, ratingTotal: 13, totalRatings: 3, fiveStarCount: 2,
  });
  assert.deepEqual(core.nextTipStats({tipTotal: 5, tipCount: 1}, 3), {
    tipTotal: 8, tipsTotal: 8, tipCount: 2, averageTip: 4,
  });
});

test("canonical compliments are bounded and private text remains optional", () => {
  assert.deepEqual(core.normalizeRatingInput({stars: 4, feedbackTags: ["On time", "Great communication"]}), {
    stars: 4, feedback: "", feedbackTags: ["On time", "Great communication"],
  });
  assert.throws(() => core.normalizeRatingInput({stars: 5, feedbackTags: ["Invented claim"]}), /invalid-feedback-tag/);
});
