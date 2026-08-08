const test = require("node:test");
const assert = require("node:assert/strict");
const {settlementProduct, standardSettlementAllowed} = require("./settlement-product-guard");

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

test("ambiguous product identity fails closed", () => {
  assert.equal(settlementProduct({}), "unknown");
  assert.equal(standardSettlementAllowed({}), false);
});
