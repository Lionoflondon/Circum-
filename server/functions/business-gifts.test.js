"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const gifts = require("./business-gifts");

function fakeDb(seed = {}) {
  const data = new Map(Object.entries(seed));
  function ref(path) {
    return {
      id: path.split("/").pop(),
      path,
      get: async () => {
        const value = data.get(path);
        return {exists: value !== undefined, data: () => value && {...value}};
      },
      set: async (value, options = {}) => {
        data.set(path, options.merge ? {...(data.get(path) || {}), ...value} : {...value});
      },
    };
  }
  return {
    collection: (name) => ({doc: (id) => ref(`${name}/${id}`)}),
    doc: (path) => ref(path),
    runTransaction: async (work) => work({
      get: (reference) => reference.get(),
      set: (reference, value, options) => reference.set(value, options),
      create: async (reference, value) => {
        if (data.has(reference.path)) throw new Error("already exists");
        data.set(reference.path, {...value});
      },
      update: (reference, value) => reference.set(value, {merge: true}),
    }),
    read: (path) => data.get(path),
    count: (prefix) => [...data.keys()].filter((key) => key.startsWith(prefix)).length,
  };
}

function context(uid = "member-1") {
  return {auth: {uid, token: {email: `${uid}@example.test`}}, app: {appId: "qa-app"}};
}

function input(overrides = {}) {
  return {
    businessId: "business-1",
    idempotencyKey: "order-1",
    budgetGbp: 250,
    paymentRail: "invoice",
    recipientName: "Maya",
    recipientEmail: "maya@example.test",
    deliveryAddress: "1 Example Street, London",
    deliveryDate: "2026-10-12",
    ...overrides,
  };
}

test("Business Gift order identity and rail validation are deterministic", () => {
  const first = gifts.orderIdFor({businessId: "b", uid: "u", idempotencyKey: "k"});
  assert.equal(first, gifts.orderIdFor({businessId: "b", uid: "u", idempotencyKey: "k"}));
  assert.notEqual(first, gifts.orderIdFor({businessId: "b", uid: "other", idempotencyKey: "k"}));
  assert.equal(gifts.normalizeRail("CARD"), "card");
  assert.equal(gifts.normalizeRail("unknown"), "");
  assert.equal(gifts.giftIdFor(first), `business_gift_${first}`);
});

test("Business Gift delivery dates use London calendar semantics and reject the past", () => {
  const now = new Date("2026-09-27T23:30:00.000Z");
  assert.equal(gifts.normalizeBusinessDeliveryDate("2026-09-26", {now}), "");
  assert.equal(gifts.normalizeBusinessDeliveryDate("2026-09-28", {now}), "2026-09-28");
  assert.equal(gifts.normalizeBusinessDeliveryDate("2026-09-27T23:30:00.000Z", {now}), "2026-09-28");
});

test("Business Gift rejects an unauthorized member before creating an order", async () => {
  const db = fakeDb({
    "businessAccounts/business-1": {ownerUid: "owner-1", businessName: "Example Business", status: "approved"},
  });
  await assert.rejects(
      gifts.createBusinessGiftOrderHandler(null, input(), context("not-a-member"), {db}),
      (error) => error.code === "permission-denied",
  );
  assert.equal(db.count("businessGiftOrders/"), 0);
});

test("Business invoice rail creates one server-priced order and replays idempotently", async () => {
  const db = fakeDb({
    "businessAccounts/business-1": {
      ownerUid: "member-1", businessName: "Example Business", billingEmail: "billing@example.test", status: "approved",
    },
  });
  const first = await gifts.createBusinessGiftOrderHandler(null, input(), context(), {db});
  const second = await gifts.createBusinessGiftOrderHandler(null, input(), context(), {db});
  assert.equal(first.paymentRail, "invoice");
  assert.equal(first.status, "awaiting_invoice");
  assert.equal(second.idempotent, true);
  assert.equal(db.count("businessGiftOrders/"), 1);
  assert.equal(db.read(`businessGiftOrders/${first.orderId}`).budgetGbp, 250);
  const invoice = db.read(`businessInvoices/gift_${first.orderId}`);
  assert.equal(invoice.businessGiftOrderId, first.orderId);
  assert.equal(invoice.checkoutProtocolVersion, 1);
});

test("a paid Business Gift order materializes exactly one protected Gift", async () => {
  const orderId = gifts.orderIdFor({businessId: "business-1", uid: "member-1", idempotencyKey: "order-1"});
  const db = fakeDb({
    [`businessGiftOrders/${orderId}`]: {
      orderId, businessId: "business-1", createdByUserId: "member-1", businessName: "Example Business",
      billingEmail: "billing@example.test", budgetGbp: 250, paymentRail: "roth",
      recipient: {recipientName: "Maya", recipientEmail: "maya@example.test", deliveryAddress: "1 Example Street", deliveryDate: "2026-10-12"},
    },
    [`businessInvoices/gift_${orderId}`]: {status: "paid", total: 250, paymentMethod: "roth"},
  });
  const first = await gifts.finalizePaidBusinessGiftOrder({db, orderId, payment: {}});
  const second = await gifts.finalizePaidBusinessGiftOrder({db, orderId, payment: {}});
  assert.equal(first.idempotent, false);
  assert.equal(second.idempotent, true);
  assert.equal(db.count("giftRequests/"), 1);
  assert.equal(db.read(`giftRequests/${gifts.giftIdFor(orderId)}`).recipientValueVisibility, "sender_only");
  assert.equal(db.read(`businessGiftOrders/${orderId}`).giftRequestId, gifts.giftIdFor(orderId));
});
