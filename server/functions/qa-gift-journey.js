/* eslint-disable max-len, require-jsdoc */
"use strict";
const crypto = require("node:crypto");
const {Timestamp} = require("firebase-admin/firestore");
const {fixtureDb} = require("./gift-story-fixture-db");
const payment = require("./gifts-payment")._private;
const {publishFromEvent, CREATED, UPDATED} = require("./transactional-email-publishers");
const {notifyGiftStatus} = require("./platform-notifications")._private;
const story = require("./gift-story-automation");
const {processEmailQueueRecord} = require("./cloud-run-transactional-email");
const ROOT = "giftStoryRuntimeFixtures";
const PURPOSE = "gift_journey_certification";
const ROUTING = "qa_isolated_gift_journey";
const fail = (code, message) => {
 throw Object.assign(new Error(message), {code});
};
const hash = (x) => crypto.createHash("sha256").update(x).digest("hex");
function scopedDb(raw, fid) {
  const base = fixtureDb(raw, fid);
  const prefix = `${ROOT}/${fid}/state/`;
  const guard = (ref) => {
 if (!ref || !ref.path || !ref.path.startsWith(prefix)) fail("permission-denied", "Private fixture scope required.");
};
  return {...base,
    collection(name) {
 if (name === ROOT) fail("permission-denied", "Private fixture scope required."); return base.collection(name);
},
    doc(path) {
      const parts = String(path).split("/");
      if (parts.length !== 2 || !parts[1] || /[.#\]]|\[/.test(parts[1])) fail("invalid-argument", "Invalid private record.");
      return base.collection(parts[0]).doc(parts[1]);
    },
    runTransaction: (fn) => raw.runTransaction((tx) => fn({
      getAll: (...refs) => {
 refs.forEach(guard); return tx.getAll(...refs);
},
      get: (r) => {
 guard(r); return tx.get(r);
},
      set: (r, ...args) => {
 guard(r); return tx.set(r, ...args);
},
      create: (r, ...args) => {
 guard(r); return tx.create(r, ...args);
},
      update: (r, ...args) => {
 guard(r); return tx.update(r, ...args);
},
      delete: (r) => {
 guard(r); return tx.delete(r);
},
    })),
  };
}
function testProvider(stripe, fid) {
  const checked = (obj) => {
    if (!obj || obj.livemode !== false || obj.metadata?.qaFixtureId !== fid) fail("failed-precondition", "Matching TEST provider object required.");
    return obj;
  };
  return {
    customers: {
      create: async (params, options) => checked(await stripe.customers.create({metadata: {...params.metadata, qaFixtureId: fid}}, {idempotencyKey: `${fid}:${options.idempotencyKey}`})),
      retrieve: async (id) => checked(await stripe.customers.retrieve(id)),
    },
    paymentIntents: {
      create: async (params, options) => {
        if (params.amount !== 5000 || params.currency !== "gbp" || !options?.idempotencyKey || params.metadata?.type !== "gift_payment_intent") fail("failed-precondition", "Fixed one-off TEST Gift required.");
        const safe = {...params, payment_method_types: ["card"], metadata: {...params.metadata, type: ROUTING, qaFixtureId: fid}};
        delete safe.automatic_payment_methods; delete safe.receipt_email; delete safe.setup_future_usage;
        return checked(await stripe.paymentIntents.create(safe, options));
      },
      retrieve: async (id) => checked(await stripe.paymentIntents.retrieve(id)),
    },
    ephemeralKeys: {create: async () => ({secret: "private_TEST_not_returned"})},
    checkout: {sessions: {list: async () => ({data: []})}},
  };
}
function factory({raw, stripe, secret, credentials, now = Date.now}) {
  if (!secret?.startsWith("sk_test_")) fail("failed-precondition", "TEST provider required.");
  const ids = credentials?.identities;
  if (!["admin", "sender", "rider"].every((r) => typeof ids?.[r]?.uid === "string") || new Set([ids.admin.uid, ids.sender.uid, ids.rider.uid]).size !== 3) fail("failed-precondition", "Private QA identities required.");
  function actor(context) {
    if (!context?.auth?.uid || !context.app) fail("unauthenticated", "Auth and App Check required.");
    const role = ["admin", "sender", "rider"].find((r) => ids[r].uid === context.auth.uid);
    if (!role) fail("permission-denied", "Approved QA identity required.");
    return role;
  }
  const own = (role, expected) => {
 if (role !== expected) fail("permission-denied", "Wrong QA actor.");
};
  async function prepare(data, context, role) {
    own(role, "admin");
    if (!/^[A-Za-z0-9_-]{1,60}$/.test(data.requestId || "")) fail("invalid-argument", "Bounded request identity required.");
    const fid = `__codex_giftqa_${hash(`${context.auth.uid}:${data.requestId}`).slice(0, 40)}`;
    const ref = raw.collection(ROOT).doc(fid); const lock = raw.collection("qaGiftJourneyLocks").doc(context.auth.uid);
    await raw.runTransaction(async (tx) => {
      const [previous, existing] = await Promise.all([tx.get(lock), tx.get(ref)]);
      if (previous.exists && previous.data().fixtureId !== fid) fail("failed-precondition", "Existing Gift fixture must be cleaned first.");
      if (existing.exists) {
        if (existing.data().purpose !== PURPOSE || existing.data().qaCreatedBy !== context.auth.uid || existing.data().expiresAt.toMillis() <= now()) fail("failed-precondition", "Fixture closed; clean it before starting again.");
        return;
      }
      tx.create(ref, {purpose: PURPOSE, testOnly: true, suppressExternalSideEffects: true, qaCreatedBy: context.auth.uid, createdAt: Timestamp.fromMillis(now()), expiresAt: Timestamp.fromMillis(now() + 3600000)});
      tx.set(lock, {fixtureId: fid});
    });
    const db = scopedDb(raw, fid);
    await db.collection("systemConfiguration").doc("giftsCommunicationsPolicy").set({version: "gifts-communications-v1", effectiveAt: "2026-09-26T16:41:34Z"});
    await db.collection("runtimeOwnership").doc("giftStoryCompletion").set({owner: "cloud_run"});
    await db.collection("adminUsers").doc(ids.admin.uid).set({role: "operations_admin", status: "active"});
    return {fixtureId: fid, stripeMode: "TEST", amountPence: 5000};
  }
  async function effects(db, fid, before, after) {
    await publishFromEvent({db, eventType: before ? UPDATED : CREATED, eventId: `qa_${fid}_${after.status}`, decoded: {documentName: `projects/circum-2797c/databases/(default)/documents/giftRequests/${fid}`, before: before || {}, after}});
    await notifyGiftStatus({db, suppressPush: true, giftId: fid, before: before || {}, after});
  }
  async function drain(db) {
    const queue = await db.collection("emailQueue").get();
    for (const row of queue.docs) {
await processEmailQueueRecord({db, emailId: row.id, eventId: `qa_consume_${row.id}`, apiKey: "private-stub-only", fetchImpl: async (_url, options) => {
      const body = JSON.parse(options.body);
      if (!body.to.every((to) => to.endsWith("@example.test") || to === ids.sender.email)) fail("permission-denied", "Fixture recipient required.");
      return {ok: true, status: 200, json: async () => ({id: crypto.randomUUID()})};
    }});
}
    return queue.size;
  }
  async function handle(data, context) {
    const role = actor(context);
    if (data.action === "prepare") return prepare(data, context, role);
    const fid = data.fixtureId;
    if (!/^__codex_giftqa_[a-f0-9]{40}$/.test(fid || "")) fail("invalid-argument", "Private fixture identity required.");
    const root = raw.collection(ROOT).doc(fid); const snap = await root.get(); const fixture = snap.data();
    if (!snap.exists || fixture.purpose !== PURPOSE || fixture.testOnly !== true || fixture.suppressExternalSideEffects !== true || fixture.qaCreatedBy !== ids.admin.uid) fail("not-found", "Private Gift fixture unavailable.");
    if (data.action !== "cleanup" && fixture.expiresAt.toMillis() <= now()) fail("failed-precondition", "Fixture expired; cleanup required.");
    const lease = crypto.randomUUID();
    await raw.runTransaction(async (tx) => {
      const current = (await tx.get(root)).data();
      if (!current) fail("not-found", "Fixture closed.");
      if (current.leaseUntil?.toMillis() > now()) fail("unavailable", "Fixture request in progress; retry.");
      tx.update(root, {lease, leaseUntil: Timestamp.fromMillis(now() + 120000)});
    });
    const db = scopedDb(raw, fid); const provider = testProvider(stripe, fid);
    try {
      if (data.action === "checkout") {
        own(role, "sender");
        const paid = await db.collection("giftRequests").doc(fid).get();
        if (paid.exists && paid.data().paymentStatus === "paid") return {giftRequestId: fid, paymentStatus: "paid", idempotent: true};
        const result = await payment.createGiftPaymentHandler(provider, db)({giftDraftId: fid, checkoutMode: "payment_intent", applyRoth: false, paymentMethod: "card", giftDraft: {grossGiftBudget: 50, giftMode: "someone", recipientName: "TEST Recipient", recipientEmail: "recipient@example.test", deliveryAddress: "TEST private address", relationship: "friend", occasion: "TEST certification", giftMessage: "TEST only"}}, context);
        return {giftDraftId: fid, paymentIntentId: result.paymentIntentId, amountPence: 5000, stripeMode: "TEST"};
      }
      if (data.action === "confirm_test_payment") {
        own(role, "admin");
        const ref = db.collection("giftRequests").doc(fid); const existing = await ref.get();
        const draft = await db.collection("giftPaymentDrafts").doc(fid).get();
        const id = draft.data()?.stripePaymentIntentId || existing.data()?.stripePaymentIntentId;
        if (!id) fail("failed-precondition", "Checkout required.");
        let intent = await provider.paymentIntents.retrieve(id);
        if (intent.metadata.type !== ROUTING || intent.metadata.senderId !== ids.sender.uid || intent.metadata.giftDraftId !== fid || intent.amount !== 5000 || intent.currency !== "gbp") fail("failed-precondition", "TEST Gift binding mismatch.");
        if (intent.status !== "succeeded") intent = await stripe.paymentIntents.confirm(id, {payment_method_data: {type: "card", card: {token: "tok_visa"}}, return_url: "https://example.invalid/qa"}, {idempotencyKey: `qa_confirm_${fid}`});
        if (intent.livemode !== false || intent.status !== "succeeded" || intent.amount_received !== 5000) fail("failed-precondition", "Confirmed matching TEST payment required.");
        const result = await payment.finalizeGiftPaymentAuthority({db, stripe: provider, giftDraftId: fid, actorUid: ids.sender.uid, eventId: `qa_${intent.id}`, verifiedVoiceNote: null, payment: {provider: "payment_intent", providerId: intent.id, paymentIntentId: intent.id, amountPence: intent.amount_received, currency: intent.currency, status: intent.status, metadata: intent.metadata, customerId: intent.customer}});
        if (!existing.exists) {
 await effects(db, fid, null, (await ref.get()).data()); await drain(db);
}
        return {...result, livemode: false};
      }
      if (data.action === "advance") {
        own(role, "admin");
        const statuses = ["submitted_for_review", "approved", "curation_started", "ready_for_gift_delivery"];
        const ref = db.collection("giftRequests").doc(fid); const before = (await ref.get()).data();
        if (!before || before.paymentStatus !== "paid" || !statuses.slice(1).includes(data.status)) fail("failed-precondition", "Paid Gift transition required.");
        const from = statuses.indexOf(before.status); const to = statuses.indexOf(data.status);
        if (to < from || to > from + 1) fail("failed-precondition", "Out-of-order Gift transition.");
        await require("./admin-operations-authority")._private.saveGiftRequestEditor({giftId: fid, patch: {status: data.status}, reason: "Isolated TEST certification"}, context, {db});
        await effects(db, fid, before, (await ref.get()).data()); await drain(db);
        return {status: data.status, idempotent: to === from};
      }
      if (data.action === "complete_delivery") {
        own(role, "rider");
        const ref = db.collection("giftRequests").doc(fid); const before = (await ref.get()).data();
        if (!before || !["ready_for_gift_delivery", "delivered"].includes(before.status)) fail("failed-precondition", "Gift must be ready for TEST delivery.");
        // This private completion event certifies Gift completion effects; it is not physical Rider/PIN proof.
        const after = {...before, status: "delivered", giftStatus: "delivered", deliveredAt: before.deliveredAt || Timestamp.now()};
        await ref.set(after); await effects(db, fid, before, after);
        const deliveryRef = db.collection("deliveryRequests").doc(fid);
        const deliveryBefore = {status: "in_transit", serviceType: "GIFTS", giftRequestId: fid, senderId: ids.sender.uid, riderId: ids.rider.uid, isSyntheticQa: true, realDispatch: false, suppressExternalSideEffects: true, excludeFromSettlement: true, excludeFromPayout: true};
        const deliveryAfter = {...deliveryBefore, status: "completed", completedAt: after.deliveredAt};
        await deliveryRef.set(deliveryAfter);
        await story.handleGiftDeliveryCompleted({before: {data: () => deliveryBefore}, after: {data: () => deliveryAfter, ref: deliveryRef}}, {params: {deliveryId: fid}}, {db, source: "cloud_run"}); await drain(db);
        return {status: "delivered", storyUnlocked: (await ref.get()).data().giftStoryUnlocked === true};
      }
      if (data.action === "story") return await story.getSenderGiftStoryHandler({giftRequestId: fid}, context, {injectedDb: db});
      if (data.action === "read") {
        const gift = (await db.collection("giftRequests").doc(fid).get()).data();
        const emails = await db.collection("emailQueue").get(); const notifications = await db.collection("notifications").get();
        return {fixtureId: fid, status: gift?.status || "checkout_pending", paymentStatus: gift?.paymentStatus || "unpaid", emailCount: emails.size, emailStates: emails.docs.map((d) => ({id: d.id, status: d.data().status})), notificationCount: notifications.size, storyUnlocked: gift?.giftStoryUnlocked === true, externalEmailCalls: 0, pushCalls: 0};
      }
      if (data.action === "cleanup") {
        own(role, "admin");
        const gift = (await db.collection("giftRequests").doc(fid).get()).data() || (await db.collection("giftPaymentDrafts").doc(fid).get()).data() || {};
        if (gift.stripePaymentIntentId) {
          const intent = await provider.paymentIntents.retrieve(gift.stripePaymentIntentId);
          if (!["succeeded", "canceled"].includes(intent.status)) await stripe.paymentIntents.cancel(intent.id, {}, {idempotencyKey: `qa_cancel_${fid}`});
        }
        const customerId = gift.stripeCustomerId || (await db.collection("users").doc(ids.sender.uid).get()).data()?.stripeCustomerId;
        if (customerId) {
          const customer = await stripe.customers.retrieve(customerId);
          if (customer.id !== customerId) fail("failed-precondition", "Provider customer mismatch.");
          if (customer.deleted !== true) {
          await provider.customers.retrieve(customerId);
          const page = await stripe.paymentIntents.list({customer: customerId, limit: 100});
          if (page.has_more) fail("failed-precondition", "Provider reconciliation required before cleanup.");
          for (const intent of page.data) {
            if (intent.livemode !== false || intent.metadata?.qaFixtureId !== fid) fail("failed-precondition", "Foreign provider object blocks cleanup.");
            if (!["succeeded", "canceled"].includes(intent.status)) await stripe.paymentIntents.cancel(intent.id, {}, {idempotencyKey: `qa_cleanup_${intent.id}`});
          }
          await stripe.customers.del(customerId);
          }
        }
        await raw.recursiveDelete(root);
        await raw.runTransaction(async (tx) => {
const lock = raw.collection("qaGiftJourneyLocks").doc(ids.admin.uid); const current = await tx.get(lock); if (current.data()?.fixtureId === fid) tx.delete(lock);
});
        return {cleaned: true, rootExists: (await root.get()).exists, remainingSubcollections: (await root.listCollections()).length, providerAuditRetained: true};
      }
      fail("invalid-argument", "Unsupported Gift QA action.");
    } finally {
      await raw.runTransaction(async (tx) => {
const current = await tx.get(root); if (current.exists && current.data().lease === lease) tx.update(root, {lease: null, leaseUntil: Timestamp.fromMillis(0)});
});
    }
  }
  return {handle};
}
module.exports = {factory, testProvider, scopedDb};
