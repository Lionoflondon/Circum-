"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {scanQuery} = require("./rider-query-scan");
const {scheduledRiderEarningsReconciliationCore} = require("./rider-earnings-summary");
function queryFor(docs, offset = 0, size = docs.length) {
  return {
    limit: (limit) => queryFor(docs, offset, limit),
    startAfter: (cursor) => queryFor(docs, docs.indexOf(cursor) + 1, size),
    get: async () => ({docs: docs.slice(offset, offset + size)}),
  };
}
test("scans tied values across multiple full pages and the final partial page", async () => {
  const docs = Array.from({length: 405}, (_, i) => ({id: String(i), data: () => ({account: "same"})}));
  const visited = [];
  await scanQuery(queryFor(docs), 200, async (doc) => visited.push(doc.id));
  assert.deepEqual(visited, docs.map((doc) => doc.id));
});
test("empty and exact-page collections terminate without duplicates", async () => {
  for (const count of [0, 25, 50]) {
    let visits = 0;
    await scanQuery(queryFor(Array.from({length: count}, (_, id) => ({id}))), 25, async () => visits++);
    assert.equal(visits, count);
  }
});
test("earnings scheduler reconciles Riders beyond the original 25 record cap", async () => {
  const docs = Array.from({length: 61}, (_, i) => ({id: String(i)}));
  const visited = [];
  const result = await scheduledRiderEarningsReconciliationCore({
    db: {collection: () => queryFor(docs)},
    reconcile: async ({riderId}) => {
      visited.push(riderId);
      return {reconciled: Number(riderId) % 2 === 0};
    },
  });
  assert.deepEqual(visited, docs.map((doc) => doc.id));
  assert.deepEqual(result, {scanned: 61, reconciled: 31, reviewRequired: 30});
});
test("earnings scheduler accepts migrated topic and explicit payload", () => {
  const {eventHandlerName} = require("./cloud-run-payment-schedulers");
  const payload = {message: {data: Buffer.from(JSON.stringify({handler: "scheduledRiderEarningsReconciliation"})).toString("base64")}};
  assert.equal(eventHandlerName(payload), "scheduledRiderEarningsReconciliation");
  assert.equal(eventHandlerName({}, "/", {"ce-source": "//pubsub.googleapis.com/projects/circum-2797c/topics/firebase-schedule-scheduledRiderEarningsReconciliation-us-central1"}), "scheduledRiderEarningsReconciliation");
});
