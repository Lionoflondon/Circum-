"use strict";
const {test} = require("node:test");
const assert = require("node:assert/strict");
const {processNotificationRetriesCore} = require("./notification-retry-core");

test("future retries skip claim transactions while preserving pagination", async () => {
  const now = Date.now();
  let transactions = 0;
  let cursor;
  const docs = Array.from({length: 100}, (_, index) => ({
    id: `future-${index}`,
    data: () => ({retryable: true, pushDeliveryStatus: "failed", nextRetryAt: new Date(now + 60000)}),
  }));
  const db = {
    collection: () => {
      let recovery = false;
      const query = {
        where: (field) => {
          recovery = field === "pushDeliveryStatus";
          return query;
        },
        orderBy: () => query,
        limit: () => query,
        get: async () => recovery ? {docs: [], empty: true} : {docs, size: docs.length, empty: false},
        doc: () => ({get: async () => ({data: () => ({})}), set: async (value) => {
 cursor = value;
}}),
      };
      return query;
    },
    runTransaction: async () => {
 transactions++; throw new Error("unexpected claim");
},
  };
  const result = await processNotificationRetriesCore({db, now});
  assert.equal(result.scanned, 100);
  assert.equal(result.sent, 0);
  assert.equal(transactions, 0);
  assert.equal(cursor.lastNotificationId, "future-99");
});
