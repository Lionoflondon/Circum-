"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {publishFromEvent} = require("./transactional-email-publishers");

function fakeDb(initial = {}) {
  const data = new Map(Object.entries(initial));
  const collection = (name) => ({doc: (id) => ({
    get: async () => {
      const value = data.get(`${name}/${id}`);
      return {exists: value !== undefined, data: () => value && {...value}};
    },
    create: async (value) => {
      const key = `${name}/${id}`;
      if (data.has(key)) throw Object.assign(new Error("Already exists"), {code: 6});
      data.set(key, {...value});
    },
  })});
  return {collection, read: (name, id) => data.get(`${name}/${id}`)};
}

function event(collection, id, before, after) {
  return {
    eventType: before ? "google.cloud.firestore.document.v1.updated" : "google.cloud.firestore.document.v1.created",
    eventId: `evt-${collection}-${id}`,
    decoded: {documentName: `projects/circum-2797c/databases/(default)/documents/${collection}/${id}`, before: before || {}, after},
  };
}

test("paid ordinary booking publishes one deterministic queue item and replay is a no-op", async () => {
  const db = fakeDb();
  const input = event("deliveryRequests", "d-1", null, {
    status: "requested", paymentStatus: "paid", senderId: "s-1", senderEmail: "sender@example.test",
  });
  assert.deepEqual(await publishFromEvent({db, ...input}), {status: "queued", id: "delivery_booking_paid_d-1"});
  assert.deepEqual(await publishFromEvent({db, ...input}), {status: "duplicate", id: "delivery_booking_paid_d-1"});
  assert.equal(db.read("emailQueue", "delivery_booking_paid_d-1").sourceRequiredStatus, "paid");
});

test("booking publisher excludes Gifts, Health+, and Business delivery source types", async () => {
  for (const overrides of [{sourceModule: "gift"}, {serviceType: "HEALTH_PLUS"}, {businessMode: true}]) {
    const db = fakeDb();
    const input = event("deliveryRequests", "d-2", null, {
      status: "requested", paymentStatus: "paid", senderEmail: "sender@example.test", ...overrides,
    });
    assert.equal((await publishFromEvent({db, ...input})).status, "ignored");
    assert.equal(db.read("emailQueue", "delivery_booking_paid_d-2"), undefined);
  }
});

test("completion publisher requires a final delivery state and uses a separate logical identity", async () => {
  const db = fakeDb();
  const input = event("deliveryRequests", "d-3", {status: "in_progress"}, {
    status: "delivered", settlementStatus: "completed", senderEmail: "sender@example.test",
  });
  const result = await publishFromEvent({db, ...input});
  assert.equal(result.id, "delivery_completed_d-3");
  assert.equal(db.read("emailQueue", result.id).sourceRequiredStatus, "delivered");
});

test("cancellation email follows the settled authoritative record and finalized delivery state", async () => {
  const db = fakeDb({"deliveryRequests/d-4": {
    status: "cancelled_by_sender", cancellationSettlementStatus: "settled", senderEmail: "sender@example.test",
  }});
  const input = event("deliveryCancellationSettlements", "d-4", {status: "pending"}, {status: "settled"});
  const result = await publishFromEvent({db, ...input});
  assert.equal(result.id, "delivery_cancellation_settled_d-4");
  assert.equal(db.read("emailQueue", result.id).sourceRequiredStatus, "settled");
});

test("business email only publishes on fully-paid transition using billingEmail", async () => {
  const db = fakeDb();
  const input = event("businessInvoices", "i-1", {status: "partially_paid", balanceDue: 20}, {
    status: "paid", balanceDue: 0, invoiceNumber: "INV-1", businessId: "b-1", billingEmail: "billing@example.test",
  });
  const result = await publishFromEvent({db, ...input});
  assert.equal(result.id, "business_invoice_paid_i-1");
  assert.equal(db.read("emailQueue", result.id).to, "billing@example.test");
});

test("completed Roth ledger movement is the sole source of its queue email", async () => {
  const db = fakeDb();
  const input = event("walletTransactions", "w-1", null, {
    status: "completed", walletType: "sender", userId: "u-1", userEmail: "roth@example.test",
  });
  const result = await publishFromEvent({db, ...input});
  assert.equal(result.id, "roth_movement_completed_w-1");
  assert.equal(db.read("emailQueue", result.id).sourceCollection, "walletTransactions");
});

test("referral award email waits for final referral and both authoritative ledger entries", async () => {
  const initial = {
    "walletTransactions/referral_reward_user-1_referrer": {status: "completed"},
    "walletTransactions/referral_reward_user-1_referred": {status: "completed"},
  };
  const db = fakeDb(initial);
  const input = event("referrals", "user-1", {status: "first_qualifying_delivery_completed"}, {
    status: "roth_awarded", referrerEmail: "inviter@example.test", referredEmail: "member@example.test",
    referrerUserId: "inviter", referredUserId: "user-1",
  });
  assert.equal((await publishFromEvent({db, ...input})).status, "published");
  assert.equal(db.read("emailQueue", "referral_award_user-1_referrer").to, "inviter@example.test");
  assert.equal(db.read("emailQueue", "referral_award_user-1_referred").to, "member@example.test");

  const pendingDb = fakeDb();
  assert.deepEqual(await publishFromEvent({db: pendingDb, ...input}), {status: "skipped", reason: "referral_ledger_not_final"});
  assert.equal(pendingDb.read("emailQueue", "referral_award_user-1_referrer"), undefined);
});

test("Rider decision email uses only the authoritative application status and contact", async () => {
  const db = fakeDb();
  const input = event("riderProfiles", "rider-1", {approvalStatus: "pending"}, {
    approvalStatus: "more_information_requested", email: "rider@example.test", riderAuthorityUpdatedAt: {seconds: 123},
  });
  const result = await publishFromEvent({db, ...input});
  assert.equal(result.id, "rider_application_rider-1_more_information_requested_123_0");
  assert.equal(db.read("emailQueue", result.id).to, "rider@example.test");
  assert.doesNotMatch(db.read("emailQueue", result.id).text, /document|internal|reason/i);
});

test("Health+ status email is limited to the canonical operational status projection", async () => {
  const db = fakeDb();
  const input = event("prescriptionPickups", "pickup-1", {status: "scheduled"}, {
    status: "delivered", email: "patient@example.test", userId: "u-1",
  });
  const result = await publishFromEvent({db, ...input});
  assert.equal(result.id, "health_pickup-1_delivered");
  assert.equal(db.read("emailQueue", result.id).sourceRequiredStatus, "delivered");
});
