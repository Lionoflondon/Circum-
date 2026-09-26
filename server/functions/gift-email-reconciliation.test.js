"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {runForwardReconciliation, communicationId} = require("./gift-email-reconciliation");
const policy = require("./gift-communications-policy");

function millis(value) {
  if (value && typeof value.toMillis === "function") return value.toMillis();
  return new Date(value).getTime();
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
      set: async (value, options = {}) => values.set(key, options.merge ? {...(values.get(key) || {}), ...value} : {...value}),
    };
  }
  function query(collection, clauses = [], orders = [], cursor = null, limit = 50) {
    const api = {
      where: (field, operator, value) => query(collection, [...clauses, {field: String(field), operator, value}], orders, cursor, limit),
      orderBy: (field) => query(collection, clauses, [...orders, typeof field === "string" ? field : "__name__"], cursor, limit),
      startAfter: (...valuesAfter) => query(collection, clauses, orders, valuesAfter, limit),
      limit: (count) => query(collection, clauses, orders, cursor, count),
      get: async () => {
        let docs = [...values.entries()]
            .filter(([key]) => key.startsWith(`${collection}/`))
            .map(([key, value]) => ({id: key.slice(collection.length + 1), data: () => value}));
        docs = docs.filter((doc) => clauses.every(({field, operator, value}) => {
          const actual = millis(doc.data()[field]);
          const expected = millis(value);
          return operator === ">=" ? actual >= expected : operator === "<=" ? actual <= expected : actual === expected;
        }));
        docs.sort((a, b) => {
          for (const field of orders) {
            const left = field === "__name__" ? a.id : millis(a.data()[field]);
            const right = field === "__name__" ? b.id : millis(b.data()[field]);
            if (left < right) return -1;
            if (left > right) return 1;
          }
          return a.id.localeCompare(b.id);
        });
        if (cursor && cursor.length) {
          docs = docs.filter((doc) => {
            const lastValue = millis(cursor[0]);
            const docValue = millis(doc.data()[orders[0]]);
            return docValue > lastValue || docValue === lastValue && doc.id > cursor[1];
          });
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

const EFFECTIVE = "2026-09-26T12:00:00.000Z";
const END = "2026-09-27T00:00:00.000Z";
const post = "2026-09-26T13:00:00.000Z";

function gift(status, eventField, extra = {}) {
  return {status, senderEmail: "sender@example.test", recipientEmail: "recipient@example.test", recipientName: "Maya",
    [eventField]: post, ...extra};
}

test("forward reconciliation covers all seven required email milestones through the canonical publisher", async () => {
  const senderToken = "s".repeat(43);
  const recipientToken = "r".repeat(43);
  const db = fakeDb({
    "giftRequests/payment": gift("submitted_for_review", "paidAt", {paymentStatus: "paid", walletContributionGbp: 25, remainingStripeAmountGbp: 0}),
    "walletTransactions/gift_roth_payment": {status: "completed", amount: -25, referenceId: "payment"},
    "giftPaymentDrafts/problem": {paymentStatus: "failed", paymentProblemAt: post, senderEmail: "sender@example.test", recipientName: "Maya"},
    "giftRequests/approved": gift("approved", "approvedAt"),
    "giftRequests/rejected": gift("rejected", "rejectedAt"),
    "giftRequests/ready": gift("ready_for_gift_delivery", "readyForDeliveryAt"),
    "giftRequests/delivered": gift("delivered", "deliveredAt"),
    "giftRequests/story": gift("delivered", "giftStoryAvailableAt", {giftStoryUnlocked: true, giftStoryStatus: "unlocked",
      giftStoryAccessToken: senderToken, recipientStoryToken: recipientToken}),
  });
  const result = await runForwardReconciliation({db, startAt: EFFECTIVE, endAt: END, policyEffectiveAt: EFFECTIVE, pageSize: 20, maxWork: 100});
  assert.equal(result.published, 7);
  assert.equal(result.suppressed, 0);
  assert.equal(result.errors, 0);
  assert.equal(db.count("emailQueue"), 9);
  assert.equal(db.read("emailQueue", "gift_approved_approved").recipientRole, "sender");
});

test("second reconciliation run is a zero-new-communication no-op and preserves deterministic IDs", async () => {
  const giftData = gift("delivered", "giftStoryAvailableAt", {giftStoryUnlocked: true, giftStoryStatus: "unlocked",
    giftStoryAccessToken: "s".repeat(43), recipientStoryToken: "r".repeat(43)});
  const db = fakeDb({"giftRequests/g-1": giftData});
  const first = await runForwardReconciliation({db, startAt: EFFECTIVE, endAt: END, policyEffectiveAt: EFFECTIVE, pageSize: 20, maxWork: 100});
  const second = await runForwardReconciliation({db, startAt: EFFECTIVE, endAt: END, policyEffectiveAt: EFFECTIVE, pageSize: 20, maxWork: 100});
  assert.equal(first.published, 1);
  assert.equal(second.published, 0);
  assert.equal(second.existing, 2);
  assert.equal(db.count("emailQueue"), 3);
});

test("partial Story pair repairs only the missing role and invalid recipients become terminal suppression outcomes", async () => {
  const base = gift("delivered", "giftStoryAvailableAt", {giftStoryUnlocked: true, giftStoryStatus: "unlocked",
    giftStoryAccessToken: "s".repeat(43), recipientStoryToken: "r".repeat(43)});
  const partial = fakeDb({"giftRequests/partial": base, ["emailQueue/" + communicationId(policy.EVENT.STORY_READY, "partial", "sender")]: {status: "queued"}});
  const repaired = await runForwardReconciliation({db: partial, startAt: EFFECTIVE, endAt: END, policyEffectiveAt: EFFECTIVE, pageSize: 20, maxWork: 100});
  assert.equal(repaired.published, 1);
  assert.equal(repaired.existing, 1);

  const noRecipient = fakeDb({"giftRequests/no-recipient": {...base, recipientEmail: "not-an-email", recipientStoryToken: "r".repeat(43)}});
  const suppressed = await runForwardReconciliation({db: noRecipient, startAt: EFFECTIVE, endAt: END, policyEffectiveAt: EFFECTIVE, pageSize: 20, maxWork: 100});
  assert.equal(suppressed.suppressed, 1);
  assert.equal(noRecipient.count("giftCommunicationOutcomes"), 1);
  const replay = await runForwardReconciliation({db: noRecipient, startAt: EFFECTIVE, endAt: END, policyEffectiveAt: EFFECTIVE, pageSize: 20, maxWork: 100});
  assert.equal(replay.published, 0);
});

test("pre-policy events remain ignored even when updated later", async () => {
  const db = fakeDb({"giftRequests/old": {status: "approved", senderEmail: "sender@example.test",
    approvedAt: "2026-09-25T10:00:00.000Z", updatedAt: "2026-09-26T23:00:00.000Z"}});
  const result = await runForwardReconciliation({db, startAt: EFFECTIVE, endAt: END, policyEffectiveAt: EFFECTIVE, pageSize: 20, maxWork: 100});
  assert.equal(result.published, 0);
  assert.equal(result.candidates, 0);
  assert.equal(db.count("emailQueue"), 0);
  assert.equal(db.count("giftCommunicationOutcomes"), 0);
});
