const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const policy = require("./canonical-weight-policy");

test("canonical five-band policy is shared and effective at exact boundaries", () => {
  assert.deepEqual(policy.WEIGHT_BANDS.map((band) => [band.label, band.maxKg, band.surchargeGbp]), [
    ["Small Parcel", 5, 0],
    ["Medium Parcel", 10, 3],
    ["Heavy Parcel", 20, 7],
    ["Large Item", 40, 15],
    ["Extra Heavy", null, 25],
  ]);
  assert.deepEqual([0.01, 5, 5.01, 10, 10.01, 20, 20.01, 40, 40.01].map((value) => policy.weightBandFor(value).id), [
    "small_parcel", "small_parcel", "medium_parcel", "medium_parcel", "heavy_parcel", "heavy_parcel", "large_item", "large_item", "extra_heavy",
  ]);
});

test("paid weight authority comes only from a complete versioned quote snapshot", () => {
  const quote = {
    weightKg: 8,
    weightBand: policy.weightBandFor(8),
    weightPolicyVersion: policy.WEIGHT_POLICY_VERSION,
    pricingSnapshotVersion: policy.PRICING_SNAPSHOT_VERSION,
    total: 21.35,
  };
  assert.equal(policy.paidWeightSnapshot({pricingBreakdown: quote}).weightKg, 8);
  assert.equal(policy.paidWeightSnapshot({weightKg: 8, paidWeightKg: 8}), null);
  assert.equal(policy.paidWeightSnapshot({pricingBreakdown: {...quote, weightBand: policy.weightBandFor(2)}}), null);
  assert.equal(policy.paidWeightSnapshot({pricingBreakdown: {...quote, pricingSnapshotVersion: null}}), null);
});

test("backend pricing, IRIS, and Health+ import one weight policy", () => {
  for (const file of ["sender-booking.js", "iris-core.js", "health-plus-core.js"]) {
    const source = fs.readFileSync(path.join(__dirname, file), "utf8");
    assert.match(source, /canonical-weight-policy/, `${file} must import canonical weight policy`);
  }
  const iris = fs.readFileSync(path.join(__dirname, "iris-core.js"), "utf8");
  const health = fs.readFileSync(path.join(__dirname, "health-plus-core.js"), "utf8");
  assert.doesNotMatch(iris, /const WEIGHT_BANDS = Object\.freeze\(\[/);
  assert.doesNotMatch(health, /const WEIGHT_BANDS = \[/);
});

test("weight repricing preserves every non-weight quote component", () => {
  const original = {
    quoteId: "quote-1",
    weightKg: 4,
    weightSurcharge: 0,
    distanceFare: 12,
    roadCharges: {customerAmount: 9},
    lineItems: [{key: "weight", amount: 0}, {key: "road_charge", amount: 9}],
    total: 28,
    riderBaseShare: 12,
    circumBaseShare: 4,
    riderPayout: 12,
  };
  const revised = policy.repriceWeightFromQuote(original, 12);
  assert.equal(revised.total, 35);
  assert.equal(revised.weightSurcharge, 7);
  assert.equal(revised.weightBand.label, "Heavy Parcel");
  assert.equal(revised.distanceFare, 12);
  assert.deepEqual(revised.roadCharges, original.roadCharges);
  assert.equal(revised.lineItems.find((item) => item.key === "road_charge").amount, 9);
  assert.equal(revised.riderPayout, 17.25);
  assert.equal(revised.riderBaseShare, 17.25);
});
