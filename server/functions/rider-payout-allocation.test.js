/* eslint-disable max-len */
const test = require("node:test");
const assert = require("node:assert/strict");
const {fifoAllocations} = require("./rider-payout-allocation");
const rows = [
  {earningId: "base", path: "riderEarningTransactions/base", deliveryId: "d", type: "delivery_earning", amountPence: 650, createdMillis: 1},
  {earningId: "tip", path: "riderWalletTransactions/tip", deliveryId: "d", tipId: "d", type: "tip", amountPence: 500, createdMillis: 2},
];
test("FIFO preserves separate delivery and tip identity and exact minor units", () => {
  const first = fifoAllocations(rows, [], 800);
  assert.deepEqual(first.map((r) => [r.earningId, r.amountPence]), [["base", 650], ["tip", 150]]);
  const second = fifoAllocations(rows, first.map((r) => ({...r, state: "paid"})), 350);
  assert.deepEqual(second.map((r) => [r.earningId, r.amountPence]), [["tip", 350]]);
  assert.throws(() => fifoAllocations(rows, [...first, ...second].map((r) => ({...r, state: "paid"})), 1), /reconciliation/);
});
test("released allocations can be reused and refunded tips cannot", () => {
  assert.equal(fifoAllocations(rows, [{earningId: "base", amountPence: 650, state: "released"}], 650)[0].earningId, "base");
  assert.throws(() => fifoAllocations([rows[0], {...rows[1], reversedPence: 500}], [], 651), /reconciliation/);
});
