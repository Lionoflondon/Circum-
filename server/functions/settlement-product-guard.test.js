const test = require("node:test");
const assert = require("node:assert/strict");
const {
  lifecycleSettlementAllowed,
  settlementProduct,
  standardSettlementAllowed,
} = require("./settlement-product-guard");

test("Standard and Business may use the canonical settlement path", () => {
  assert.equal(standardSettlementAllowed({serviceType: "standard"}), true);
  assert.equal(standardSettlementAllowed({businessMode: true, businessId: "b1"}), true);
});

test("Health+ and Gifts cannot enter Standard settlement", () => {
  assert.equal(settlementProduct({sourceModule: "health_plus"}), "health_plus");
  assert.equal(settlementProduct({serviceType: "GIFTS"}), "gifts");
  assert.equal(standardSettlementAllowed({sourceModule: "health_plus"}), false);
  assert.equal(standardSettlementAllowed({serviceType: "gifts"}), false);
});

test("Gift and Health+ converge on lifecycle settlement only with canonical Rider payout", () => {
  assert.equal(lifecycleSettlementAllowed({
    serviceType: "GIFTS",
    riderSettlementAuthority: "canonical",
    riderEarning: 12.5,
  }), true);
  assert.equal(lifecycleSettlementAllowed({
    sourceModule: "health_plus",
    riderSettlementAuthority: "canonical",
    riderPayout: 14,
  }), true);
  assert.equal(lifecycleSettlementAllowed({
    serviceType: "GIFTS",
    riderEarning: 12.5,
  }), false);
  assert.equal(lifecycleSettlementAllowed({
    sourceModule: "health_plus",
    riderSettlementAuthority: "canonical",
  }), false);
});

test("ambiguous product identity fails closed", () => {
  assert.equal(settlementProduct({}), "unknown");
  assert.equal(standardSettlementAllowed({}), false);
  assert.equal(lifecycleSettlementAllowed({}), false);
});
