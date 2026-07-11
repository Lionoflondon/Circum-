/* eslint-disable max-len */
const test = require("node:test");
const assert = require("node:assert/strict");
const {
  LEGEND_LIMIT,
  isEligibleLegendDelivery,
  nextLegendNumber,
  legendAwardDecision,
  formatRecognitionNumber,
  recognitionAwardDecision,
  buildRecognitionPatch,
  buildRecognitionRevokePatch,
} = require("./legends-core");

test("only paid completed deliveries qualify", () => {
  assert.equal(isEligibleLegendDelivery({status: "completed", paymentStatus: "paid"}), true);
  assert.equal(isEligibleLegendDelivery({status: "pending", paymentStatus: "paid"}), false);
  assert.equal(isEligibleLegendDelivery({status: "cancelled", paymentStatus: "paid"}), false);
  assert.equal(isEligibleLegendDelivery({status: "completed", paymentStatus: "paid", refunded: true}), false);
});

test("Legend counter stops at 1000 and assigns unique next values", () => {
  assert.equal(LEGEND_LIMIT, 1000);
  assert.equal(nextLegendNumber(0), 1);
  assert.equal(nextLegendNumber(999), 1000);
  assert.equal(nextLegendNumber(1000), null);
});

test("an existing Legend cannot receive another number", () => {
  assert.equal(legendAwardDecision({
    delivery: {status: "completed", paymentStatus: "paid"},
    user: {isLegend: true, legendNumber: 12},
    counter: {totalAwarded: 12, limit: 1500},
  }), null);
});

test("recognition numbers use canonical widths", () => {
  assert.equal(formatRecognitionNumber("legend", 7), "0007");
  assert.equal(formatRecognitionNumber("foundingRider", 12), "0012");
  assert.equal(formatRecognitionNumber("patron", 3), "003");
});

test("Founding Rider and Patron decisions respect limits and duplicates", () => {
  assert.equal(recognitionAwardDecision({type: "foundingRider", counter: {totalAwarded: 999}}), 1000);
  assert.equal(recognitionAwardDecision({type: "foundingRider", counter: {totalAwarded: 1000}}), null);
  assert.equal(recognitionAwardDecision({type: "patron", counter: {totalAwarded: 99}}), 100);
  assert.equal(recognitionAwardDecision({type: "patron", counter: {totalAwarded: 100}}), null);
  assert.equal(recognitionAwardDecision({
    type: "foundingRider",
    subject: {recognitions: {foundingRider: {awarded: true, number: 1}}},
    counter: {totalAwarded: 1},
  }), null);
});

test("recognition patches keep nested canonical fields and flat compatibility fields", () => {
  const patch = buildRecognitionPatch({
    type: "foundingRider",
    number: 42,
    awardedBy: "admin-1",
    source: "admin_manual_grant",
    reason: "Imported founding cohort",
    timestampValue: "SERVER_TIME",
  });
  assert.equal(patch.recognitions.foundingRider.awarded, true);
  assert.equal(patch.recognitions.foundingRider.numberLabel, "0042");
  assert.equal(patch.isFoundingRider, true);
  assert.equal(patch.foundingRiderNumber, 42);

  const revoke = buildRecognitionRevokePatch({
    type: "patron",
    revokedBy: "admin-2",
    reason: "Granted to wrong account",
    timestampValue: "SERVER_TIME",
  });
  assert.equal(revoke.recognitions.patron.awarded, false);
  assert.equal(revoke.isPatron, false);
});

test("sequential awards produce distinct numbers", () => {
  const first = legendAwardDecision({delivery: {status: "completed", paymentStatus: "paid"}, counter: {totalAwarded: 20}});
  const second = legendAwardDecision({delivery: {status: "completed", paymentStatus: "paid"}, counter: {totalAwarded: first}});
  assert.deepEqual([first, second], [21, 22]);
});
