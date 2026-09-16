"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {reserveBusinessRothCheckout} = require("./business-payments")._private;

class MemoryRef {
  constructor(db, path) {
 this.db = db; this.path = path; this.id = path.split("/").pop();
}
}

class MemoryDb {
  constructor() {
 this.records = new Map(); this.queue = Promise.resolve();
}
  collection(name) {
 return {doc: (id) => new MemoryRef(this, `${name}/${id}`)};
}
  async runTransaction(callback) {
    const run = this.queue.then(async () => {
      const writes = [];
      const transaction = {
        get: async (ref) => ({
          exists: this.records.has(ref.path),
          data: () => this.records.get(ref.path),
        }),
        set: (ref, value, options = {}) => writes.push({ref, value, options}),
      };
      const result = await callback(transaction);
      for (const {ref, value, options} of writes) {
        const previous = options.merge ? this.records.get(ref.path) || {} : {};
        this.records.set(ref.path, {...previous, ...value});
      }
      return result;
    });
    this.queue = run.catch(() => {});
    return run;
  }
}

const reserve = (db, overrides = {}) => reserveBusinessRothCheckout({
  db,
  uid: "sender-1",
  businessId: "business-1",
  amount: 50000,
  idempotencyKey: "checkout-request-0001",
  nowMs: 1000,
  ...overrides,
});

test("20 concurrent calls resolve to one logical Business Roth checkout", async () => {
  const db = new MemoryDb();
  const reservations = await Promise.all(Array.from({length: 20}, () => reserve(db)));
  assert.equal(new Set(reservations.map((item) => item.purchaseId)).size, 1);
  assert.equal(new Set(reservations.map((item) => item.intentId)).size, 1);
});

test("reload and timeout retry keys reuse the active backend intent", async () => {
  const db = new MemoryDb();
  const first = await reserve(db);
  const reload = await reserve(db, {idempotencyKey: "new-browser-key-after-reload"});
  assert.equal(reload.purchaseId, first.purchaseId);
  assert.equal(reload.reused, true);
});

test("same request key cannot cross amount or Business boundaries", async () => {
  const db = new MemoryDb();
  await reserve(db);
  await assert.rejects(() => reserve(db, {amount: 25000}), /already used/i);
  await assert.rejects(() => reserve(db, {businessId: "business-2"}), /already used/i);
});

test("completed intent permits a deliberate subsequent purchase", async () => {
  const db = new MemoryDb();
  const first = await reserve(db);
  const intentPath = `businessRothCheckoutIntents/${first.intentId}`;
  db.records.set(intentPath, {...db.records.get(intentPath), status: "completed"});
  const second = await reserve(db, {idempotencyKey: "deliberate-purchase-0002", nowMs: 2000});
  assert.notEqual(second.purchaseId, first.purchaseId);
});

test("an expired pending checkout is replaced without reusing its Stripe identity", async () => {
  const db = new MemoryDb();
  const first = await reserve(db);
  const intentPath = `businessRothCheckoutIntents/${first.intentId}`;
  db.records.set(intentPath, {
    ...db.records.get(intentPath),
    status: "pending_verification",
    activeUntilMs: 1500,
  });
  const replacement = await reserve(db, {nowMs: 2000});
  assert.notEqual(replacement.purchaseId, first.purchaseId);
});
