/* eslint-disable max-len, require-jsdoc */
"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {Timestamp} = require("firebase-admin/firestore");
const {windowBounds, linkedGift, reconcileGiftStoryWindow} = require("./gift-story-gap-reconciliation");

const START = "2026-09-26T10:00:00Z";
const END = "2026-09-26T10:10:00Z";

function delivery(id, atMs, data = {}) {
  const fields = {status: "completed", serviceType: "gifts", giftRequestId: `gift_${id}`,
    completedAt: Timestamp.fromMillis(atMs), ...data};
  return {id, data: () => fields, get: (field) => fields[field]};
}

function fakeDb(rows = [], gifts = {}) {
  const queries = [];
  const deliveryCollection = {
    where(field, op, value) {
      queries.push({field, op, value});
      return this;
    },
    orderBy(field) {
      queries.push({orderBy: typeof field === "string" ? field : "__name__"});
      return this;
    },
    limit(value) {
      this.pageLimit = value;
      return this;
    },
    startAfter(at, id) {
      this.after = {at, id};
      return this;
    },
    async get() {
      const lower = queries.find((entry) => entry.field === "completedAt" && entry.op === ">=").value.toMillis();
      const upper = queries.find((entry) => entry.field === "completedAt" && entry.op === "<=").value.toMillis();
      const matches = rows.filter((item) => {
        const at = item.get("completedAt").toMillis();
        return at >= lower && at <= upper && (!this.after || at > this.after.at.toMillis() ||
          at === this.after.at.toMillis() && item.id > this.after.id);
      }).sort((a, b) => a.get("completedAt").toMillis() - b.get("completedAt").toMillis() || a.id.localeCompare(b.id));
      return {docs: matches.slice(0, this.pageLimit)};
    },
  };
  return {queries, collection: (name) => name === "deliveryRequests" ? deliveryCollection : {
    doc: (id) => ({get: async () => ({id, exists: Boolean(gifts[id]), data: () => gifts[id]})}),
    where: (_field, _op, deliveryId) => ({limit: () => ({get: async () => ({docs: Object.entries(gifts)
        .filter(([, gift]) => gift.deliveryId === deliveryId)
        .map(([id, gift]) => ({id, exists: true, data: () => gift}))})})}),
  }};
}

function options(db, overrides = {}) {
  return {db, start: START, end: END, pageSize: 2, maxRecords: 10, apply: true,
    ownerReader: async () => "cloud_run", runCompletion: async () => ({effectiveEffects: 1}), ...overrides};
}

test("reconciliation requires explicit short UTC bounds and bounded work", async () => {
  assert.throws(() => windowBounds("", END), /utc_bounds/);
  assert.throws(() => windowBounds(END, START), /out_of_bounds/);
  assert.throws(() => windowBounds(START, "2026-09-28T10:00:00Z"), /out_of_bounds/);
  await assert.rejects(reconcileGiftStoryWindow(options(fakeDb(), {pageSize: 51})), /invalid_page_size/);
  await assert.rejects(reconcileGiftStoryWindow(options(fakeDb(), {maxRecords: 201})), /invalid_max_records/);
  await assert.rejects(reconcileGiftStoryWindow(options(fakeDb(), {ownerReader: async () => "none"})), /requires_cloud_run_owner/);
});

test("zero candidates use an indexed timestamp range and deterministic document order", async () => {
  const db = fakeDb();
  const result = await reconcileGiftStoryWindow(options(db));
  assert.deepEqual(result, {candidates: 0, processed: 0, alreadyClaimed: 0, ignored: 0, errors: 0,
    examined: 0, nextCursor: null});
  assert.deepEqual(db.queries.map((entry) => entry.field || entry.orderBy),
      ["completedAt", "completedAt", "completedAt", "__name__"]);
});

test("one missed Gift is processed once and the identical second window adds no effective Story work", async () => {
  const at = Date.parse("2026-09-26T10:03:00Z");
  const db = fakeDb([delivery("d1", at)], {gift_d1: {deliveryId: "d1"}});
  const done = new Set();
  const runCompletion = async (_db, gift) => {
    if (done.has(gift.id)) return {effectiveEffects: 0};
    done.add(gift.id);
    return {effectiveEffects: 7};
  };
  const first = await reconcileGiftStoryWindow(options(db, {runCompletion}));
  const second = await reconcileGiftStoryWindow(options(db, {runCompletion}));
  assert.equal(first.processed, 1);
  assert.equal(second.processed, 0);
  assert.equal(second.alreadyClaimed, 1);
  assert.equal(first.nextCursor, null);
});

test("pagination resumes from timestamp and ID without skipping equal-timestamp deliveries", async () => {
  const at = Date.parse("2026-09-26T10:03:00Z");
  const rows = [delivery("a", at), delivery("b", at), delivery("c", at + 1)];
  const gifts = {gift_a: {}, gift_b: {}, gift_c: {}};
  const db = fakeDb(rows, gifts);
  const first = await reconcileGiftStoryWindow(options(db, {maxRecords: 2}));
  assert.equal(first.processed, 2);
  assert.ok(first.nextCursor);
  const second = await reconcileGiftStoryWindow(options(fakeDb(rows, gifts), {cursor: first.nextCursor}));
  assert.equal(second.processed, 1);
  assert.equal(second.nextCursor, null);
  await assert.rejects(reconcileGiftStoryWindow(options(db, {cursor: first.nextCursor, end: "2026-09-26T10:11:00Z"})),
      /invalid_reconciliation_cursor/);
});

test("failed downstream work preserves the cursor before that candidate for a safe restart", async () => {
  const at = Date.parse("2026-09-26T10:03:00Z");
  const rows = [delivery("a", at), delivery("b", at + 1)];
  const gifts = {gift_a: {}, gift_b: {}};
  let fail = true;
  const runCompletion = async (_db, gift) => {
    if (gift.id === "gift_b" && fail) throw new Error("email_queue_unavailable");
    return {effectiveEffects: 1};
  };
  const first = await reconcileGiftStoryWindow(options(fakeDb(rows, gifts), {runCompletion}));
  assert.equal(first.processed, 1);
  assert.equal(first.errors, 1);
  assert.ok(first.nextCursor);
  fail = false;
  const retry = await reconcileGiftStoryWindow(options(fakeDb(rows, gifts), {runCompletion, cursor: first.nextCursor}));
  assert.equal(retry.processed, 1);
  assert.equal(retry.errors, 0);
});

test("notification publication failure retries the same candidate without advancing the cursor", async () => {
  const at = Date.parse("2026-09-26T10:03:00Z");
  const rows = [delivery("a", at)];
  const gifts = {gift_a: {}};
  let attempts = 0;
  const runCompletion = async () => {
    attempts++;
    if (attempts === 1) throw new Error("notification_queue_unavailable");
    return {effectiveEffects: 1};
  };
  const first = await reconcileGiftStoryWindow(options(fakeDb(rows, gifts), {runCompletion}));
  assert.equal(first.errors, 1);
  assert.equal(first.processed, 0);
  assert.equal(first.nextCursor, null);
  const retry = await reconcileGiftStoryWindow(options(fakeDb(rows, gifts), {runCompletion, cursor: first.nextCursor}));
  assert.equal(retry.errors, 0);
  assert.equal(retry.processed, 1);
  assert.equal(attempts, 2);
});

test("non-Gift and non-final records are ignored while malformed Gift links fail closed", async () => {
  const at = Date.parse("2026-09-26T10:03:00Z");
  const rows = [delivery("a", at, {serviceType: "standard", giftRequestId: ""}),
    delivery("b", at + 1, {status: "in_transit"}), delivery("c", at + 2)];
  const result = await reconcileGiftStoryWindow(options(fakeDb(rows), {pageSize: 3}));
  assert.equal(result.ignored, 2);
  assert.equal(result.errors, 1);
  assert.equal(result.processed, 0);
});

test("a stale direct Gift ID falls back to the canonical delivery-link lookup", async () => {
  const fallback = {id: "actual_gift", exists: true, data: () => ({deliveryId: "d1"})};
  const db = {collection: () => ({
    doc: () => ({get: async () => ({exists: false})}),
    where: () => ({limit: () => ({get: async () => ({docs: [fallback]})})}),
  })};
  assert.equal((await linkedGift(db, "d1", {giftOrderId: "stale_id"})).id, "actual_gift");
});

test("concurrent reconciliation invocations reuse effective Story claims", async () => {
  const at = Date.parse("2026-09-26T10:03:00Z");
  const db = fakeDb([delivery("d1", at)], {gift_d1: {}});
  const done = new Set();
  const runCompletion = async (_db, gift) => {
    if (done.has(gift.id)) return {effectiveEffects: 0};
    done.add(gift.id);
    await new Promise((resolve) => setTimeout(resolve, 5));
    return {effectiveEffects: 1};
  };
  const results = await Promise.all([reconcileGiftStoryWindow(options(db, {runCompletion})),
    reconcileGiftStoryWindow(options(fakeDb([delivery("d1", at)], {gift_d1: {}}), {runCompletion}))]);
  assert.equal(results.reduce((sum, result) => sum + result.processed, 0), 1);
  assert.equal(results.reduce((sum, result) => sum + result.alreadyClaimed, 0), 1);
});

test("reconciliation stops before the next Gift if ownership changes mid-window", async () => {
  const at = Date.parse("2026-09-26T10:03:00Z");
  const rows = [delivery("a", at), delivery("b", at + 1)];
  const gifts = {gift_a: {}, gift_b: {}};
  let reads = 0;
  let completions = 0;
  const result = await reconcileGiftStoryWindow(options(fakeDb(rows, gifts), {
    ownerReader: async () => ++reads < 3 ? "cloud_run" : "none",
    runCompletion: async () => {
      completions++;
      return {effectiveEffects: 1};
    },
  }));
  assert.equal(result.processed, 1);
  assert.equal(result.errors, 1);
  assert.equal(completions, 1);
  assert.ok(result.nextCursor);
});
