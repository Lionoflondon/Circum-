/* eslint-disable max-len */
const test = require("node:test");
const assert = require("node:assert/strict");
const {
  isEligibleLegendDelivery,
  nextLegendNumber,
  legendAwardDecision,
  recognitionAwardDecision,
  buildRecognitionPatch,
  buildRecognitionRevokePatch,
} = require("./legends-core");

test("only paid completed deliveries qualify", () => {
  assert.equal(isEligibleLegendDelivery({status: "completed", paymentStatus: "paid"}), true);
  assert.equal(isEligibleLegendDelivery({status: "pending", paymentStatus: "paid"}), false);
  assert.equal(isEligibleLegendDelivery({status: "cancelled", paymentStatus: "paid"}), false);
  assert.equal(isEligibleLegendDelivery({status: "completed", paymentStatus: "paid", refunded: true}), false);
  assert.equal(isEligibleLegendDelivery({status: "completed", paymentStatus: "paid", refundStatus: "partially_refunded"}), false);
});

test("counter stops at 1000 and assigns unique next values", () => {
  assert.equal(nextLegendNumber(0), 1);
  assert.equal(nextLegendNumber(999), 1000);
  assert.equal(nextLegendNumber(1000), null);
});

test("an existing Legend cannot receive another number", () => {
  assert.equal(legendAwardDecision({
    delivery: {status: "completed", paymentStatus: "paid"},
    user: {isLegend: true, legendNumber: 12},
    counter: {totalAwarded: 12, limit: 1000},
  }), null);
});

test("sequential awards produce distinct numbers", () => {
  const first = legendAwardDecision({delivery: {status: "completed", paymentStatus: "paid"}, counter: {totalAwarded: 20}});
  const second = legendAwardDecision({delivery: {status: "completed", paymentStatus: "paid"}, counter: {totalAwarded: first}});
  assert.deepEqual([first, second], [21, 22]);
});

test("recognition patches keep Founding Rider separate from rank and Trust Points", () => {
  const patch = buildRecognitionPatch({
    type: "foundingRider",
    number: 1,
    awardedBy: "system",
    source: "first_approved_work_ready_riders",
    reason: "First 1000 approved CIRCUM Riders.",
    timestampValue: "SERVER_TIME",
  });
  assert.equal(patch.isFoundingRider, true);
  assert.equal(patch.foundingRiderNumber, 1);
  assert.equal(patch.recognitions.foundingRider.awarded, true);
  assert.equal(Object.hasOwn(patch, "rank"), false);
  assert.equal(Object.hasOwn(patch, "riderRank"), false);
  assert.equal(Object.hasOwn(patch, "trustPoints"), false);
});

test("Legend and Patron projections remain surface-specific", () => {
  const legendPatch = buildRecognitionPatch({
    type: "legend",
    number: 12,
    awardedBy: "system",
    source: "first_completed_delivery",
    reason: "Sender recognition",
    timestampValue: "SERVER_TIME",
  });
  const patronPatch = buildRecognitionPatch({
    type: "patron",
    number: 3,
    awardedBy: "system",
    source: "first_business_payment",
    reason: "Business recognition",
    timestampValue: "SERVER_TIME",
  });
  assert.equal(legendPatch.isLegend, true);
  assert.equal(legendPatch.recognitions.legend.awarded, true);
  assert.equal(Object.hasOwn(legendPatch, "isFoundingRider"), false);
  assert.equal(Object.hasOwn(legendPatch, "isPatron"), false);
  assert.equal(patronPatch.isPatron, true);
  assert.equal(patronPatch.recognitions.patron.awarded, true);
  assert.equal(Object.hasOwn(patronPatch, "isLegend"), false);
  assert.equal(Object.hasOwn(patronPatch, "isFoundingRider"), false);
});

test("recognition award decision respects existing recognition state", () => {
  assert.equal(recognitionAwardDecision({
    type: "foundingRider",
    subject: {recognitions: {foundingRider: {awarded: true}}},
    counter: {totalAwarded: 1},
  }), null);
  assert.equal(recognitionAwardDecision({
    type: "patron",
    subject: {isPatron: true},
    counter: {totalAwarded: 1},
  }), null);
  assert.equal(recognitionAwardDecision({
    type: "legend",
    subject: {},
    counter: {totalAwarded: 1},
  }), 2);
});

test("recognition revoke patch does not mutate rank or Trust Points", () => {
  const patch = buildRecognitionRevokePatch({
    type: "foundingRider",
    revokedBy: "admin-1",
    reason: "test",
    timestampValue: "SERVER_TIME",
  });
  assert.equal(patch.isFoundingRider, false);
  assert.equal(patch.recognitions.foundingRider.awarded, false);
  assert.equal(Object.hasOwn(patch, "rank"), false);
  assert.equal(Object.hasOwn(patch, "trustPoints"), false);
});
