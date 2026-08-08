const test = require("node:test");
const assert = require("node:assert/strict");
const {allocateGiftBudget, createGiftBudgetAuthority} = require("./gift-budget-authority");

test("Gift allocations cannot exceed the submitted budget", () => {
  let ledger = createGiftBudgetAuthority(5000);
  ledger = allocateGiftBudget(ledger, "procurement", 3500);
  ledger = allocateGiftBudget(ledger, "rider", 1500);
  assert.equal(ledger.customerLiabilityPence, 5000);
  assert.throws(() => allocateGiftBudget(ledger, "toll", 1), /exceeds/);
});

test("Gift budget allocation is retry-safe when the same allocation is not reposted", () => {
  let ledger = createGiftBudgetAuthority(2000);
  ledger = allocateGiftBudget(ledger, "procurement", 2000);
  assert.equal(ledger.remainingPence, 0);
});
