const test = require("node:test");
const assert = require("node:assert/strict");
const {
  BALANCE_TYPES,
  TRANSACTION_TYPES,
  canWithdraw,
  isRothCreditWithdrawable,
  nextBalance,
} = require("./roth-ledger-core");

test("Roth credit is not withdrawable", () => {
  assert.equal(isRothCreditWithdrawable(), false);
  assert.equal(canWithdraw(BALANCE_TYPES.rothCredit), false);
  assert.equal(canWithdraw(BALANCE_TYPES.pendingEarnings), false);
  assert.equal(canWithdraw(BALANCE_TYPES.availableEarnings), true);
});

test("Roth credit cannot go negative unless reversal is explicit", () => {
  assert.throws(() => nextBalance({
    balanceBefore: 10,
    amount: -20,
    type: TRANSACTION_TYPES.adminDebit,
  }), /cannot go negative/);
  assert.equal(nextBalance({
    balanceBefore: 10,
    amount: -20,
    type: TRANSACTION_TYPES.reversal,
  }), -10);
});
