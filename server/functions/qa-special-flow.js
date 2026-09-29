/* eslint-disable max-len, require-jsdoc */
"use strict";
const functions = require("firebase-functions/v1");
const {defineSecret} = require("firebase-functions/params");
const {getFirestore, Timestamp, FieldValue} = require("firebase-admin/firestore");
const {createHash} = require("node:crypto");
const {config, authorize, assertFixture, scopedDatabase} = require("./qa-lifecycle")._test;
const {providerForFixture, paymentProviderForFixture} = require("./qa-special-provider");
const qaLifecycle = require("./qa-lifecycle")._test;
const qaPublic = require("./qa-public-delivery");
const health = require("./health-plus")._qaHandlers;
const business = require("./business-payments")._qaHandlers;
const businessReservations = require("./business-checkout-reservations");
const movement = require("./movement-ledger");
const qaRoth = require("./qa-roth-certification");
const {normalizeEmail} = require("./wallet-core");
const irisQa = require("./qa-iris-certification");
const senderBooking = require("./sender-booking")._qa;
const cancellationPolicy = require("./delivery-policy-core");
const ROOT = "qaSpecialFlowFixtures";
const QA_STRIPE_SECRET = defineSecret("CIRCUM_QA_STRIPE_SECRET_KEY");
const COLLECTIONS = ["healthPlusProfiles", "prescriptionPickups", "healthPlusPayments", "healthPlusBookingIdempotency", "healthPlusUsageEvents", "healthPlusNotifications", "notifications", "businessAccounts", "businessInvoices", "businessCheckoutReservations", "businessInvoicePayments", "business_wallets", "adminAuditLogs", "wallets", "senderWallets", "walletTransactions", "giftPaymentDrafts", "giftCheckoutOrigins", "giftCheckoutReservations", "giftRequests", "giftPaymentEvents", "giftRecurringSeries", "giftRecurringRenewals", "paymentArtifactReconciliations", "deliveryRequests", "irisPhotoAnalyses"];
const fail = (message, code = "failed-precondition") => {
 throw new functions.https.HttpsError(code, message);
};
const senderActions = new Set(["sender_capability", "sender_quote", "sender_roth_prepare", "sender_roth_balance", "sender_payment_session", "sender_finalize", "sender_read", "sender_cancel"]);
const activityActions = new Set(["activity_seed", "activity_insert", "activity_delete_reference", "activity_pagination_seed", "activity_pagination_insert", "activity_page_fault"]);
const certificationActions = new Set(["wallet_notification_seed", "chat_retry_probe", "cancellation_quote_probe"]);
function fixtureIdForRequest(uid, requestId) {
  if (typeof requestId !== "string" || !/^lifecycle_[A-Za-z0-9_-]{1,64}$/.test(requestId)) fail("A bounded QA request ID is required.");
  return createHash("sha256").update(`special-v5:${uid}:${requestId}`).digest("hex");
}
function requiredFixtureId(value) {
  if (typeof value !== "string" || !/^[a-f0-9]{64}$/.test(value)) fail("A valid QA fixture ID is required.");
  return value;
}

function activityDeliveryId(fixtureId, suffix) {
  return `qa_activity_${fixtureId.slice(0, 12)}_${suffix}`;
}

function activityMillis(fixture, offsetMinutes) {
  const created = fixture.qaCreatedAt && typeof fixture.qaCreatedAt.toMillis === "function" ?
    fixture.qaCreatedAt.toMillis() : Date.now();
  return created - 30 * 60 * 1000 + offsetMinutes * 60 * 1000;
}

function activityDelivery(fixture, suffix, status, updatedAtMillis, extra = {}) {
  const id = activityDeliveryId(fixture.id, suffix);
  const timestamp = Timestamp.fromMillis(updatedAtMillis);
  const marker = {
    id,
    requestId: id,
    bookingId: id,
    senderId: fixture.senderId,
    userId: fixture.senderId,
    status,
    deliveryStatus: status,
    deliveryStage: status,
    paymentStatus: "unpaid",
    pickupDetails: {locality: `QA Fixture Pickup ${suffix}`},
    dropoffDetails: {locality: `QA Fixture Drop-off ${suffix}`},
    parcel: {itemName: `QA Activity Parcel ${suffix}`},
    createdAt: timestamp,
    updatedAt: timestamp,
    isSyntheticQa: true,
    qaActivityFixture: true,
    qaPublic: true,
    qaNamespace: ROOT,
    qaFixtureId: fixture.id,
    qaCreatedBy: fixture.qaCreatedBy,
    qaCreatedAt: fixture.qaCreatedAt,
    qaImmutable: true,
    realDispatch: false,
    suppressExternalSideEffects: true,
    excludeFromAnalytics: true,
    excludeFromSettlement: true,
    excludeFromPayout: true,
    excludeFromCustomerNotifications: true,
  };
  return {...marker, ...extra};
}

function activityExpectedOrder(records) {
  return records
      .filter((record) => !["in_transit"].includes(record.status))
      .sort((left, right) => {
        const byTime = right.updatedAt.toMillis() - left.updatedAt.toMillis();
        return byTime || right.id.localeCompare(left.id);
      })
      .map((record) => record.id);
}

function activityExpectedPages(expectedOrder, pageSize) {
  return Array.from({length: Math.ceil(expectedOrder.length / pageSize)}, (_, index) => ({
    page: index + 1,
    ids: expectedOrder.slice(index * pageSize, (index + 1) * pageSize),
  }));
}

async function seedActivityFixture(db, fixture) {
  const root = db.collection(ROOT).doc(fixture.id);
  const current = (await root.get()).data() || {};
  if (current.activitySeed && Array.isArray(current.activitySeed.historyIds)) {
    return current.activitySeed;
  }
  const statuses = [
    "completed", "cancelled", "scheduled", "completed", "archived",
    "completed", "cancelled", "completed", "scheduled", "completed",
    "cancelled", "completed", "completed", "scheduled", "completed",
    "cancelled", "completed", "completed", "scheduled", "completed",
    "completed", "cancelled", "completed", "completed",
  ];
  const records = statuses.map((status, index) => {
    const offset = index === 20 || index === 21 ? 12 : index + 1;
    const extra = status === "scheduled" ? {
      scheduledAt: Timestamp.fromMillis(activityMillis(fixture, 240)),
      deliveryTime: {type: "scheduled", scheduledAt: Timestamp.fromMillis(activityMillis(fixture, 240))},
    } : {};
    return activityDelivery(fixture, `h${String(index + 1).padStart(2, "0")}`, status, activityMillis(fixture, offset), extra);
  });
  const live = activityDelivery(fixture, "live", "in_transit", activityMillis(fixture, 60));
  const batch = db.batch();
  // Reverse write order deliberately; authoritative updatedAt plus document ID
  // ordering must determine the client result, never insertion order.
  for (const record of [...records].reverse()) {
    batch.create(db.collection("deliveryRequests").doc(record.id), record);
  }
  batch.create(db.collection("deliveryRequests").doc(live.id), live);
  const notificationId = activityDeliveryId(fixture.id, "notification");
  const missingNotificationId = activityDeliveryId(fixture.id, "missing_notification");
  const notificationBase = {
    recipientId: fixture.senderId,
    title: "QA Activity delivery update",
    body: "Synthetic QA activity notification.",
    type: "delivery_created",
    category: "deliveries",
    read: false,
    archived: false,
    createdAt: Timestamp.fromMillis(activityMillis(fixture, 70)),
    isSyntheticQa: true,
    qaActivityFixture: true,
    qaNamespace: ROOT,
    qaFixtureId: fixture.id,
    qaCreatedBy: fixture.qaCreatedBy,
    qaImmutable: true,
    suppressExternalSideEffects: true,
    excludeFromCustomerNotifications: true,
  };
  batch.create(db.collection("notifications").doc(notificationId), {
    ...notificationBase,
    destination: {route: "tracking", deliveryId: records[0].id},
    bookingId: records[0].id,
  });
  batch.create(db.collection("notifications").doc(missingNotificationId), {
    ...notificationBase,
    title: "QA Activity missing delivery update",
    destination: {route: "tracking", deliveryId: records[4].id},
    bookingId: records[4].id,
    createdAt: Timestamp.fromMillis(activityMillis(fixture, 69)),
  });
  const seed = {
    historyIds: activityExpectedOrder(records),
    liveId: live.id,
    scheduledId: records.find((record) => record.status === "scheduled").id,
    completedId: records.find((record) => record.status === "completed").id,
    cancelledId: records.find((record) => record.status === "cancelled").id,
    deletedReferenceId: records[4].id,
    notificationId,
    missingNotificationId,
    seededAt: Timestamp.now(),
  };
  batch.set(root, {activitySeed: seed}, {merge: true});
  await batch.commit();
  return seed;
}

async function insertActivityFixtureRecord(db, fixture) {
  const root = db.collection(ROOT).doc(fixture.id);
  const current = (await root.get()).data() || {};
  const seed = current.activitySeed;
  if (!seed) fail("QA Activity fixture is not seeded.");
  const id = activityDeliveryId(fixture.id, "late_insert");
  const record = activityDelivery(fixture, "late_insert", "completed", activityMillis(fixture, 80));
  const ref = db.collection("deliveryRequests").doc(id);
  const existing = await ref.get();
  if (!existing.exists) await ref.create(record);
  const historyIds = [id, ...seed.historyIds.filter((value) => value !== id)];
  await root.set({activitySeed: {...seed, historyIds, insertedId: id}}, {merge: true});
  return {...seed, historyIds, insertedId: id};
}

async function deleteActivityReference(db, fixture) {
  const seed = (await db.collection(ROOT).doc(fixture.id).get()).data()?.activitySeed;
  if (!seed?.deletedReferenceId) fail("QA Activity fixture reference is unavailable.");
  const ref = db.collection("deliveryRequests").doc(seed.deletedReferenceId);
  const snapshot = await ref.get();
  if (snapshot.exists) {
    const record = snapshot.data() || {};
    if (record.qaFixtureId !== fixture.id || record.isSyntheticQa !== true || record.qaActivityFixture !== true) {
      fail("QA Activity reference provenance is invalid.", "permission-denied");
    }
    await ref.delete();
  }
  await db.collection(ROOT).doc(fixture.id).set({activitySeed: {...seed, referenceDeleted: true}}, {merge: true});
  return {deletedReferenceId: seed.deletedReferenceId, deleted: snapshot.exists};
}

async function seedActivityPagination(db, fixture) {
  const root = db.collection(ROOT).doc(fixture.id);
  const current = (await root.get()).data() || {};
  if (current.activityPaginationSeed) return current.activityPaginationSeed;
  const records = Array.from({length: 121}, (_, index) => activityDelivery(
      fixture,
      `p${String(index + 1).padStart(3, "0")}`,
      index % 3 === 0 ? "cancelled" : "completed",
      activityMillis(fixture, index === 60 || index === 61 ? 500 : index + 1),
      {qaActivityPagination: true},
  ));
  let batch = db.batch(); let writes = 0;
  for (const record of [...records].reverse()) {
    batch.create(db.collection("deliveryRequests").doc(record.id), record);
    if (++writes === 400) {
      await batch.commit(); batch = db.batch(); writes = 0;
    }
  }
  if (writes) await batch.commit();
  const equalTimestampIds = records
      .filter((record) => record.updatedAt.toMillis() === activityMillis(fixture, 500))
      .map((record) => record.id)
      .sort((left, right) => right.localeCompare(left));
  const expectedOrder = activityExpectedOrder(records);
  const pageSize = 20;
  const result = {
    count: records.length,
    pageSize,
    pageCount: Math.ceil(expectedOrder.length / pageSize),
    expectedOrder,
    expectedPages: activityExpectedPages(expectedOrder, pageSize),
    equalTimestampIds,
    oldestId: expectedOrder[expectedOrder.length - 1],
    newestId: expectedOrder[0],
    firstPageExpectedId: expectedOrder[0],
    secondPageExpectedId: expectedOrder[pageSize],
    seededAt: Timestamp.now(),
  };
  await root.set({activityPaginationSeed: result}, {merge: true});
  return result;
}

async function insertActivityPaginationRecord(db, fixture) {
  const root = db.collection(ROOT).doc(fixture.id);
  const current = (await root.get()).data() || {};
  const seed = current.activityPaginationSeed;
  if (!seed) fail("QA Activity pagination fixture is not seeded.");
  const id = activityDeliveryId(fixture.id, "late_insert");
  const record = activityDelivery(fixture, "late_insert", "completed", activityMillis(fixture, 501), {qaActivityPagination: true});
  const ref = db.collection("deliveryRequests").doc(id);
  const existing = await ref.get();
  if (!existing.exists) await ref.create(record);
  const expectedOrder = [id, ...seed.expectedOrder.filter((value) => value !== id)];
  const result = {
    ...seed,
    count: expectedOrder.length,
    pageCount: Math.ceil(expectedOrder.length / seed.pageSize),
    expectedOrder,
    expectedPages: activityExpectedPages(expectedOrder, seed.pageSize),
    insertedId: id,
  };
  await root.set({activityPaginationSeed: result}, {merge: true});
  return result;
}

function activityPageFault(data) {
  const mode = `${data?.mode || ""}`.trim();
  if (!["unavailable", "rate_limit", "internal"].includes(mode)) fail("Unsupported Activity QA fault mode.", "invalid-argument");
  if (mode === "unavailable") fail("QA Activity page fault requested.", "unavailable");
  if (mode === "rate_limit") fail("QA Activity page fault requested.", "resource-exhausted");
  fail("QA Activity page fault requested.", "internal");
}

async function seedWalletNotification(db, fixture) {
  const id = activityDeliveryId(fixture.id, "wallet_payment_notification");
  const ref = db.collection("notifications").doc(id);
  const existing = await ref.get();
  if (!existing.exists) {
    await ref.create({
      recipientId: fixture.senderId,
      title: "QA Wallet payment received",
      body: "Synthetic QA wallet payment for certification.",
      type: "wallet_payment",
      category: "wallet",
      read: false,
      archived: false,
      createdAt: Timestamp.now(),
      destination: {route: "wallet"},
      walletTransactionId: id,
      isSyntheticQa: true,
      qaWalletNotification: true,
      qaNamespace: ROOT,
      qaFixtureId: fixture.id,
      qaCreatedBy: fixture.qaCreatedBy,
      qaCreatedAt: fixture.qaCreatedAt,
      qaImmutable: true,
      suppressExternalSideEffects: true,
    });
  }
  return {notificationId: id, category: "wallet", type: "wallet_payment", destinationRoute: "wallet", qaOnly: true};
}

async function chatRetryProbe(db, fixture) {
  const deliveryId = activityDeliveryId(fixture.id, "chat");
  const chatRef = db.collection("chats").doc(deliveryId);
  const message = "QA timeout retry message";
  const messageId = createHash("sha256").update(`${fixture.senderId}:${message}`).digest("hex");
  const result = await db.runTransaction(async (tx) => {
    const current = await tx.get(chatRef);
    const chat = current.exists ? current.data() || {} : {
      threadId: deliveryId, bookingId: deliveryId, requestId: deliveryId,
      participants: [fixture.senderId, fixture.riderId],
      members: [fixture.senderId, fixture.riderId],
      status: "active", isSyntheticQa: true, qaFixtureId: fixture.id,
      qaChatFixture: true, noExternalNotification: true,
    };
    const messages = Array.isArray(chat.messages) ? chat.messages : [];
    const alreadyStored = messages.some((item) => item && item.id === messageId);
    if (!alreadyStored) messages.push({id: messageId, senderId: fixture.senderId, text: message});
    tx.set(chatRef, {...chat, messages, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
    return {deliveryId, messageId, attempts: 2, created: alreadyStored ? 0 : 1, stored: messages.filter((item) => item && item.id === messageId).length};
  });
  return {...result, exactlyOnce: result.stored === 1, qaOnly: true};
}

async function cancellationQuoteProbe(db, fixture) {
  const deliveryId = activityDeliveryId(fixture.id, "cancellation");
  const ref = db.collection("deliveryRequests").doc(deliveryId);
  const existing = await ref.get();
  if (!existing.exists) {
    await ref.create(activityDelivery(fixture, "cancellation", "requested", Date.now(), {
      paymentStatus: "paid", qaCancellationFixture: true,
    }));
  }
  const decision = cancellationPolicy.cancellationDecision({
    delivery: {status: "requested"}, state: "requested", serverNow: Date.now(),
  });
  const breakdown = cancellationPolicy.cancellationSettlement({
    grossDeliveryTotal: 20, stripePaid: 20, rothPaid: 0,
    cancellationFee: decision.feeAmount, riderCompensation: decision.riderCompensation,
    circumRetained: decision.platformRetainedAmount,
  });
  const quote = cancellationPolicy.customerCancellationQuote({decision, breakdown});
  return {
    deliveryId,
    quoteKeys: Object.keys(quote).sort(),
    quote,
    sensitiveKeysPresent: ["riderCompensation", "circumRetained", "stripePaymentIntentId", "senderEmail", "paymentSessionId"]
        .filter((key) => Object.hasOwn(quote, key) || Object.hasOwn(quote.decision || {}, key)),
    qaOnly: true,
  };
}

async function deleteTopLevelQaRecords(db, fixtureId) {
  const collections = ["deliveryRequests", "chats", "notifications", "walletTransactions"];
  const deleted = {};
  for (const collection of collections) {
    const snapshot = await db.collection(collection).where("qaFixtureId", "==", fixtureId).limit(400).get();
    if (!snapshot.empty) {
      const batch = db.batch(); snapshot.docs.forEach((doc) => batch.delete(doc.ref)); await batch.commit();
    }
    deleted[collection] = snapshot.size;
  }
  return deleted;
}
function factory({db, env = process.env, stripe}) {
  const provider = (fixture) => providerForFixture({stripe, registry: db.collection(ROOT).doc(fixture.id).collection("qaCheckoutProviderObjects"), fixtureId: fixture.id, secret: env.CIRCUM_QA_STRIPE_SECRET_KEY});
  const paidProvider = (fixture, qa) => paymentProviderForFixture({stripe, qa, fixture, secret: env.CIRCUM_QA_STRIPE_SECRET_KEY});
  const lifecycle = qaLifecycle.factory({db, env, providerFactory: (qa, fixture) => paymentProviderForFixture({stripe, qa, fixture, secret: env.CIRCUM_QA_STRIPE_SECRET_KEY})});
  async function cleanup(fixture) {
    const ref = db.collection(ROOT).doc(fixture.id);
    // Operations may not race cleanup: one lease covers all external effects.
    await db.runTransaction(async (tx) => {
      const s = await tx.get(ref); const current = s.data();
      if (current.leaseUntil && current.leaseUntil > Date.now()) fail("QA operation still running; retry cleanup.");
      tx.update(ref, {closing: true});
    });
    if (fixture.lifecycleFixtureId) await lifecycle.handle({action: "cleanup", fixtureId: fixture.lifecycleFixtureId}, {auth: {uid: fixture.qaCreatedBy, token: {}}, app: {appId: "qa-cleanup"}});
    await qaPublic.cleanup({db, fixture});
    const senderResult = await senderBooking.cleanupQaSenderFixture(db, fixture);
    const activityNotifications = await db.collection("notifications").where("qaFixtureId", "==", fixture.id).limit(400).get();
    if (!activityNotifications.empty) {
      const notificationBatch = db.batch();
      activityNotifications.docs.forEach((doc) => notificationBatch.delete(doc.ref));
      await notificationBatch.commit();
    }
    const topLevelDeleted = await deleteTopLevelQaRecords(db, fixture.id);
    const testStripe = provider(fixture);
    const result = await testStripe.cleanup();
    const qa = scopedDatabase(db, fixture, true, ROOT, COLLECTIONS);
    const paidResult = await paidProvider(fixture, qa).cleanup();
    const reservations = await qa.collection("businessCheckoutReservations").get();
    for (const snap of reservations.docs) {
      await require("./business-checkout-reservations").terminate({db: qa, stripe: testStripe, reservation: snap.data()});
    }
    await ref.set({archived: true, cleanupResult: result, cleanedAt: Timestamp.now()}, {merge: true});
    return {...result, ...paidResult, sender: senderResult, activityNotificationsDeleted: activityNotifications.size, topLevelDeleted};
  }
  async function activeSenderFixture(uid) {
    const snapshot = await db.collection(ROOT)
        .where("senderId", "==", uid)
        .where("archived", "==", false)
        .limit(2)
        .get();
    const active = snapshot.docs
        .map((doc) => ({id: doc.id, ...doc.data()}))
        .find((fixture) => fixture.isSyntheticQa === true &&
          !fixture.closing && fixture.expiresAt && fixture.expiresAt.toMillis() > Date.now());
    return active || null;
  }
  function senderContext(uid, token = {}) {
    return {auth: {uid, token}, app: {appId: "qa-sender-web"}};
  }
  async function createSenderQuote(fixture, uid, data) {
    const sourceQuoteId = `${data.quoteId || ""}`.trim();
    if (!sourceQuoteId || sourceQuoteId.length > 160) fail("A canonical Sender quote is required.", "invalid-argument");
    const sourceRef = db.collection("senderBookingQuotes").doc(sourceQuoteId);
    const sourceSnap = await sourceRef.get();
    const source = sourceSnap.data();
    if (!sourceSnap.exists || !source || source.userId !== uid) fail("Booking quote not found.", "not-found");
    if (source.isSyntheticQa === true && source.qaFixtureId !== fixture.id) fail("Quote is outside the QA fixture.", "permission-denied");
    if (!source.parcelAuthority) fail("This quote requires a fresh parcel safety check.");
    const quoteId = `qa_sender_${fixture.id.slice(0, 24)}_${createHash("sha256").update(sourceQuoteId).digest("hex").slice(0, 24)}`;
    const marker = {isSyntheticQa: true, qaNamespace: ROOT, qaFixtureId: fixture.id, qaImmutable: true, sourceQuoteId};
    const ref = db.collection("senderBookingQuotes").doc(quoteId);
    const existing = await ref.get();
    if (existing.exists) {
      const current = existing.data() || {};
      if (current.userId !== uid || current.sourceQuoteId !== sourceQuoteId || current.qaFixtureId !== fixture.id) fail("QA quote binding changed.");
    } else {
      await ref.create({...source, ...marker, quoteId, userId: uid, createdAt: Timestamp.now()});
    }
    await db.collection(ROOT).doc(fixture.id).set({
      senderQuoteId: quoteId,
      senderSourceQuoteId: sourceQuoteId,
      senderSourceQuoteCreatedAt: source.createdAt || null,
    }, {merge: true});
    const quote = (await ref.get()).data();
    return {fixtureId: fixture.id, quoteId, amountDue: quote.amountDue || quote.total, currency: quote.currency || "GBP", quote};
  }
  async function handle(data, context) {
    const lists = config(env);
    // Capability discovery is safe for any authenticated, App Check-attested
    // Sender. It must return disabled for ordinary users so their normal Roth
    // balance and live payment path remain available; every mutating QA action
    // still goes through the strict allowlist authorization below.
    if (data && data.action === "sender_capability" && context && context.auth && context.auth.uid && context.app &&
        ![...lists.operators, ...lists.senders, ...lists.riders].includes(context.auth.uid)) {
      return {enabled: false};
    }
    const uid = authorize(context, lists);
    const lifecycleActions = new Set(["book", "pay", "read", "accept", "seed_legacy_status", "publish_location", "start_heading_to_pickup", "arrived_at_pickup", "verify_collection_pin", "confirm_collected", "start_delivery", "near_dropoff", "arrived_at_dropoff", "verify_receiver_pin", "capture_tip", "send_message", "cancel"]);
    if (!data || !["prepare", "health", "health_finalize", "business", "business_finalize", "public_delivery", "roth", "iris", "cleanup"].includes(data.action) && !lifecycleActions.has(data.action) && !senderActions.has(data.action) && !activityActions.has(data.action) && !certificationActions.has(data.action)) fail("Unknown QA action.");
    if (data.action === "sender_capability") {
      if (!lists.senders.includes(uid)) return {enabled: false};
      const active = await activeSenderFixture(uid);
      return active ? {enabled: true, fixtureId: active.id, qaOnly: true, paymentFamily: "sender_delivery"} : {enabled: false};
    }
    if (data.action === "sender_quote") {
      if (!lists.senders.includes(uid)) fail("QA Sender required.", "permission-denied");
      const fixture = await activeSenderFixture(uid);
      if (!fixture) fail("No active QA Sender fixture is available.");
      return createSenderQuote(fixture, uid, data);
    }
    // Fixed participant-scoped identity prevents an operator from accumulating live fixtures.
    if (["prepare", "cleanup"].includes(data.action) && !lists.operators.includes(uid)) fail("QA operator required.", "permission-denied");
    if (["health", "health_finalize", "business", "business_finalize", "public_delivery", "roth", "iris", ...senderActions, ...activityActions, ...certificationActions].includes(data.action) && !lists.senders.includes(uid)) fail("QA Sender required.", "permission-denied");
    const id = data.action === "prepare" ?
      fixtureIdForRequest(uid, data.requestId) : requiredFixtureId(data.fixtureId);
    const ref = db.collection(ROOT).doc(id);
    if (data.action === "prepare") {
      const previous = await ref.get();
      if (previous.exists && previous.data().archived === true) fail("This QA request was archived. Use a new request ID.");
      const created = await lifecycle.handle({action: "create", requestId: `special_v5_${data.requestId}`, senderId: lists.senders[0], riderId: lists.riders[0]}, context);
      await db.runTransaction(async (tx) => {
        const current = await tx.get(ref); if (current.exists) return;
        const now = Timestamp.now();
        tx.create(ref, {id, isSyntheticQa: true, qaCreatedBy: uid, qaCreatedAt: now, senderId: lists.senders[0], riderId: lists.riders[0], lifecycleFixtureId: created.fixtureId, expiresAt: Timestamp.fromMillis(now.toMillis() + 3600000), archived: false});
        tx.create(ref.collection("businessAccounts").doc("qa_business"), {ownerUid: lists.senders[0], isSyntheticQa: true, qaFixtureId: id});
        // An unpaid, fixed synthetic invoice is setup data, not a payment transition.
        tx.create(ref.collection("businessInvoices").doc("qa_invoice"), {businessId: "qa_business", total: 5, balanceDue: 5, amountPaid: 0, status: "issued", checkoutProtocolVersion: 1, isSyntheticQa: true, qaFixtureId: id});
      });
      return {fixtureId: id};
    }
    const fixture = (await ref.get()).data(); assertFixture(fixture, lists, uid, Date.now(), data.action === "cleanup");
    if (data.action === "cleanup") return cleanup(fixture);
    if (activityActions.has(data.action)) {
      if (uid !== fixture.senderId) fail("QA Sender required.", "permission-denied");
      if (data.action === "activity_seed") return {...await seedActivityFixture(db, fixture), fixtureId: fixture.id, qaOnly: true};
      if (data.action === "activity_insert") return {...await insertActivityFixtureRecord(db, fixture), fixtureId: fixture.id, qaOnly: true};
      if (data.action === "activity_pagination_seed") return {...await seedActivityPagination(db, fixture), fixtureId: fixture.id, qaOnly: true};
      if (data.action === "activity_pagination_insert") return {...await insertActivityPaginationRecord(db, fixture), fixtureId: fixture.id, qaOnly: true};
      if (data.action === "activity_page_fault") return activityPageFault(data);
      return {...await deleteActivityReference(db, fixture), fixtureId: fixture.id, qaOnly: true};
    }
    if (certificationActions.has(data.action)) {
      if (data.action === "wallet_notification_seed") return seedWalletNotification(db, fixture);
      if (data.action === "chat_retry_probe") return chatRetryProbe(db, fixture);
      return cancellationQuoteProbe(db, fixture);
    }
    if (senderActions.has(data.action)) {
      if (uid !== fixture.senderId) fail("QA Sender required.", "permission-denied");
      const qaContext = {fixtureId: fixture.id, isSyntheticQa: true};
      if (data.action === "sender_quote") return createSenderQuote(fixture, uid, data);
      if (data.action === "sender_roth_prepare") {
        const email = normalizeEmail(context.auth.token.email);
        if (!email) fail("QA Sender email is required.", "permission-denied");
        const qa = scopedDatabase(db, fixture, false, ROOT, COLLECTIONS);
        return {...await qaRoth.seed({qa, fixture, uid, email}), qaOnly: true, fixtureId: fixture.id};
      }
      if (data.action === "sender_roth_balance") {
        const email = normalizeEmail(context.auth.token.email);
        if (!email) fail("QA Sender email is required.", "permission-denied");
        const qa = scopedDatabase(db, fixture, false, ROOT, COLLECTIONS);
        const wallet = (await qa.collection("wallets").doc(email).get()).data();
        if (!wallet || wallet.uid !== uid || wallet.qaFixtureId !== fixture.id) {
          fail("QA Roth fixture is not prepared.", "failed-precondition");
        }
        return {qaOnly: true, fixtureId: fixture.id, balance: Number(wallet.balance || 0), availableRoth: Number(wallet.balance || 0), currency: "ROTH"};
      }
      if (data.action === "sender_payment_session") {
        const result = await senderBooking.createSenderPaymentSession(
            provider(fixture),
            {...data, quoteId: `${data.quoteId || ""}`, checkoutMode: "web_checkout", returnUrl: "https://circum-app-2797c.web.app/"},
            senderContext(uid, context.auth.token),
            {db, qaContext},
        );
        return {...result, qaOnly: true, fixtureId: fixture.id};
      }
      if (data.action === "sender_finalize") {
        const paymentSessionId = `${data.paymentSessionId || ""}`;
        const checkoutSessionId = `${data.checkoutSessionId || ""}`;
        if (!paymentSessionId || !checkoutSessionId) fail("Confirmed QA checkout is required.", "invalid-argument");
        const session = await provider(fixture).checkout.sessions.retrieve(checkoutSessionId);
        if (`${session.metadata && session.metadata.paymentSessionId || ""}` !== paymentSessionId) {
          fail("QA checkout does not match the payment session.", "permission-denied");
        }
        const result = await senderBooking.finalizeSenderCheckoutSession(
            provider(fixture),
            session,
            `qa_${paymentSessionId}`,
            {db, qaContext},
        );
        return {...result, qaOnly: true, fixtureId: fixture.id};
      }
      if (data.action === "sender_read") {
        const deliveryId = `${data.deliveryId || ""}`;
        const snapshot = await db.collection("deliveryRequests").doc(deliveryId).get();
        if (!snapshot.exists || snapshot.data().qaFixtureId !== fixture.id || snapshot.data().isSyntheticQa !== true) fail("QA delivery not found.", "not-found");
        return {qaOnly: true, fixtureId: fixture.id, delivery: {id: snapshot.id, ...snapshot.data()}};
      }
      if (data.action === "sender_cancel") {
        const deliveryId = `${data.deliveryId || ""}`;
        const ref = db.collection("deliveryRequests").doc(deliveryId);
        const snapshot = await ref.get();
        if (!snapshot.exists || snapshot.data().qaFixtureId !== fixture.id || snapshot.data().isSyntheticQa !== true) fail("QA delivery not found.", "not-found");
        await ref.set({status: "cancelled", deliveryStatus: "cancelled", dispatchStatus: "suppressed_qa", cancellationReason: "qa_cleanup", updatedAt: Timestamp.now()}, {merge: true});
        return {qaOnly: true, cancelled: true, deliveryId};
      }
    }
    if (data.action === "public_delivery") {
      if (uid !== fixture.senderId) fail("QA Sender required.", "permission-denied");
      return qaPublic.createPublicDelivery({db, fixture, actorUid: uid});
    }
    if (lifecycleActions.has(data.action)) {
      const payload = {...data, fixtureId: fixture.lifecycleFixtureId}; delete payload.profileOverride;
      if (data.action !== "publish_location") delete payload.status;
      return lifecycle.handle(payload, context);
    }
    const leaseId = require("node:crypto").randomUUID();
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref); const current = snap.data();
      assertFixture(current, lists, uid);
      if (current.leaseUntil > Date.now()) fail("QA operation in progress; retry.");
      tx.update(ref, {leaseId, leaseUntil: Date.now() + 300000});
    });
    try {
      const qa = scopedDatabase(db, fixture, false, ROOT, COLLECTIONS); const testStripe = provider(fixture);
      const actual = paidProvider(fixture, qa);
      if (data.action === "roth") {
        if (!qaRoth.ACTIONS.has(data.scenario)) fail("Unknown QA Roth scenario.", "invalid-argument");
        const email = context.auth.token.email;
        if (typeof email !== "string" || !email.includes("@")) fail("QA Sender email is required.", "permission-denied");
        const args = {qa, fixture, uid, email, stripe: actual};
        if (data.scenario === "prepare") return qaRoth.seed(args);
        if (data.scenario === "roth_only" || data.scenario === "split") return qaRoth.pay({...args, type: data.scenario});
        if (data.scenario === "insufficient") return qaRoth.insufficient(args);
        if (data.scenario === "read") return qaRoth.read(args);
        return qaRoth.reconcile(args);
      }
      if (data.action === "iris") {
        if (typeof data.scenario !== "string" || !Object.hasOwn(irisQa.SCENARIOS, data.scenario)) fail("Unknown synthetic IRIS scenario.", "invalid-argument");
        const result = irisQa.analyse({uid, scenario: data.scenario});
        if (!result.photo) return result;
        const photoRef = qa.collection("irisPhotoAnalyses").doc(result.photo.analysisId);
        const idempotent = await qa.runTransaction(async (tx) => {
          const existing = await tx.get(photoRef);
          if (!existing.exists) tx.create(photoRef, {...result.photo, createdAt: FieldValue.serverTimestamp(), expiresAt: Timestamp.fromMillis(Date.now() + 24 * 60 * 60 * 1000)});
          return existing.exists;
        });
        const safePhoto = {...result.photo};
        delete safePhoto.imageHash; delete safePhoto.descriptionHash;
        return {scenario: result.scenario, iris: result.iris, photo: safePhoto, idempotent};
      }
      if (data.action === "health_finalize") {
        const payments = await qa.collection("healthPlusPayments").limit(2).get();
        if (payments.size !== 1) fail("One canonical Health+ checkout is required.");
        const payment = payments.docs[0].data(); const bookingId = payments.docs[0].id;
        const deliveryId = `health_${bookingId}`;
        await qa.doc(`deliveryRequests/${deliveryId}`).set({deliveryId, senderId: fixture.senderId, status: "booked", paymentStatus: "unpaid", serviceType: "health_plus", isSyntheticQa: true, qaFixtureId: fixture.id}, {merge: true});
        const intent = await actual.paymentIntents.create({amount: Math.round(payment.cardAmount * 100), currency: "gbp", payment_method: "pm_card_visa", payment_method_types: ["card"], confirm: true, metadata: {isSyntheticQa: "true", qaFixtureId: fixture.id, deliveryId, paymentType: "health_plus_payment"}}, {idempotencyKey: `health_${bookingId}`});
        const session = {id: payment.checkoutSessionId, livemode: false, payment_status: "paid", status: "complete", amount_total: intent.amount_received, currency: "gbp", payment_intent: intent.id, metadata: {bookingId, profileId: payment.profileId, userId: payment.senderId, userEmail: payment.userEmail || ""}};
        await health.handleHealthPlusCheckoutSessionHandler(session, `qa_${intent.id}`, {db: qa});
        const pickup = (await qa.doc(`prescriptionPickups/${bookingId}`).get()).data();
        await movement.projectHealth(qa, bookingId, pickup);
        await qa.doc(`deliveryRequests/${deliveryId}`).set({profileId: FieldValue.delete()}, {merge: true});
        return {paid: true, providerId: intent.id, deliveryId, amountPence: intent.amount_received};
      }
      if (data.action === "business") {
        const result = await business.createBusinessInvoiceCheckoutHandler(testStripe, {invoiceId: "qa_invoice", businessId: "qa_business", useRoth: false}, context, {db: qa});
        return {fixtureId: id, sessionId: result.sessionId, reservationId: result.checkoutReservationId, cardAmount: result.cardAmount, rothApplied: result.rothApplied};
      }
      if (data.action === "business_finalize") {
        const reservations = await qa.collection("businessCheckoutReservations").limit(2).get();
        if (reservations.size !== 1) fail("One canonical Business checkout is required.");
        const reservation = reservations.docs[0].data(); const deliveryId = "business_qa_invoice";
        await qa.doc(`deliveryRequests/${deliveryId}`).set({deliveryId, senderId: fixture.senderId, status: "booked", paymentStatus: "unpaid", serviceType: "business", isBusiness: true, businessMode: true, trustPointsAwarded: 3, pickupAddress: "Synthetic QA Business pickup", dropoffAddress: "Synthetic QA Business dropoff", routeDistanceMetres: 2400, routeDurationSeconds: 720}, {merge: true});
        const intent = await actual.paymentIntents.create({amount: reservation.externalAmount, currency: "gbp", payment_method: "pm_card_visa", payment_method_types: ["card"], confirm: true, metadata: {isSyntheticQa: "true", qaFixtureId: fixture.id, deliveryId, paymentType: "business_invoice_payment"}}, {idempotencyKey: `business_${reservation.checkoutReservationId}`});
        const session = {id: reservation.providerSessionId, livemode: false, payment_status: "paid", status: "complete", amount_total: intent.amount_received, currency: "gbp", payment_intent: intent.id, metadata: {type: "business_invoice_payment", checkoutReservationId: reservation.checkoutReservationId, invoiceId: reservation.invoiceId, businessId: reservation.businessId}};
        await businessReservations.settle({db: qa, session, id: reservation.checkoutReservationId});
        await qa.doc(`deliveryRequests/${deliveryId}`).set({status: "requested", paymentStatus: "paid", stripePaymentIntentId: intent.id}, {merge: true});
        return {paid: true, providerId: intent.id, deliveryId, amountPence: intent.amount_received};
      }
      const booking = await health.createHealthPlusBookingHandler({
        consentConfirmed: true, fullName: "Synthetic QA", email: context.auth.token.email, phoneNumber: "07000000000",
        pharmacyAddress: "10 Downing Street, London SW1A 2AA", deliveryAddress: "Trafalgar Square, London WC2N 5DN", preferredPickupTime: "12:00", frequency: "one_off",
        pricingInputs: {medicationWeightKg: 0.5}, subscriptionPlan: "priority", idempotencyKey: `qa_health_${id}`,
      }, context, {db: qa});
      let code = 200; let body;
      const res = {set() {
return this;
}, setHeader() {}, status(value) {
code = value; return this;
}, send(value) {
body = value; return this;
}, json(value) {
body = value; return this;
}};
      await health.createHealthPlusCheckoutHandler({method: "POST", headers: context.rawRequest.headers, body: {bookingId: booking.pickupId, profileId: booking.profileId, useRoth: false}}, res, {db: qa, stripe: testStripe});
      if (code !== 200) fail(`Canonical QA checkout rejected (${code}).`);
      const payment = (await qa.doc(`healthPlusPayments/${booking.pickupId}`).get()).data();
      return {fixtureId: id, bookingId: booking.pickupId, amountPence: booking.amountPence, sessionId: payment.checkoutSessionId || body.sessionId, routeAuthority: (await qa.doc(`prescriptionPickups/${booking.pickupId}`).get()).data().routeAuthorityVersion};
    } finally {
      await db.runTransaction(async (tx) => {
        const snap = await tx.get(ref); if (snap.data().leaseId === leaseId) tx.update(ref, {leaseUntil: 0});
      });
    }
  }
  async function expire() {
    config(env);
    const all = await db.collection(ROOT).where("archived", "==", false).get();
    const results = [];
    for (const doc of all.docs) {
if (doc.data().expiresAt.toMillis() <= Date.now()) {
      try {
results.push(await cleanup(doc.data()));
} catch (error) {
console.error("QA cleanup remains pending", {fixtureId: doc.id, message: error.message});
}
    }
}
    return {processed: results.length};
  }
  return {handle, expire};
}
function instance() {
  const secret = process.env.CIRCUM_QA_STRIPE_SECRET_KEY;
  if (!secret || !secret.startsWith("sk_test_")) fail("TEST provider required.");
  return factory({db: getFirestore(), stripe: require("stripe")(secret, {timeout: 20000, maxNetworkRetries: 1})});
}
exports.callable = () => functions.runWith({enforceAppCheck: true, timeoutSeconds: 180, secrets: [QA_STRIPE_SECRET, "GOOGLE_MAPS_DIRECTIONS_API_KEY"]}).https.onCall((data, context) => instance().handle(data, context));
exports.scheduled = () => functions.runWith({timeoutSeconds: 180, secrets: [QA_STRIPE_SECRET]}).pubsub.schedule("every 10 minutes").onRun(() => instance().expire());
exports._test = {factory, fixtureIdForRequest, requiredFixtureId, activityDelivery};
