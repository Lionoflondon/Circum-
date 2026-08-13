const test = require("node:test");
const assert = require("node:assert/strict");
const {allocateGiftBudget, budgetPenceFromGbp, createGiftBudgetAuthority} = require("./gift-budget-authority");

test("Gift budget conversion is finite and pence-precise", () => {
  assert.equal(budgetPenceFromGbp(50), 5000);
  assert.equal(budgetPenceFromGbp(50.005), 5001);
  assert.equal(budgetPenceFromGbp(Infinity), 0);
  assert.equal(budgetPenceFromGbp("not-a-budget"), 0);
});

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
