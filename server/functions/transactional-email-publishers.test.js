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
    set: async (value, options = {}) => {
      const key = `${name}/${id}`;
      data.set(key, options.merge ? {...(data.get(key) || {}), ...value} : {...value});
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

test("scheduled ordinary delivery remains in the Info family", async () => {
  const db = fakeDb();
  const input = event("deliveryRequests", "scheduled-1", null, {
    status: "scheduled", paymentStatus: "paid", deliveryDate: "2026-10-01",
    scheduleType: "scheduled", senderEmail: "sender@example.test",
  });
  const result = await publishFromEvent({db, ...input});
  assert.equal(result.id, "delivery_booking_paid_scheduled-1");
  assert.equal(db.read("emailQueue", result.id).senderCategory, "info");
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
  assert.equal(db.read("emailQueue", result.id).senderCategory, "business");
});

test("Business payment failure publishes one Business action-required queue item", async () => {
  const db = fakeDb();
  const input = event("businessInvoices", "i-failed", {status: "open", balanceDue: 20}, {
    status: "open", balanceDue: 20, invoiceNumber: "INV-FAILED", businessId: "b-1", billingEmail: "billing@example.test",
    paymentCommunicationState: "failed", paymentCommunicationKey: "reservation-1:pi_failed",
  });
  const result = await publishFromEvent({db, ...input});
  assert.equal(result.id, "business_invoice_payment_problem_i-failed_reservation-1_pi_failed");
  assert.equal(db.read("emailQueue", result.id).senderCategory, "business");
  assert.equal(db.read("emailQueue", result.id).sourcePaymentProblemState, "failed");
  assert.deepEqual(await publishFromEvent({db, ...input}), {status: "duplicate", id: result.id});
});

test("Business success and unchanged failure markers do not publish a failed email", async () => {
  const db = fakeDb();
  const unchanged = event("businessInvoices", "i-success", {status: "open", balanceDue: 20, paymentCommunicationKey: "same"}, {
    status: "open", balanceDue: 20, paymentCommunicationState: "failed", paymentCommunicationKey: "same",
    billingEmail: "billing@example.test",
  });
  assert.equal((await publishFromEvent({db, ...unchanged})).status, "ignored");
  const success = event("businessInvoices", "i-success", {status: "open", balanceDue: 20}, {
    status: "paid", balanceDue: 0, paymentCommunicationState: "succeeded", paymentCommunicationKey: "reservation-1:pi_success",
    billingEmail: "billing@example.test",
  });
  assert.equal((await publishFromEvent({db, ...success})).id, "business_invoice_paid_i-success");
  assert.equal(db.read("emailQueue", "business_invoice_payment_problem_i-success_reservation-1_pi_success"), undefined);
});

test("completed Roth ledger movement is the sole source of its queue email", async () => {
  const db = fakeDb();
  const input = event("walletTransactions", "w-1", null, {
    status: "completed", walletType: "sender", userId: "u-1", userEmail: "roth@example.test",
  });
  const result = await publishFromEvent({db, ...input});
  assert.equal(result.id, "roth_activity_w-1");
  assert.equal(db.read("emailQueue", result.id).sourceCollection, "walletTransactions");
});

test("Starter Roth ledger creation does not create a second generic activity email", async () => {
  const db = fakeDb();
  const input = event("walletTransactions", "sender_welcome_roth_u-1", null, {
    status: "completed", walletType: "sender", userId: "u-1", userEmail: "welcome@example.test",
    metadata: {source: "sender_welcome_roth"},
  });
  assert.deepEqual(await publishFromEvent({db, ...input}), {
    status: "ignored", reason: "starter_welcome_has_dedicated_email", eventId: input.eventId,
  });
  assert.equal(db.read("emailQueue", "roth_activity_sender_welcome_roth_u-1"), undefined);
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
  assert.equal(db.read("emailQueue", result.id).senderCategory, "health");
});

test("Roth-only Gift confirmation uses the finalized Gift and completed debit once", async () => {
  const db = fakeDb({"walletTransactions/gift_roth_g-1": {status: "completed", amount: -120, referenceId: "g-1"}});
  const input = event("giftRequests", "g-1", null, {paymentStatus: "paid", status: "submitted_for_review",
    senderEmail: "sender@example.test", recipientName: "Maya", walletContributionGbp: 120, remainingStripeAmountGbp: 0});
  assert.deepEqual(await publishFromEvent({db, ...input}), {status: "queued", id: "gift_payment_confirmed_g-1"});
  assert.deepEqual(await publishFromEvent({db, ...input}), {status: "duplicate", id: "gift_payment_confirmed_g-1"});
  const queued = db.read("emailQueue", "gift_payment_confirmed_g-1");
  assert.equal(queued.senderCategory, "gifts");
  assert.equal(queued.sourceRecipientField, "senderEmail");
  assert.match(queued.text, /120 Roth for your Gift to Maya/);
});

test("split Gift confirmation has no false card amount or duplicate receipt", async () => {
  const db = fakeDb({"walletTransactions/gift_roth_g-2": {status: "completed", amount: -25, referenceId: "g-2"}});
  const input = event("giftRequests", "g-2", null, {paymentStatus: "paid", senderEmail: "sender@example.test",
    recipientName: "Maya", walletContributionGbp: 25, remainingStripeAmountGbp: 75, stripePaymentIntentId: "pi-test"});
  const result = await publishFromEvent({db, ...input});
  assert.equal(result.id, "gift_payment_confirmed_g-2");
  const queued = db.read("emailQueue", result.id);
  assert.match(queued.text, /card payment receipt is provided separately/);
  assert.doesNotMatch(queued.text, /75 Roth|£75/);
});

test("no Gift confirmation before paid state and completed Roth debit", async () => {
  const pending = event("giftRequests", "g-3", null, {paymentStatus: "pending", senderEmail: "sender@example.test",
    walletContributionGbp: 120, remainingStripeAmountGbp: 0});
  const db = fakeDb();
  assert.equal((await publishFromEvent({db, ...pending})).status, "ignored");
  assert.equal((await publishFromEvent({db, ...event("giftRequests", "g-3", null, {...pending.decoded.after, paymentStatus: "paid"})})).reason,
      "gift_roth_ledger_not_final");
  assert.equal(db.read("emailQueue", "gift_payment_confirmed_g-3"), undefined);
});

test("card-only Gift relies on Stripe receipt and does not publish Roth confirmation", async () => {
  const db = fakeDb();
  const input = event("giftRequests", "g-4", null, {paymentStatus: "paid", senderEmail: "sender@example.test",
    walletContributionGbp: 0, remainingStripeAmountGbp: 120});
  assert.equal((await publishFromEvent({db, ...input})).status, "ignored");
});

test("all policy-required Gift status milestones publish deterministic Sender emails", async () => {
  for (const [status, eventType, templateId] of [
    ["approved", "gift_approved", "gift-approved"],
    ["rejected", "gift_rejected", "gift-rejected"],
    ["ready_for_gift_delivery", "gift_ready_for_delivery", "gift-ready-for-delivery"],
  ]) {
    const db = fakeDb();
    const input = event("giftRequests", `g-${status}`, {status: "submitted_for_review"}, {
      status, senderEmail: "sender@example.test", recipientName: "Maya",
    });
    const result = await publishFromEvent({db, ...input});
    assert.equal(result.id, `${eventType}_g-${status}`);
    const queued = db.read("emailQueue", result.id);
    assert.equal(queued.templateId, templateId);
    assert.equal(queued.senderCategory, "gifts");
    assert.equal(queued.recipientRole, "sender");
  }
});

test("Gift payment problem uses state-safe copy and never creates a refund email", async () => {
  for (const [paymentStatus, expectedTemplate] of [["failed", "gift-payment-problem-failed"], ["requires_action", "gift-payment-problem-unconfirmed"]]) {
    const db = fakeDb();
    const input = event("giftPaymentDrafts", `draft-${paymentStatus}`, {paymentStatus: "payment_pending"}, {
      paymentStatus, paymentProblemAt: "2026-09-26T13:00:00.000Z", senderEmail: "sender@example.test", recipientName: "Maya",
    });
    const result = await publishFromEvent({db, ...input});
    assert.equal(result.status, "queued");
    const queued = db.read("emailQueue", result.id);
    assert.equal(queued.templateId, expectedTemplate);
    assert.equal(queued.sourceCollection, "giftPaymentDrafts");
    assert.doesNotMatch(queued.text, /refund|refunded|weren't charged|not charged/i);
  }
});

test("routine Gift progression remains push-only and never publishes an email", async () => {
  for (const status of ["submitted_for_review", "curation_started", "in_delivery", "rider_assigned"]) {
    const db = fakeDb();
    const input = event("giftRequests", `push-${status}`, {status: "submitted_for_review"}, {
      status, senderEmail: "sender@example.test", recipientName: "Maya",
    });
    assert.equal((await publishFromEvent({db, ...input})).status, "ignored");
    assert.equal(db.read("emailQueue", `gift_${status}_push-${status}`), undefined);
  }
});

test("Story unlock publishes sender delivery plus both role-specific Story emails", async () => {
  const db = fakeDb();
  const senderToken = "s".repeat(43);
  const recipientToken = "r".repeat(43);
  const after = {status: "delivered", giftStoryUnlocked: true, giftStoryStatus: "unlocked",
    senderEmail: "sender@example.test", recipientEmail: "recipient@example.test", recipientName: "Maya",
    giftStoryAccessToken: senderToken, recipientStoryToken: recipientToken};
  const input = event("giftRequests", "g-5", {status: "approved", giftStoryStatus: "locked"}, after);
  assert.equal((await publishFromEvent({db, ...input})).status, "published");
  const delivered = db.read("emailQueue", "gift_g-5_gift_delivered");
  assert.equal(delivered.to, "sender@example.test");
  assert.equal(delivered.ctaUrl, "https://circumuk.com/?app=gifts");
  assert.equal(db.read("emailQueue", "gift_story_g-5_sender").to, "sender@example.test");
  assert.equal(db.read("emailQueue", "gift_story_g-5_recipient").to, "recipient@example.test");
  assert.equal(db.read("emailQueue", "gift_g-5_recipient_delivered"), undefined);
  assert.equal((await publishFromEvent({db, ...input})).status, "published");
});
