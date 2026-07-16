/* eslint-disable max-len, require-jsdoc */
const test = require("node:test");
const assert = require("node:assert/strict");
const {creditRiderEarnings, earningsCreditId} = require("./rider-earnings");

function fakeDb() {
  const docs = new Map([["payments/rider-1", {accountBalance: 10, bankAccountLast4: "4242"}]]);
  const ref = (path) => ({
    path,
    id: path.split("/").pop(),
  });
  return {
    docs,
    collection(name) {
      return {doc: (id) => ref(`${name}/${id}`)};
    },
    async runTransaction(callback) {
      return callback({
        get: async (reference) => ({exists: docs.has(reference.path), data: () => docs.get(reference.path)}),
        create(reference, value) {
          if (docs.has(reference.path)) throw new Error("already exists");
          docs.set(reference.path, value);
        },
        set(reference, value, options) {
          assert.deepEqual(options, {merge: true});
          const current = docs.get(reference.path) || {};
          const increment = value.accountBalance && Number.isFinite(value.accountBalance.operand) ?
            value.accountBalance.operand : Number(value.accountBalance || 0);
          docs.set(reference.path, {...current, ...value, accountBalance: Number(current.accountBalance || 0) + increment});
        },
      });
    },
  };
}

test("concurrent delivery credits add without losing either update and preserve fields", async () => {
  const db = fakeDb();
  await Promise.all([
    creditRiderEarnings({db, riderId: "rider-1", deliveryId: "a", amount: 5, now: 1}),
    creditRiderEarnings({db, riderId: "rider-1", deliveryId: "b", amount: 7, now: 1}),
  ]);
  assert.equal(db.docs.get("payments/rider-1").accountBalance, 22);
  assert.equal(db.docs.get("payments/rider-1").bankAccountLast4, "4242");
});

test("retrying a delivery completion never credits twice", async () => {
  const db = fakeDb();
  const first = await creditRiderEarnings({db, riderId: "rider-1", deliveryId: "a", amount: 5, now: 1});
  const retry = await creditRiderEarnings({db, riderId: "rider-1", deliveryId: "a", amount: 5, now: 1});
  assert.equal(first.credited, true);
  assert.equal(retry.duplicate, true);
  assert.equal(db.docs.get("payments/rider-1").accountBalance, 15);
  assert.equal(earningsCreditId("a"), "delivery_a");
});
