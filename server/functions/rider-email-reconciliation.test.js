"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {runForwardReconciliation} = require("./rider-email-reconciliation");

function millis(value) {
  if (value && typeof value.toMillis === "function") return value.toMillis();
  if (value && value.seconds != null) return Number(value.seconds) * 1000;
  return new Date(value || 0).getTime();
}

function fakeDb(initial = {}) {
  const values = new Map(Object.entries(initial));
  function ref(collection, id) {
    const key = `${collection}/${id}`;
    return {
      id,
      get: async () => ({exists: values.has(key), data: () => values.get(key)}),
      create: async (value) => {
        if (values.has(key)) throw Object.assign(new Error("Already exists"), {code: 6});
        values.set(key, {...value});
      },
    };
  }
  function query(collection, clauses = [], orders = [], cursor = null, limit = 50) {
    const api = {
      where: (field, operator, value) => query(collection, [...clauses, {field: String(field), operator, value}], orders, cursor, limit),
      orderBy: (field) => query(collection, clauses, [...orders, typeof field === "string" ? field : "__name__"], cursor, limit),
      startAfter: (...after) => query(collection, clauses, orders, after, limit),
      limit: (count) => query(collection, clauses, orders, cursor, count),
      get: async () => {
        let docs = [...values.entries()]
            .filter(([key]) => key.startsWith(`${collection}/`))
            .map(([key, value]) => ({id: key.slice(collection.length + 1), data: () => value}));
        docs = docs.filter((doc) => clauses.every(({field, operator, value}) => {
          const actual = millis(doc.data()[field]);
          const expected = millis(value);
          return operator === ">=" ? actual >= expected : actual <= expected;
        }));
        docs.sort((a, b) => {
          for (const field of orders) {
            const left = field === "__name__" ? a.id : millis(a.data()[field]);
            const right = field === "__name__" ? b.id : millis(b.data()[field]);
            if (left !== right) return left < right ? -1 : 1;
          }
          return a.id.localeCompare(b.id);
        });
        if (cursor && cursor.length) {
          const lastValue = millis(cursor[0]);
          const lastId = cursor[1];
          docs = docs.filter((doc) => millis(doc.data()[orders[0]]) > lastValue ||
            millis(doc.data()[orders[0]]) === lastValue && doc.id > lastId);
        }
        return {docs: docs.slice(0, limit)};
      },
    };
    return api;
  }
  return {
    collection: (name) => ({doc: (id) => ref(name, id), where: (field, operator, value) => query(name, [{field: String(field), operator, value}])}),
    read: (collection, id) => values.get(`${collection}/${id}`),
    count: (collection) => [...values.keys()].filter((key) => key.startsWith(`${collection}/`)).length,
  };
}

const EFFECTIVE = "2026-09-27T00:00:00.000Z";
const POST = "2026-09-27T01:00:00.000Z";
const END = "2026-09-28T00:00:00.000Z";

function fixtures() {
  return {
    "riderProfiles/approved": {email: "approved@example.test", approvalStatus: "approved", riderAuthorityUpdatedAt: POST},
    "riderDocuments/doc-1": {email: "unused@example.test", riderId: "approved", status: "replacement_requested", documentType: "driving_licence", riderAuthorityUpdatedAt: POST},
    "riderEarningTransactions/earning-1": {riderId: "approved", type: "delivery_earning", status: "completed", amount: 18, createdAt: POST, deliveryId: "delivery-1"},
    "payoutRequests/withdrawal-1": {riderId: "approved", status: "requested", payoutStatus: "requested", amount: 20, createdAt: POST},
    "payoutRequests/withdrawal-2": {riderId: "approved", status: "processing", payoutStatus: "paid", amount: 20, paidAt: POST},
    "payoutRequests/withdrawal-3": {riderId: "approved", status: "processing", payoutStatus: "failed", amount: 20, failedAt: POST},
  };
}

test("forward reconciliation publishes required Rider milestones and the second run is zero-new", async () => {
  const db = fakeDb(fixtures());
  const first = await runForwardReconciliation({db, startAt: EFFECTIVE, endAt: END, policyEffectiveAt: EFFECTIVE, pageSize: 20, maxWork: 100});
  assert.equal(first.published, 6);
  assert.equal(first.suppressed, 0);
  assert.equal(first.errors, 0);
  const second = await runForwardReconciliation({db, startAt: EFFECTIVE, endAt: END, policyEffectiveAt: EFFECTIVE, pageSize: 20, maxWork: 100});
  assert.equal(second.published, 0);
  assert.equal(second.existing, 6);
  assert.equal(db.count("emailQueue"), 6);
});

test("pre-policy Rider milestones are ignored and missing recipients become terminal suppression outcomes", async () => {
  const db = fakeDb({
    "riderProfiles/old": {email: "old@example.test", approvalStatus: "approved", riderAuthorityUpdatedAt: "2026-09-26T23:59:00.000Z"},
    "riderProfiles/missing": {approvalStatus: "approved", riderAuthorityUpdatedAt: POST},
  });
  const result = await runForwardReconciliation({db, startAt: "2026-09-26T00:00:00.000Z", endAt: END, policyEffectiveAt: EFFECTIVE, pageSize: 20, maxWork: 100});
  assert.equal(result.published, 0);
  assert.equal(result.candidates, 1);
  assert.equal(result.suppressed, 1);
  assert.equal(db.count("emailQueue"), 0);
  assert.equal(db.count("riderEmailOutcomes"), 1);
  const replay = await runForwardReconciliation({db, startAt: "2026-09-26T00:00:00.000Z", endAt: END, policyEffectiveAt: EFFECTIVE, pageSize: 20, maxWork: 100});
  assert.equal(replay.published, 0);
  assert.equal(replay.existing, 1);
});
