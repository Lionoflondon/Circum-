"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {once} = require("node:events");
const {DocumentEventData} = require("./rider-policy-firestore-event");
const {createEmailQueueRecord} = require("./email-queue");
const {
  EVENT_TYPE,
  claimEmail,
  createServer,
  currentServiceDesign,
  fromForRecord,
  processEmailQueueRecord,
  queueEmailIdFromName,
  senderCategoryForRecord,
  sendResend,
} = require("./cloud-run-transactional-email");

test("approved Business and Health+ design refreshes only matching validated queue records", () => {
  const invoice = currentServiceDesign({eventType: "business_invoice_paid", templateId: "business-invoice-paid",
    sourceCollection: "businessInvoices", sourceDocumentId: "invoice-1", ctaUrl: "https://circumuk.com/?app=business"},
  {status: "valid", source: {status: "paid", balanceDue: 0, invoiceNumber: "INV-2048"}});
  assert.match(invoice.html, /INV-2048/);
  assert.match(invoice.html, /download-on-the-app-store\.svg/);
  const health = currentServiceDesign({eventType: "health_plus_rescheduled", templateId: "health-update-rescheduled",
    sourceCollection: "prescriptionPickups", ctaUrl: "https://circumuk.com/?app=health-plus"},
  {status: "valid", source: {status: "rescheduled"}});
  assert.match(health.html, /rescheduled/);
  assert.match(health.html, /en_badge_web_generic\.png/);
  const unrelated = {eventType: "gift_delivered", templateId: "gift-delivered", html: "unchanged"};
  assert.equal(currentServiceDesign(unrelated, {status: "valid", source: {}}), unrelated);
});

function fakeDb(initial = {}) {
  const data = new Map(Object.entries(initial));
  let transactionQueue = Promise.resolve();
  const refFor = (collection, id) => ({
    collection,
    id,
    get: async () => {
      const value = data.get(`${collection}/${id}`);
      return {exists: value !== undefined, data: () => value && {...value}};
    },
    set: async (value, options = {}) => {
      const key = `${collection}/${id}`;
      data.set(key, options.merge ? {...(data.get(key) || {}), ...value} : {...value});
    },
    create: async (value) => {
      const key = `${collection}/${id}`;
      if (data.has(key)) throw Object.assign(new Error("Already exists"), {code: 6});
      data.set(key, {...value});
    },
  });
  return {
    collection: (collection) => ({doc: (id) => refFor(collection, id)}),
    runTransaction: (callback) => {
      const run = async () => {
        const tx = {
          get: (ref) => ref.get(),
          set: (ref, value, options) => ref.set(value, options),
          update: (ref, value) => ref.set(value, {merge: true}),
        };
        return callback(tx);
      };
      const pending = transactionQueue.then(run);
      transactionQueue = pending.catch(() => {});
      return pending;
    },
    read: (collection, id) => data.get(`${collection}/${id}`),
  };
}

function record(overrides = {}) {
  return {
    notificationId: "email-1",
    eventType: "delivery_test",
    to: "approved@example.com",
    subject: "Transactional test",
    text: "Test body",
    status: "queued",
    attempts: 0,
    maxAttempts: 5,
    ...overrides,
  };
}

test("legacy queued-over-sent records cannot acquire a send lease or lose terminal fields", async () => {
  const sentAt = new Date("2026-09-25T09:30:00Z");
  const db = fakeDb({"emailQueue/email-1": record({
    status: "queued",
    sentAt,
    providerId: "resend-original",
    attempts: 2,
  })});
  let providerCalls = 0;
  const publishReplay = () => createEmailQueueRecord(db, "email-1", record());
  const replays = await Promise.all(Array.from({length: 20}, publishReplay));
  assert.equal(replays.filter((result) => result.status === "duplicate").length, 20);
  const results = await Promise.all(Array.from({length: 20}, (_, index) => processEmailQueueRecord({
    db,
    emailId: "email-1",
    eventId: `replay-${index}`,
    fetchImpl: async () => {
      providerCalls++;
      return {ok: true, status: 200, json: async () => ({id: "unexpected"})};
    },
    apiKey: "test-key",
  })));
  assert.equal(results.filter((result) => result.status === "duplicate").length, 20);
  assert.equal(providerCalls, 0);
  const final = db.read("emailQueue", "email-1");
  assert.equal(final.status, "sent");
  assert.equal(final.sentAt, sentAt);
  assert.equal(final.providerId, "resend-original");
  assert.equal(final.attempts, 2);
});

test("suppressed, failed, and skipped queue records remain terminal on replay", async () => {
  for (const status of ["suppressed", "failed", "skipped"]) {
    const db = fakeDb({"emailQueue/email-1": record({status, attempts: 3})});
    let providerCalls = 0;
    const result = await processEmailQueueRecord({
      db,
      emailId: "email-1",
      eventId: `replay-${status}`,
      fetchImpl: async () => {
        providerCalls++;
        return {ok: true, status: 200, json: async () => ({id: "unexpected"})};
      },
      apiKey: "test-key",
    });
    assert.equal(result.status, "duplicate");
    assert.equal(providerCalls, 0);
    assert.equal(db.read("emailQueue", "email-1").status, status);
    assert.equal(db.read("emailQueue", "email-1").attempts, 3);
  }
});

test("transactional sender identity follows the activity family", async () => {
  assert.equal(senderCategoryForRecord({eventType: "gift_delivered"}), "gifts");
  assert.equal(senderCategoryForRecord({eventType: "business_invoice_paid"}), "business");
  assert.equal(senderCategoryForRecord({eventType: "health_plus_delivered"}), "health");
  assert.equal(senderCategoryForRecord({eventType: "roth_movement_completed"}), "info");
  assert.equal(senderCategoryForRecord({eventType: "sender_welcome_ready"}), "info");
  assert.equal(fromForRecord({eventType: "gift_delivered"}, {}), "Circum Gifts <gifts@circumuk.com>");
  assert.equal(fromForRecord({eventType: "business_invoice_paid"}, {}), "Circum <info@circumuk.com>");
  assert.equal(fromForRecord({eventType: "health_plus_delivered"}, {}), "Circum <info@circumuk.com>");
  assert.equal(fromForRecord({eventType: "roth_movement_completed"}, {}), "Circum <info@circumuk.com>");
  assert.equal(fromForRecord({eventType: "sender_welcome_ready"}, {}), "Circum <info@circumuk.com>");
  assert.equal(fromForRecord({eventType: "roth_movement_completed"}, {
    NOTIFICATIONS_EMAIL_FROM: "Circum Notifications <notifications@circumuk.com>",
  }), "Circum Notifications <notifications@circumuk.com>");
  assert.equal(fromForRecord({eventType: "business_invoice_paid"}, {
    BUSINESS_EMAIL_FROM: "Circum Business <business@circumuk.com>",
  }), "Circum Business <business@circumuk.com>");
  assert.equal(fromForRecord({eventType: "health_plus_delivered"}, {
    HEALTH_EMAIL_FROM: "Circum Health+ <health@circumuk.com>",
  }), "Circum Health+ <health@circumuk.com>");
  assert.equal(fromForRecord({eventType: "business_invoice_paid"}, {
    NOTIFICATIONS_EMAIL_FROM: "Circum Notifications <notifications@circumuk.com>",
  }), "Circum Notifications <notifications@circumuk.com>");
  assert.throws(() => fromForRecord({eventType: "roth_movement_completed", senderCategory: "gifts"}, {}), /sender_family_mismatch/);
  assert.throws(() => fromForRecord({eventType: "business_invoice_paid"}, {BUSINESS_EMAIL_FROM: "Circum Gifts <gifts@circumuk.com>"}), /sender_family_mismatch/);
  assert.throws(() => fromForRecord({eventType: "business_invoice_paid"}, {BUSINESS_EMAIL_FROM: "Circum Health+ <health@circumuk.com>"}), /sender_family_mismatch/);
  assert.throws(() => fromForRecord({eventType: "health_plus_delivered"}, {HEALTH_EMAIL_FROM: "Circum Business <business@circumuk.com>"}), /sender_family_mismatch/);
  let request;
  await sendResend({
    record: record({eventType: "business_invoice_paid"}),
    to: "billing@example.test",
    apiKey: "test-key",
    fetchImpl: async (_url, options) => {
      request = JSON.parse(options.body);
      return {ok: true, status: 200, json: async () => ({id: "resend-business"})};
    },
    env: {BUSINESS_EMAIL_FROM: "Configured Business <business@circumuk.com>"},
  });
  assert.equal(request.from, "Configured Business <business@circumuk.com>");
});

test("an explicit sender override cannot cross product families", async () => {
  await assert.rejects(sendResend({
    record: record({eventType: "roth_movement_completed"}),
    to: "account@example.test",
    apiKey: "test-key",
    from: "Circum Gifts <gifts@circumuk.com>",
    fetchImpl: async () => ({ok: true, status: 200, json: async () => ({id: "should-not-send"})}),
  }), /sender_family_mismatch/);
});

function createdEvent(emailId = "email-1") {
  return DocumentEventData.encode({
    value: {
      name: `projects/circum-2797c/databases/(default)/documents/emailQueue/${emailId}`,
      fields: {
        notificationId: {stringValue: emailId},
        status: {stringValue: "queued"},
      },
    },
  }).finish();
}

function eventBody(emailId) {
  return Buffer.from(JSON.stringify({
    message: {
      data: Buffer.from(createdEvent(emailId)).toString("base64"),
      messageId: "eventarc-email-1",
    },
  }));
}

test("extracts only canonical emailQueue document ids", () => {
  assert.equal(queueEmailIdFromName("projects/p/databases/(default)/documents/emailQueue/e1"), "e1");
  assert.equal(queueEmailIdFromName("projects/p/databases/(default)/documents/giftEmailNotifications/e1"), null);
});

test("valid queue record is claimed once and persisted as sent", async () => {
  const db = fakeDb({"emailQueue/email-1": record()});
  let calls = 0;
  const result = await processEmailQueueRecord({
    db,
    emailId: "email-1",
    eventId: "event-1",
    apiKey: "test-key",
    fetchImpl: async (_url, options) => {
      calls += 1;
      assert.equal(options.headers["Idempotency-Key"], "email-1");
      return {ok: true, status: 200, json: async () => ({id: "resend-1"})};
    },
  });
  assert.deepEqual(result, {status: "sent", providerId: "resend-1"});
  assert.equal(calls, 1);
  assert.equal(db.read("emailQueue", "email-1").status, "sent");
});

test("exact replay and 20 concurrent copies cannot send twice", async () => {
  const db = fakeDb({"emailQueue/email-1": record()});
  let calls = 0;
  const send = async () => {
    calls += 1;
    return {ok: true, status: 200, json: async () => ({id: "resend-1"})};
  };
  const results = await Promise.allSettled(Array.from({length: 20}, (_, index) => processEmailQueueRecord({
    db, emailId: "email-1", eventId: `event-${index}`, apiKey: "test-key", fetchImpl: send,
  })));
  assert.equal(calls, 1);
  assert.equal(results.filter((item) => item.status === "fulfilled" && item.value.status === "sent").length, 1);
  const duplicates = results.filter((item) => item.status === "fulfilled" && item.value.status === "duplicate").length;
  const busyRetries = results.filter((item) => item.status === "rejected" && item.reason.statusCode === 503).length;
  assert.equal(duplicates + busyRetries, 19);
  const replay = await processEmailQueueRecord({db, emailId: "email-1", eventId: "replay", apiKey: "test-key", fetchImpl: send});
  assert.deepEqual(replay, {status: "duplicate", current: db.read("emailQueue", "email-1")});
  assert.equal(calls, 1);
});

test("expired worker lease can be reclaimed after a restart", async () => {
  const db = fakeDb({"emailQueue/email-1": record({
    status: "processing",
    eventId: "crashed",
    leaseExpiresAt: {toMillis: () => 1},
    attempts: 1,
  })});
  const claim = await claimEmail({db, emailId: "email-1", eventId: "restart", nowMs: 1000});
  assert.equal(claim.status, "claimed");
  assert.equal(db.read("emailQueue", "email-1").attempts, 2);
});

test("429 is retryable and succeeds on the bounded retry", async () => {
  const db = fakeDb({"emailQueue/email-1": record()});
  let calls = 0;
  await assert.rejects(processEmailQueueRecord({
    db, emailId: "email-1", eventId: "429", apiKey: "test-key",
    fetchImpl: async () => ({ok: false, status: 429, json: async () => ({name: "rate_limit"})}),
    nowMs: 1000,
  }), (error) => error.statusCode === 503);
  assert.equal(db.read("emailQueue", "email-1").status, "retryable_failed");
  const retryAt = db.read("emailQueue", "email-1").nextAttemptAt.toMillis();
  await assert.rejects(processEmailQueueRecord({
    db, emailId: "email-1", eventId: "early-retry", apiKey: "test-key", nowMs: retryAt - 1,
    fetchImpl: async () => {
      calls += 1;
      return {ok: true, status: 200, json: async () => ({id: "too-early"})};
    },
  }), (error) => error.statusCode === 503);
  assert.equal(calls, 0);
  const result = await processEmailQueueRecord({
    db, emailId: "email-1", eventId: "retry", apiKey: "test-key", nowMs: retryAt + 1,
    fetchImpl: async () => {
      calls += 1;
      return {ok: true, status: 200, json: async () => ({id: "resend-retry"})};
    },
  });
  assert.deepEqual(result, {status: "sent", providerId: "resend-retry"});
  assert.equal(calls, 1);
});

test("provider acceptance followed by a lost response retries with the same idempotency key", async () => {
  const db = fakeDb({"emailQueue/email-1": record()});
  const accepted = new Map();
  let requests = 0;
  const provider = async (_url, options) => {
    requests += 1;
    const key = options.headers["Idempotency-Key"];
    if (!accepted.has(key)) accepted.set(key, "provider-accepted-once");
    if (requests === 1) throw new TypeError("network response lost");
    return {ok: true, status: 200, json: async () => ({id: accepted.get(key)})};
  };
  await assert.rejects(processEmailQueueRecord({db, emailId: "email-1", eventId: "first", apiKey: "test-key",
    fetchImpl: provider, nowMs: 1000}), (error) => error.statusCode === 503);
  assert.equal(db.read("emailQueue", "email-1").status, "retryable_failed");
  const retryAt = db.read("emailQueue", "email-1").nextAttemptAt.toMillis();
  const result = await processEmailQueueRecord({db, emailId: "email-1", eventId: "replay", apiKey: "test-key",
    fetchImpl: provider, nowMs: retryAt + 1});
  assert.deepEqual(result, {status: "sent", providerId: "provider-accepted-once"});
  assert.equal(accepted.size, 1);
  assert.equal(requests, 2);
});

test("provider acceptance followed by a failed local sent write remains retryable", async () => {
  const db = fakeDb({"emailQueue/email-1": record()});
  const originalCollection = db.collection;
  let failSentWrite = true;
  db.collection = (name) => ({doc: (id) => {
    const document = originalCollection(name).doc(id);
    return {...document, set: async (value, options) => {
      if (name === "emailQueue" && value.status === "sent" && failSentWrite) {
        failSentWrite = false;
        throw new Error("write unavailable");
      }
      return document.set(value, options);
    }};
  }});
  const keys = [];
  const provider = async (_url, options) => {
    keys.push(options.headers["Idempotency-Key"]);
    return {ok: true, json: async () => ({id: "same-provider-id"})};
  };
  await assert.rejects(processEmailQueueRecord({db, emailId: "email-1", eventId: "first", apiKey: "test-key",
    fetchImpl: provider, nowMs: 1000}), (error) => error.statusCode === 503);
  assert.equal(db.read("emailQueue", "email-1").status, "processing");
  const second = await processEmailQueueRecord({db, emailId: "email-1", eventId: "recovery", apiKey: "test-key",
    fetchImpl: provider, nowMs: 1000 + 5 * 60 * 1000 + 1});
  assert.equal(second.status, "sent");
  assert.deepEqual(keys, ["email-1", "email-1"]);
});

test("5xx and timeout remain retryable without changing the source record", async () => {
  const db = fakeDb({
    "emailQueue/email-1": record({sourceCollection: "giftRequests", sourceDocumentId: "gift-1", sourceRequiredStatus: "delivered"}),
    "giftRequests/gift-1": {status: "delivered", paymentStatus: "paid"},
  });
  await assert.rejects(processEmailQueueRecord({
    db, emailId: "email-1", eventId: "5xx", apiKey: "test-key", fetchImpl: async () => ({ok: false, status: 503, json: async () => ({})}),
  }), (error) => error.statusCode === 503);
  assert.equal(db.read("emailQueue", "email-1").status, "retryable_failed");
  assert.equal(db.read("giftRequests", "gift-1").status, "delivered");
  const retryAt = db.read("emailQueue", "email-1").nextAttemptAt.toMillis();
  await assert.rejects(processEmailQueueRecord({
    db, emailId: "email-1", eventId: "timeout", apiKey: "test-key", nowMs: retryAt + 1,
    fetchImpl: async () => {
      throw Object.assign(new Error("timeout"), {retryable: true});
    },
  }), (error) => error.statusCode === 503);
  assert.equal(db.read("giftRequests", "gift-1").paymentStatus, "paid");
});

test("invalid and suppressed recipients terminate without provider calls", async () => {
  const invalidDb = fakeDb({"emailQueue/email-1": record({to: "not-an-email"})});
  let calls = 0;
  assert.deepEqual(await processEmailQueueRecord({
    db: invalidDb,
    emailId: "email-1",
    eventId: "invalid",
    fetchImpl: async () => {
      calls += 1;
    },
  }), {status: "suppressed", reason: "invalid_recipient"});
  assert.equal(calls, 0);
  const missingDb = fakeDb({"emailQueue/email-1": record({to: ""})});
  assert.deepEqual(await processEmailQueueRecord({db: missingDb, emailId: "email-1", eventId: "missing",
    fetchImpl: async () => {
      calls += 1;
    }}), {status: "suppressed", reason: "invalid_recipient"});
  assert.equal(calls, 0);
  const suppressedDb = fakeDb({"emailQueue/email-1": record({recipientSuppressed: true, suppressionReason: "unsubscribe"})});
  assert.deepEqual(await processEmailQueueRecord({db: suppressedDb, emailId: "email-1", eventId: "suppressed"}), {status: "suppressed", reason: "unsubscribe"});
});

test("source-state revalidation suppresses a stale queue record", async () => {
  const db = fakeDb({
    "emailQueue/email-1": record({sourceCollection: "giftRequests", sourceDocumentId: "gift-1", sourceRequiredStatus: "delivered"}),
    "giftRequests/gift-1": {status: "cancelled"},
  });
  let calls = 0;
  assert.deepEqual(await processEmailQueueRecord({
    db,
    emailId: "email-1",
    eventId: "source-changed",
    apiKey: "test-key",
    fetchImpl: async () => {
      calls += 1;
    },
  }), {status: "suppressed", reason: "source_state_changed"});
  assert.equal(calls, 0);
});

test("legacy Gift Story email without source and recipient revalidation is suppressed", async () => {
  const db = fakeDb({
    "emailQueue/legacy-gift-story": record({
      notificationId: "",
      type: "gift_story_ready",
      eventType: "gift_story_ready",
      giftRequestId: "gift-legacy",
      sourceCollection: undefined,
      sourceDocumentId: undefined,
      sourceRequiredStatus: undefined,
      sourceRecipientField: undefined,
    }),
    "giftRequests/gift-legacy": {status: "unlocked", senderEmail: "approved@example.com"},
  });
  let calls = 0;
  assert.deepEqual(await processEmailQueueRecord({
    db,
    emailId: "legacy-gift-story",
    eventId: "legacy-gift-story-replay",
    apiKey: "test-key",
    fetchImpl: async () => {
      calls += 1;
      return {ok: true, status: 200, json: async () => ({id: "unexpected"})};
    },
  }), {status: "suppressed", reason: "source_metadata_missing"});
  assert.equal(calls, 0);
});

test("Gift payment confirmation requires paid Gift, matching sender and completed debit", async () => {
  const queued = record({eventType: "gift_payment_confirmed", to: "sender@example.test",
    sourceCollection: "giftRequests", sourceDocumentId: "g-1", sourceRequiredStatus: "paid",
    sourceRecipientField: "senderEmail", giftPaymentRothAmount: 120, giftPaymentCardAmount: 0});
  const gift = {paymentStatus: "paid", senderEmail: "sender@example.test", walletContributionGbp: 120, remainingStripeAmountGbp: 0};
  const ledger = {status: "completed", amount: -120, referenceId: "g-1"};
  const db = fakeDb({"emailQueue/email-1": queued, "giftRequests/g-1": gift,
    "walletTransactions/gift_roth_g-1": ledger});
  let sends = 0;
  assert.equal((await processEmailQueueRecord({db, emailId: "email-1", eventId: "payment", apiKey: "test-key",
    fetchImpl: async () => {
sends += 1; return {ok: true, json: async () => ({id: "provider-1"})};
}})).status, "sent");
  assert.equal(sends, 1);
  for (const change of [{gift: {...gift, paymentStatus: "pending"}}, {gift: {...gift, senderEmail: "other@example.test"}},
    {ledger: {...ledger, status: "pending"}}]) {
    const fixture = fakeDb({"emailQueue/email-1": queued, "giftRequests/g-1": change.gift || gift,
      "walletTransactions/gift_roth_g-1": change.ledger || ledger});
    const result = await processEmailQueueRecord({db: fixture, emailId: "email-1", eventId: "invalid", apiKey: "test-key",
      fetchImpl: async () => {
throw new Error("must not send");
}});
    assert.equal(result.status, "suppressed");
  }
});

test("delivered and Story emails require matching current private token", async () => {
  const gift = {status: "delivered", giftStoryUnlocked: true, giftStoryStatus: "unlocked",
    giftStoryAccessToken: "senderToken", recipientStoryToken: "recipientToken",
    giftStoryAccessExpiresAt: {toMillis: () => Date.now() + 60000},
    senderEmail: "sender@example.test", recipientEmail: "recipient@example.test"};
  for (const [eventType, role, to, field, token] of [
    ["gift_delivered", "sender", "sender@example.test", "senderEmail", "senderToken"],
    ["gift_story_ready", "sender", "sender@example.test", "senderEmail", "senderToken"],
    ["gift_story_ready", "recipient", "recipient@example.test", "recipientEmail", "recipientToken"],
  ]) {
    const queued = record({eventType, to, sourceCollection: "giftRequests", sourceDocumentId: "g-2",
      sourceRequiredStatus: eventType === "gift_delivered" ? "delivered" : "unlocked",
      sourceRecipientField: field, sourceStoryRole: role, recipientRole: role,
      ctaUrl: `https://circumuk.com/story/${token}`});
    const db = fakeDb({"emailQueue/email-1": queued, "giftRequests/g-2": gift});
    assert.equal((await processEmailQueueRecord({db, emailId: "email-1", eventId: role, apiKey: "test-key",
      fetchImpl: async () => ({ok: true, json: async () => ({id: "provider"})})})).status, "sent");
    const wrong = fakeDb({"emailQueue/email-1": {...queued, ctaUrl: "https://circumuk.com/story/wrong"}, "giftRequests/g-2": gift});
    assert.equal((await processEmailQueueRecord({db: wrong, emailId: "email-1", eventId: "wrong", apiKey: "test-key",
      fetchImpl: async () => {
        throw new Error("must not send");
      }})).status, "suppressed");
    const wrongRole = fakeDb({"emailQueue/email-1": {...queued, recipientRole: role === "sender" ? "recipient" : "sender"},
      "giftRequests/g-2": gift});
    assert.equal((await processEmailQueueRecord({db: wrongRole, emailId: "email-1", eventId: "wrong-role", apiKey: "test-key",
      fetchImpl: async () => {
        throw new Error("must not send");
      }})).status, "suppressed");
  }
});

test("legacy delivered queue item waits for Story and renders the current secure link", async () => {
  const queued = record({eventType: "gift_delivered", to: "sender@example.test", recipientRole: "sender",
    sourceCollection: "giftRequests", sourceDocumentId: "g-legacy", sourceRequiredStatus: "delivered",
    subject: "Old delivery email", text: "Old email without Story", ctaUrl: "https://circumuk.com/?app=gifts"});
  const gift = {status: "delivered", senderEmail: "sender@example.test", recipientName: "Maya"};
  const db = fakeDb({"emailQueue/email-1": queued, "giftRequests/g-legacy": gift});
  await assert.rejects(processEmailQueueRecord({db, emailId: "email-1", eventId: "before-story",
    apiKey: "test-key", nowMs: 1000, fetchImpl: async () => {
throw new Error("must not send");
}}),
  (error) => error.statusCode === 503);
  assert.equal(db.read("emailQueue", "email-1").status, "retryable_failed");
  assert.equal(db.read("emailQueue", "email-1").maxAttempts, 20);
  const retryAt = db.read("emailQueue", "email-1").nextAttemptAt.toMillis();
  await db.collection("giftRequests").doc("g-legacy").set({giftStoryUnlocked: true, giftStoryStatus: "unlocked",
    giftStoryAccessToken: "secureToken", giftStoryAccessExpiresAt: {toMillis: () => Date.now() + 60000}}, {merge: true});
  let sent;
  const result = await processEmailQueueRecord({db, emailId: "email-1", eventId: "after-story", apiKey: "test-key",
    nowMs: retryAt + 1, fetchImpl: async (_url, options) => {
      sent = JSON.parse(options.body);
      return {ok: true, json: async () => ({id: "provider"})};
    }});
  assert.equal(result.status, "sent");
  assert.equal(sent.subject, "Your CIRCUM Gift has been delivered");
  assert.match(sent.html, /https:\/\/circumuk\.com\/story\/secureToken/);
  assert.doesNotMatch(sent.html, /Old email without Story/);
});

test("recipient is revalidated against the current authoritative source before provider call", async () => {
  const db = fakeDb({
    "emailQueue/email-1": record({sourceCollection: "businessInvoices", sourceDocumentId: "invoice-1", sourceRequiredStatus: "paid", sourceRecipientField: "billingEmail"}),
    "businessInvoices/invoice-1": {status: "paid", billingEmail: "changed@example.test"},
  });
  let calls = 0;
  assert.deepEqual(await processEmailQueueRecord({
    db, emailId: "email-1", eventId: "recipient-change", apiKey: "test-key",
    fetchImpl: async () => {
      calls += 1;
      return {ok: true, status: 200, json: async () => ({id: "unexpected"})};
    },
  }), {status: "suppressed", reason: "source_recipient_changed"});
  assert.equal(calls, 0);
});

test("Rider decision uses approvalStatus as an authoritative source state", async () => {
  const db = fakeDb({
    "emailQueue/rider-decision": record({sourceCollection: "riderProfiles", sourceDocumentId: "rider-1", sourceRequiredStatus: "approved", sourceRecipientField: "email", to: "rider@example.test"}),
    "riderProfiles/rider-1": {approvalStatus: "approved", email: "rider@example.test"},
  });
  const result = await processEmailQueueRecord({
    db, emailId: "rider-decision", eventId: "rider-decision-event", apiKey: "test-key",
    fetchImpl: async () => ({ok: true, status: 200, json: async () => ({id: "provider-rider"})}),
  });
  assert.equal(result.status, "sent");
});

test("welcome queue item revalidates the authoritative account and Starter Roth grant", async () => {
  const db = fakeDb({
    "emailQueue/sender_welcome_u-1": record({
      notificationId: "sender_welcome_u-1",
      eventType: "sender_welcome_ready",
      senderCategory: "info",
      sourceCollection: "users",
      sourceDocumentId: "u-1",
      sourceRequiredStatus: "active",
      sourceRecipientField: "email",
      sourceRequiredFields: {starterRothGrantStatus: "granted", starterRothTransactionId: "grant-u-1"},
      to: "welcome@example.test",
    }),
    "users/u-1": {
      status: "active", email: "welcome@example.test", starterRothGrantStatus: "granted",
      starterRothTransactionId: "grant-u-1",
    },
  });
  const result = await processEmailQueueRecord({
    db, emailId: "sender_welcome_u-1", eventId: "welcome-event", apiKey: "test-key",
    fetchImpl: async () => ({ok: true, status: 200, json: async () => ({id: "provider-welcome"})}),
  });
  assert.equal(result.status, "sent");
  const staleDb = fakeDb({
    "emailQueue/sender_welcome_u-2": record({
      notificationId: "sender_welcome_u-2", eventType: "sender_welcome_ready", sourceCollection: "users",
      sourceDocumentId: "u-2", sourceRequiredStatus: "active", sourceRecipientField: "email",
      sourceRequiredFields: {starterRothGrantStatus: "granted", starterRothTransactionId: "grant-u-2"},
      to: "welcome@example.test",
    }),
    "users/u-2": {status: "active", email: "welcome@example.test", starterRothGrantStatus: "pending"},
  });
  assert.deepEqual(await processEmailQueueRecord({
    db: staleDb, emailId: "sender_welcome_u-2", eventId: "welcome-stale", apiKey: "test-key",
    fetchImpl: async () => ({ok: true, status: 200, json: async () => ({id: "must-not-send"})}),
  }), {status: "suppressed", reason: "source_state_changed"});
});

test("referral queue item revalidates both finalized role ledgers at send time", async () => {
  const db = fakeDb({
    "emailQueue/referral-email": record({eventType: "referral_award_finalized", sourceCollection: "referrals", sourceDocumentId: "referred-1", sourceRequiredStatus: "roth_awarded", sourceRecipientField: "referrerEmail", to: "inviter@example.test"}),
    "referrals/referred-1": {status: "roth_awarded", referrerEmail: "inviter@example.test"},
    "walletTransactions/referral_reward_referred-1_referrer": {status: "completed"},
    "walletTransactions/referral_reward_referred-1_referred": {status: "pending"},
  });
  let calls = 0;
  assert.deepEqual(await processEmailQueueRecord({
    db, emailId: "referral-email", eventId: "referral-event", apiKey: "test-key",
    fetchImpl: async () => {
      calls++;
      return {ok: true, status: 200, json: async () => ({id: "not-sent"})};
    },
  }), {status: "suppressed", reason: "source_state_changed"});
  assert.equal(calls, 0);
});

test("permanent provider rejection ends as failed, not suppressed", async () => {
  const db = fakeDb({"emailQueue/email-1": record()});
  const result = await processEmailQueueRecord({
    db, emailId: "email-1", eventId: "permanent-provider", apiKey: "test-key",
    fetchImpl: async () => ({ok: false, status: 400, json: async () => ({name: "invalid_parameter"})}),
  });
  assert.equal(result.status, "failed");
  assert.equal(db.read("emailQueue", "email-1").status, "failed");
});

test("malformed Eventarc payload is rejected and health exposes only safe booleans", async () => {
  const server = createServer({processRecord: async () => ({status: "sent"})});
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  try {
    const {port} = server.address();
    const bad = await fetch(`http://127.0.0.1:${port}/`, {
      method: "POST",
      headers: {"ce-type": EVENT_TYPE, "ce-id": "bad-event"},
      body: Buffer.from("not-json"),
    });
    assert.equal(bad.status, 400);
    const health = await fetch(`http://127.0.0.1:${port}/health`);
    assert.equal(health.status, 200);
    assert.deepEqual(await health.json(), {
      status: "ok",
      service: "circum-transactional-email",
      sourceSha: "unknown",
      providerConfigured: false,
      fromConfigured: true,
    });
  } finally {
    server.close();
    await once(server, "close");
  }
});

test("Eventarc Firestore create is handed to the single queue processor", async () => {
  let received;
  const server = createServer({
    processRecord: async (input) => {
      received = input;
      return {status: "sent"};
    },
  });
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  try {
    const {port} = server.address();
    const response = await fetch(`http://127.0.0.1:${port}/`, {
      method: "POST",
      headers: {"content-type": "application/json", "ce-type": EVENT_TYPE, "ce-id": "eventarc-email-1"},
      body: eventBody("email-1"),
    });
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), {ok: true, status: "sent"});
    assert.equal(received.emailId, "email-1");
    assert.equal(received.eventId, "eventarc-email-1");
  } finally {
    server.close();
    await once(server, "close");
  }
});

test("Eventarc authoritative invoice update creates one queue item without invoking the provider", async () => {
  const name = "projects/circum-2797c/databases/(default)/documents/businessInvoices/invoice-2";
  const payload = DocumentEventData.encode({
    oldValue: {name, fields: {status: {stringValue: "partially_paid"}}},
    value: {name, fields: {
      status: {stringValue: "paid"},
      balanceDue: {doubleValue: 0},
      invoiceNumber: {stringValue: "INV-2"},
      businessId: {stringValue: "business-2"},
      billingEmail: {stringValue: "billing@example.test"},
    }},
    updateMask: {paths: ["status", "balanceDue"]},
  }).finish();
  const body = Buffer.from(JSON.stringify({message: {data: Buffer.from(payload).toString("base64")}}));
  const db = fakeDb();
  const server = createServer({dbFactory: () => db});
  server.listen(0);
  await once(server, "listening");
  const address = server.address();
  const response = await fetch(`http://127.0.0.1:${address.port}/`, {
    method: "POST",
    headers: {"ce-type": "google.cloud.firestore.document.v1.updated", "ce-id": "invoice-event-1"},
    body,
  });
  assert.equal(response.status, 200);
  assert.equal(db.read("emailQueue", "business_invoice_paid_invoice-2").to, "billing@example.test");
  server.close();
});
