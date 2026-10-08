"use strict";
const {test} = require("node:test");
const assert = require("node:assert/strict");
const {processNotificationRetriesCore} = require("./notification-retry-core");

test("future retries use only the rotating ten-row compatibility page without claims", async () => {
  const now = Date.now();
  let cursor;
  let cursorWrites = 0;
  const reads = [];
  const db = {
    collection: (name) => {
      const filters = [];
      let limit = 0;
      const query = {
        where: (...args) => {
 filters.push(args); return query;
},
        orderBy: () => query,
        limit: (n) => {
 limit = n; return query;
},
        startAfter: () => query,
        get: async () => {
          const indexed = filters.some(([field]) => ["nextRetryAt", "retryLeaseExpiresAt"].includes(field));
          const docs = indexed ? [] : Array.from({length: limit}, (_, i) => ({
            id: `future-${i}`, data: () => ({retryable: true, pushDeliveryStatus: "failed", nextRetryAt: new Date(now + 60000)}),
          }));
          reads.push({name, filters, limit, count: docs.length});
          return {docs, size: docs.length, empty: !docs.length};
        },
        doc: () => ({get: async () => ({data: () => cursor || {}}), set: async (value) => {
 cursor = value; cursorWrites++;
}}),
      };
      return query;
    },
    runTransaction: async () => {
 throw new Error("unexpected claim");
},
  };
  const result = await processNotificationRetriesCore({db, now});
  assert.equal(result.scanned, 10);
  assert.equal(result.sent, 0);
  assert.equal(cursor.lastNotificationId, "future-9");
  assert.ok(reads.some((r) => r.filters.some(([field, op]) => field === "nextRetryAt" && op === "<=")));
  assert.ok(reads.some((r) => r.filters.some(([field, op]) => field === "retryLeaseExpiresAt" && op === "<=")));
  await processNotificationRetriesCore({db, now});
  assert.equal(cursorWrites, 1);
});
