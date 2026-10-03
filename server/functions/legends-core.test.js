/* eslint-disable max-len */
const test = require("node:test");
const assert = require("node:assert/strict");
const {isEligibleLegendDelivery, nextLegendNumber, legendAwardDecision} = require("./legends-core");

test("only paid completed deliveries qualify", () => {
  assert.equal(isEligibleLegendDelivery({status: "completed", paymentStatus: "paid"}), true);
  assert.equal(isEligibleLegendDelivery({status: "pending", paymentStatus: "paid"}), false);
  assert.equal(isEligibleLegendDelivery({status: "cancelled", paymentStatus: "paid"}), false);
  assert.equal(isEligibleLegendDelivery({status: "completed", paymentStatus: "paid", refunded: true}), false);
  assert.equal(isEligibleLegendDelivery({status: "completed", paymentStatus: "paid", refundStatus: "partially_refunded"}), false);
});

test("counter stops at 1500 and assigns unique next values", () => {
  assert.equal(nextLegendNumber(0), 1);
  assert.equal(nextLegendNumber(1499), 1500);
  assert.equal(nextLegendNumber(1500), null);
});

test("an existing Legend cannot receive another number", () => {
  assert.equal(legendAwardDecision({
    delivery: {status: "completed", paymentStatus: "paid"},
    user: {isLegend: true, legendNumber: 12},
    counter: {totalAwarded: 12, limit: 1500},
  }), null);
});

test("sequential awards produce distinct numbers", () => {
  const first = legendAwardDecision({delivery: {status: "completed", paymentStatus: "paid"}, counter: {totalAwarded: 20}});
  const second = legendAwardDecision({delivery: {status: "completed", paymentStatus: "paid"}, counter: {totalAwarded: first}});
  assert.deepEqual([first, second], [21, 22]);
});

test("recovered recognition helpers preserve published founding/patron fields and the current Legend cap", () => {
 const {RECOGNITION_CONFIG, recognitionConfig, recognitionAwardDecision, buildRecognitionPatch, buildRecognitionRevokePatch} = require("./legends-core");
 assert.equal(RECOGNITION_CONFIG.legend.limit, 1500); assert.equal(recognitionConfig("foundingRider").limit, 1000); assert.equal(recognitionConfig("patron").limit, 100);
 assert.equal(recognitionAwardDecision({type: "foundingRider", counter: {totalAwarded: 999}}), 1000);
 assert.equal(recognitionAwardDecision({type: "foundingRider", counter: {totalAwarded: 1000}}), null);
 assert.equal(recognitionAwardDecision({type: "patron", counter: {totalAwarded: 100}}), null);
 assert.equal(recognitionAwardDecision({type: "foundingRider", subject: {isFoundingRider: true}}), null);
 const patch = buildRecognitionPatch({type: "foundingRider", number: 42, awardedBy: "system", source: "rider_application_accepted", timestampValue: "test-time"});
 assert.equal(patch.isFoundingRider, true); assert.equal(patch.foundingRiderNumber, 42); assert.equal(patch.recognitions.foundingRider.numberLabel, "0042");
 assert.equal(buildRecognitionRevokePatch({type: "patron"}).isPatron, false);
 assert.throws(() => recognitionConfig("unknown"), /Unsupported/);
});
