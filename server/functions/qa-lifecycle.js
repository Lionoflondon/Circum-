/* eslint-disable max-len, require-jsdoc */
"use strict";
const crypto = require("node:crypto");
const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue, Timestamp} = require("firebase-admin/firestore");
const rating = require("./ratings-tipping-core");
const tracking = require("./sender-tracking-state-core");
const lifecycle = require("./delivery-tracking")._private;
const evidence = require("./delivery-evidence")._private;
const payout = require("./rider-payout-allocation");
const refunds = require("./tip-refunds");
const tipAuthority = require("./ratings-tipping")._test;
const ROOT = "qaLifecycleFixtures";
const COLLECTIONS = new Set(["deliveryRequests", "deliveryEvidence", "riderProfiles", "riders", "driverRatings", "ratingPrivateFeedback", "publishedDriverRatings", "driverPerformanceMetrics", "deliveryTips", "riderEarnings", "riderWalletTransactions", "riderEarningTransactions", "walletTransactions", "riderPayoutAllocations", "payoutRequests", "tipRecoveries", "supportCases", "offers", "chats", "audit", "qaProviderObjects"]);
const id = (value) => typeof value === "string" && /^[A-Za-z0-9_-]{1,128}$/.test(value);
const fail = (message, code = "failed-precondition") => {
 throw new functions.https.HttpsError(code, message);
};
const hash = (value) => crypto.createHash("sha256").update(value).digest("hex");
function config(env = process.env) {
  let lists;
  try {
 lists = JSON.parse(env.QA_LIFECYCLE_ALLOWLIST || "{}");
} catch (_) {
 fail("QA configuration is unavailable.");
}
  for (const role of ["operators", "senders", "riders"]) if (!Array.isArray(lists[role]) || !lists[role].length || lists[role].length > 10 || !lists[role].every(id)) fail("QA configuration is unavailable.");
  if (env.QA_LIFECYCLE_ENABLED !== "true" || env.GCLOUD_PROJECT !== "circum-2797c" || env.STRIPE_MODE !== "TEST") fail("QA is disabled in this environment.");
  if (lists.senders.some((uid) => lists.riders.includes(uid))) fail("QA participants must be distinct.");
  return lists;
}
function authorize(context, lists) {
  if (!context.auth || !context.auth.uid || !context.app) fail("Authenticated QA attestation is required.", "unauthenticated");
  const uid = context.auth.uid;
  if (![...lists.operators, ...lists.senders, ...lists.riders].includes(uid)) fail("QA access is not permitted.", "permission-denied");
  return uid;
}
function scopedDatabase(db, fixture, allowClosing = false, rootName = ROOT, extraCollections = []) {
  if (![ROOT, "qaSpecialFlowFixtures"].includes(rootName)) fail("Invalid QA root.");
  const collections = new Set([...COLLECTIONS, ...extraCollections]);
  if (!id(fixture.id) || fixture.isSyntheticQa !== true) fail("Invalid QA scope.");
  const prefix = `${rootName}/${fixture.id}/`;
  const markers = {isSyntheticQa: true, qaFixtureId: fixture.id, qaCreatedBy: fixture.qaCreatedBy, qaCreatedAt: fixture.qaCreatedAt};
  function guard(ref) {
    const path = ref.path;
    if (typeof path !== "string" || !path.startsWith(prefix)) fail("Cross-fixture access denied.", "permission-denied");
    const parts = path.slice(prefix.length).split("/");
    if (parts.length !== 2 || !collections.has(parts[0]) || !id(parts[1])) fail("Invalid QA record path.", "permission-denied");
  }
  return {
    collection(name) {
 if (!collections.has(name)) fail("Invalid QA collection."); return db.collection(prefix + name);
},
    doc(path) {
 const ref = db.doc(path.startsWith(prefix) ? path : prefix + path); guard(ref); return ref;
},
    runTransaction(callback) {
      return db.runTransaction(async (tx) => {
        const root = await tx.get(db.collection(rootName).doc(fixture.id));
        if (!root.exists || root.data().isSyntheticQa !== true || (!allowClosing && (root.data().closing || root.data().archived || root.data().expiresAt.toMillis() <= Date.now()))) fail("QA scope has closed.");
        return callback({
        get: (ref) => {
 if (ref.path) guard(ref); return tx.get(ref);
},
        getAll: (...refs) => {
 refs.forEach(guard); return tx.getAll(...refs);
},
        set: (ref, data, options) => {
 guard(ref); return options ? tx.set(ref, {...data, ...markers}, options) : tx.set(ref, {...data, ...markers});
},
        create: (ref, data) => {
 guard(ref); return tx.create(ref, {...data, ...markers});
},
        update: (ref, data) => {
 guard(ref); return tx.update(ref, {...data, ...markers});
},
        delete: (ref) => {
 guard(ref); if (!["offers", "deliveryEvidence"].includes(ref.parent.id)) fail("QA audit and finance records are immutable."); return tx.delete(ref);
},
      });
      });
    },
  };
}
function assertFixture(fixture, lists, uid, now = Date.now(), allowExpired = false) {
  if (!fixture || fixture.isSyntheticQa !== true || !lists.operators.includes(fixture.qaCreatedBy) || !lists.senders.includes(fixture.senderId) || !lists.riders.includes(fixture.riderId) || fixture.senderId === fixture.riderId) fail("QA fixture is unavailable.");
  if (![fixture.senderId, fixture.riderId, fixture.qaCreatedBy].includes(uid)) fail("Cross-fixture actor denied.", "permission-denied");
  if (!allowExpired && (fixture.closing || fixture.archived || fixture.expiresAt.toMillis() <= now)) fail("QA fixture has expired.");
}
function requireActor(fixture, uid, role) {
  if (uid !== fixture[role]) fail("Wrong QA actor.", "permission-denied");
}
function assertProvider(object, fixture, deliveryId, amount) {
  if (!object || object.livemode !== false || object.status !== "succeeded" || object.amount !== amount || object.amount_received !== amount || object.currency !== "gbp" || object.metadata.qaFixtureId !== fixture.id || object.metadata.deliveryId !== deliveryId) fail("A matching successful TEST payment is required.");
}
function factory({db, env = process.env}) {
  async function handle(data, context) {
    const lists = config(env); const uid = authorize(context, lists);
    if (!data || typeof data !== "object") fail("QA action is required.");
    const action = data.action;
    if (action === "create") {
      if (!lists.operators.includes(uid) || !lists.senders.includes(data.senderId) || !lists.riders.includes(data.riderId) || !id(data.requestId)) fail("QA provisioning is not permitted.", "permission-denied");
      const fixtureId = hash(`${uid}:${data.requestId}`); const ref = db.collection(ROOT).doc(fixtureId);
      await db.runTransaction(async (tx) => {
        const lockRef = db.collection("qaLifecycleOperators").doc(uid);
        const [existing, lock] = await tx.getAll(ref, lockRef);
        if (existing.exists) {
          const old = existing.data();
          if (old.senderId !== data.senderId || old.riderId !== data.riderId) fail("Fixture request identity changed.");
          return;
        }
        if (lock.exists && lock.data().activeFixtureId) fail("Clean up the existing QA fixture first.");
        tx.set(lockRef, {activeFixtureId: fixtureId, isSyntheticQa: true, qaFixtureId: fixtureId, qaCreatedBy: uid, qaCreatedAt: FieldValue.serverTimestamp()});
        const now = Timestamp.now();
        tx.create(ref, {id: fixtureId, isSyntheticQa: true, qaFixtureId: fixtureId, qaCreatedBy: uid, qaCreatedAt: now, senderId: data.senderId, riderId: data.riderId, expiresAt: Timestamp.fromMillis(now.toMillis() + 3600000), cleanupDueAt: Timestamp.fromMillis(now.toMillis() + 3600000), archived: false, sourceVersion: 1});
      });
      return {fixtureId};
    }
    if (!id(data.fixtureId)) fail("Invalid fixture identity.");
    const root = db.collection(ROOT).doc(data.fixtureId); const snapshot = await root.get(); const fixture = snapshot.data();
    assertFixture(fixture, lists, uid, Date.now(), ["cleanup", "read"].includes(action));
    const qa = scopedDatabase(db, fixture);
    const stripe = simulatedProvider(qa, fixture);
    if (action === "read") {
      const result = {};
      const names = uid === fixture.riderId ? ["publishedDriverRatings", "driverPerformanceMetrics", "riderEarnings", "riderWalletTransactions", "riderPayoutAllocations"] : ["deliveryRequests", "driverRatings", "publishedDriverRatings", "driverPerformanceMetrics", "deliveryTips", "walletTransactions", "riderPayoutAllocations", "supportCases", "audit"];
      for (const name of names) {
result[name] = (await qa.collection(name).limit(100).get()).docs.map((d) => {
        const row = {id: d.id, ...d.data()};
        if (uid === fixture.riderId) {
 delete row.qaCreatedBy; delete row.senderId;
}
        return row;
      });
}
      return {isSyntheticQa: true, archived: fixture.archived, records: result};
    }
    if (action === "cleanup") {
      requireActor(fixture, uid, "qaCreatedBy");
      return cleanup(fixture);
    }
    if (!["a", "b", "c"].includes(data.delivery)) fail("Only three bounded QA deliveries are allowed.");
    const deliveryId = `qa_${fixture.id}_${data.delivery}`; const ref = qa.collection("deliveryRequests").doc(deliveryId);
    if (action === "book") {
      requireActor(fixture, uid, "senderId");
      await qa.runTransaction(async (tx) => {
        const old = await tx.get(ref); if (old.exists) return;
        tx.create(ref, {deliveryId, senderId: fixture.senderId, status: "booked", currency: "GBP", amountPence: 2000, riderEligibleFare: 20, riderPayoutCalculationVersion: "65_35_v1", paymentStatus: "unpaid", serviceType: "standard", verificationRequired: true, deliveryPhotoRequired: true, collectionPin: "2468", deliveryPin: "8642", createdAt: FieldValue.serverTimestamp()});
        tx.set(qa.collection("riderProfiles").doc(fixture.riderId), {approvalStatus: "approved", verificationStatus: "verified", approvalScope: "isolated_qa_only", dispatchEligible: false}, {merge: true});
        tx.create(qa.collection("audit").doc(`book_${data.delivery}`), {action: "book", actorId: uid, deliveryId, at: FieldValue.serverTimestamp()});
      });
      return {deliveryId};
    }
    if (action === "pay") {
      requireActor(fixture, uid, "senderId"); const old = await ref.get(); if (!old.exists || old.data().status !== "booked" && old.data().status !== "requested") fail("Book before payment.");
      await qa.runTransaction(async (tx) => {
        const fresh = await tx.get(ref);
        if (!fresh.exists || fresh.data().closing || !["booked", "requested"].includes(fresh.data().status)) fail("QA payment is closing.");
        tx.set(ref, {paymentReserved: true}, {merge: true});
      });
      const intent = await stripe.paymentIntents.create({amount: 2000, currency: "gbp", payment_method: "pm_card_visa", payment_method_types: ["card"], confirm: true, metadata: {isSyntheticQa: "true", qaFixtureId: fixture.id, deliveryId}}, {idempotencyKey: `qa_base_${deliveryId}`});
      const verified = await stripe.paymentIntents.retrieve(intent.id); assertProvider(verified, fixture, deliveryId, 2000);
      await qa.runTransaction(async (tx) => {
        const fresh = await tx.get(ref); if (fresh.data().paymentStatus === "paid") return; if (fresh.data().closing || !["booked", "requested"].includes(fresh.data().status)) fail("Payment transition changed.");
        tx.set(ref, {status: "requested", paymentStatus: "paid", stripePaymentIntentId: intent.id}, {merge: true});
        tx.set(qa.collection("offers").doc(deliveryId), {deliveryId, riderId: fixture.riderId, senderId: fixture.senderId, status: "offered", realDispatch: false});
        tx.create(qa.collection("audit").doc(`pay_${data.delivery}`), {action: "provider_payment_confirmed", providerId: intent.id, deliveryId, at: FieldValue.serverTimestamp()});
      }); return {paid: true};
    }
    if (action === "capture_tip") {
      requireActor(fixture, uid, "senderId"); const d = (await ref.get()).data(); if (!d || d.closing || d.paymentStatus !== "paid" || !d.riderId || d.status === "cancelled") fail("A paid assigned QA delivery is required.");
      await qa.runTransaction(async (tx) => {
        const fresh = await tx.get(ref);
        if (!fresh.exists || fresh.data().closing || fresh.data().status === "cancelled") fail("QA tip is closing.");
        tx.set(ref, {tipReserved: true}, {merge: true});
      });
      const input = rating.normalizeTipInput({amountPence: 300, paymentMethod: "card", currency: "GBP"});
      const metadata = {isSyntheticQa: "true", qaFixtureId: fixture.id, paymentType: "delivery_tip", tipId: deliveryId, deliveryId, senderId: fixture.senderId, riderId: fixture.riderId};
      const intent = await stripe.paymentIntents.create({amount: input.amountPence, currency: "gbp", payment_method: "pm_card_visa", payment_method_types: ["card"], confirm: true, metadata}, {idempotencyKey: `qa_tip_${deliveryId}`});
      const verified = await stripe.paymentIntents.retrieve(intent.id); assertProvider(verified, fixture, deliveryId, input.amountPence);
      const tip = {tipId: deliveryId, deliveryId, senderId: fixture.senderId, riderId: fixture.riderId, amountPence: 300, amount: 3, currency: "GBP", stripePaymentIntentId: intent.id, paymentMethod: "card", status: "captured"};
      tipAuthority.assertTipIntent(tip, verified, "test"); tipAuthority.assertTipParties(tip, d);
      await qa.runTransaction(async (tx) => {
 const fresh = await tx.get(ref); const existing = await tx.get(qa.collection("deliveryTips").doc(deliveryId)); if (fresh.data().closing || fresh.data().status === "cancelled") fail("Delivery was cancelled."); if (!existing.exists) tx.create(qa.collection("deliveryTips").doc(deliveryId), {...tip, createdAt: FieldValue.serverTimestamp()});
});
      await earnTip(qa, fixture, deliveryId);
      return {status: (await qa.collection("deliveryTips").doc(deliveryId).get()).data().status, amountPence: 300, providerSimulation: true};
    }
    if (action === "cancel") {
 requireActor(fixture, uid, "senderId"); return cancel(qa, fixture, deliveryId, "cancel");
}
    if (action === "refund_delivery") {
      requireActor(fixture, uid, "qaCreatedBy"); const d = (await ref.get()).data(); if (!d || d.status !== "completed") fail("Completed QA delivery required.");
      const refund = await refundProvider(qa, fixture, deliveryId, d.stripePaymentIntentId, 2000, "delivery_fee");
      await qa.runTransaction(async (tx) => {
 const auditRef = qa.collection("audit").doc(`fee_refund_${data.delivery}`); if ((await tx.get(auditRef)).exists) return; tx.create(auditRef, {providerId: refund.id, amountPence: 2000, tipPreserved: true, action: "delivery_fee_refund"});
});
      return {tipPreserved: true};
    }
    if (action === "refund_tip") {
      requireActor(fixture, uid, "qaCreatedBy"); if (data.reason !== "duplicate_charge") fail("Only the approved QA duplicate-charge reason is supported.");
      return reverse(qa, fixture, deliveryId, "duplicate_charge");
    }
    if (action === "allocate") {
      requireActor(fixture, uid, "qaCreatedBy"); const requestId = `qa_allocation_${data.delivery}`; const amount = data.amountPence;
      if (!Number.isSafeInteger(amount) || amount < 1 || amount > 4200) fail("Invalid QA allocation amount.");
      return qa.runTransaction(async (tx) => {
        const requestRef = qa.collection("payoutRequests").doc(requestId);
        const [previous, earnings] = await tx.getAll(requestRef, qa.collection("riderEarnings").doc(fixture.riderId));
        if (previous.exists) {
          if (payout.minor(previous.data().amount) !== amount) fail("Allocation amount changed.");
          return {idempotent: true, realTransfer: false};
        }
        const before = payout.minor((earnings.data() || {}).availableBalance || 0);
        if (before < amount) fail("Insufficient QA earnings.");
        const plan = await payout.readAllocationPlan(tx, qa, fixture.riderId, requestId, amount);
        if (plan.recoveries.length) fail("QA does not allocate real recoveries.");
        payout.reserveAllocations(tx, qa, fixture.riderId, requestId, plan.allocations);
        tx.set(qa.collection("payoutRequests").doc(requestId), {riderId: fixture.riderId, amount: amount / 100, status: "reserved", allocationVersion: 1, fundsReserved: true, reservationVersion: 1, realTransfer: false});
        tx.set(qa.collection("riderEarnings").doc(fixture.riderId), {availableBalance: (before - amount) / 100, availableEarnings: (before - amount) / 100, pendingWithdrawal: Number((earnings.data() || {}).pendingWithdrawal || 0) + amount / 100}, {merge: true});
        payout.writePayoutLedger(tx, qa, {requestId, version: 1, riderId: fixture.riderId, amountPence: amount, phase: "reserved", balanceBeforePence: before, balanceAfterPence: before - amount});
        return {allocations: plan.allocations, realTransfer: false};
      });
    }
    if (action === "rate") {
      requireActor(fixture, uid, "senderId");
      if ((data.senderId && data.senderId !== uid) || (data.riderId && data.riderId !== fixture.riderId)) fail("Rating association mismatch.", "permission-denied");
      const input = rating.normalizeRatingInput(data);
      return qa.runTransaction(async (tx) => {
        const [d, previous, metric] = await tx.getAll(ref, qa.collection("driverRatings").doc(deliveryId), qa.collection("driverPerformanceMetrics").doc(fixture.riderId));
        const parties = rating.assertCompletedDelivery(d.data(), uid); if (parties.riderId !== fixture.riderId || d.data().paymentStatus !== "paid") fail("Rating identity or payment mismatch.");
        if (previous.exists) {
 if (previous.data().requestHash !== hash(JSON.stringify(input))) fail("Rating already exists."); return {idempotent: true};
}
        const projection = {stars: input.stars, starRating: input.stars, feedbackText: rating.publicRatingFeedback(input.feedback), feedbackTags: input.feedbackTags, categories: rating.ratingCategories(d.data()), riderId: fixture.riderId, driverId: fixture.riderId, date: FieldValue.serverTimestamp()};
        tx.create(qa.collection("driverRatings").doc(deliveryId), {...projection, senderId: uid, deliveryId, requestHash: hash(JSON.stringify(input))});
        tx.create(qa.collection("publishedDriverRatings").doc(deliveryId), projection);
        tx.set(qa.collection("driverPerformanceMetrics").doc(fixture.riderId), rating.nextRatingStats(metric.data(), input.stars), {merge: true});
        if (input.feedbackTags.some((t) => ["Safety concern", "Damaged item"].includes(t))) tx.create(qa.collection("supportCases").doc(deliveryId), {deliveryId, senderId: uid, riderId: fixture.riderId, reason: "serious_feedback", status: "qa_review_only", noExternalNotification: true});
        return {idempotent: false};
      });
    }
    if (action === "accept" || tracking.RIDER_ACTION_TO_STATUS[action]) {
      requireActor(fixture, uid, "riderId");
      await qa.runTransaction(async (tx) => {
        const [snap, profile, offer, balance] = await tx.getAll(ref, qa.collection("riderProfiles").doc(uid), qa.collection("offers").doc(deliveryId), qa.collection("riderEarnings").doc(uid));
        const d = snap.data(); if (!d || d.closing || d.paymentStatus !== "paid" || (profile.data() || {}).approvalScope !== "isolated_qa_only" || profile.data().approvalStatus !== "approved" || !offer.exists || offer.data().riderId !== uid) fail("QA delivery authority is incomplete.");
        const next = action === "accept" ? "accepted" : tracking.RIDER_ACTION_TO_STATUS[action];
        if (d.status === next || (d.status === "completed" && next === "delivered")) return;
        if (!tracking.canTransitionDeliveryStatus(d.status, next)) fail("Invalid lifecycle transition.");
        if (action !== "accept") lifecycle.assertRiderOwnsDelivery(d, uid);
        const patch = {status: next, deliveryState: next, riderId: uid, driverId: uid};
        if (["verify_collection_pin", "verify_receiver_pin"].includes(action)) {
          const pickup = action === "verify_collection_pin"; if (data.pin !== (pickup ? d.collectionPin : d.deliveryPin)) fail("QA PIN is incorrect.");
          const stage = pickup ? "pickup" : "dropoff";
          const path = `deliveryEvidence/${deliveryId}/${uid}/${stage}.jpg`;
          const record = {deliveryId, riderId: uid, stage, verified: true, storagePath: path, contentType: "image/jpeg", generation: "1"};
          const metadata = {metadata: {deliveryId, riderId: uid, stage}, contentType: "image/jpeg", size: 4, generation: "1"};
          // Validated QA-only media adapter: no real storage file or customer evidence is forged.
          await evidence.validateRecord(record, {deliveryId, riderId: uid, requiredStage: stage, bucket: {file: (requested) => {
 if (requested !== path) fail("Wrong QA evidence path."); return {getMetadata: async () => [metadata]};
}}});
          const decision = lifecycle.evidenceRequirements(d, action, {evidenceId: stage, conditionConfirmed: true, riderDeclarationAccepted: true, recipientConfirmed: true}); if (!decision.valid) fail(decision.reason);
          tx.set(qa.collection("deliveryEvidence").doc(`${data.delivery}_${stage}`), record);
          if (pickup) patch.collectionPinVerified = true; else patch.deliveryPinVerified = true;
        }
        if (action === "confirm_collected" && !d.collectionPinVerified) fail("Collection verification required.");
        if (next === "delivered") {
          if (!d.collectionPinVerified) fail("Collection verification required.");
          patch.status = "completed"; patch.deliveryState = "completed"; patch.completedAt = FieldValue.serverTimestamp();
          const amount = lifecycle.settlementValues(d).deliveryAmount; if (amount !== 13) fail("Unexpected canonical QA base settlement.");
          const earning = {transactionId: `base_${deliveryId}`, type: "delivery_earning", riderId: uid, senderId: fixture.senderId, deliveryId, amount, amountPence: 1300, currency: "GBP", createdAt: FieldValue.serverTimestamp()};
          tx.create(qa.collection("riderEarningTransactions").doc(earning.transactionId), earning);
          const available = payout.minor((balance.data() || {}).availableBalance || 0) + 1300;
          tx.set(qa.collection("riderEarnings").doc(uid), {availableBalance: available / 100, availableEarnings: available / 100}, {merge: true});
        }
        tx.set(ref, patch, {merge: true});
        if (action === "accept") tx.set(qa.collection("chats").doc(deliveryId), {members: [fixture.senderId, uid], deliveryId, noExternalNotification: true});
        tx.create(qa.collection("audit").doc(`${data.delivery}_${action}`), {action, actorId: uid, deliveryId, next: patch.status, at: FieldValue.serverTimestamp()});
      });
      await earnTip(qa, fixture, deliveryId); return {advanced: true};
    }
    fail("Unsupported QA action.", "invalid-argument");
  }
  async function earnTip(qa, fixture, deliveryId) {
    return qa.runTransaction(async (tx) => {
      const [delivery, tip, prior, earnings] = await tx.getAll(qa.collection("deliveryRequests").doc(deliveryId), qa.collection("deliveryTips").doc(deliveryId), qa.collection("walletTransactions").doc(`delivery_tip_${deliveryId}`), qa.collection("riderEarnings").doc(fixture.riderId));
      if (delivery.data().status !== "completed" || !tip.exists || prior.exists || tip.data().status !== "captured") return;
      rating.assertCompletedDelivery(delivery.data(), fixture.senderId); tipAuthority.assertTipParties(tip.data(), delivery.data());
      const row = {...tip.data(), type: "tip", status: "completed", transactionId: `delivery_tip_${deliveryId}`, createdAt: FieldValue.serverTimestamp()};
      tx.create(qa.collection("walletTransactions").doc(row.transactionId), row); tx.create(qa.collection("riderWalletTransactions").doc(row.transactionId), row);
      const stats = rating.nextTipStats(earnings.data(), 3); tx.set(qa.collection("riderEarnings").doc(fixture.riderId), {...stats, availableBalance: Number((earnings.data() || {}).availableBalance || 0) + 3, availableEarnings: Number((earnings.data() || {}).availableEarnings || 0) + 3}, {merge: true});
      tx.set(tip.ref, {status: "succeeded"}, {merge: true});
    });
  }
  async function refundProvider(qa, fixture, deliveryId, intentId, amount, purpose) {
    const stripe = simulatedProvider(qa, fixture);
    const intent = await stripe.paymentIntents.retrieve(intentId); assertProvider(intent, fixture, deliveryId, amount);
    const result = await stripe.refunds.create({payment_intent: intentId, amount, metadata: {isSyntheticQa: "true", qaFixtureId: fixture.id, purpose}}, {idempotencyKey: `qa_refund_${intentId}`});
    if (result.status !== "succeeded" || result.amount !== amount || result.payment_intent !== intentId) fail("TEST refund is not confirmed.");
    return result;
  }
  async function reverse(qa, fixture, deliveryId, reason) {
    const tip = await qa.collection("deliveryTips").doc(deliveryId).get(); if (!tip.exists) return {noTip: true};
    const result = await refundProvider(qa, fixture, deliveryId, tip.data().stripePaymentIntentId, tip.data().amountPence, reason);
    return refunds.reverseTipEarning({db: qa, tipId: deliveryId, amountPence: tip.data().amountPence, providerReference: result.id, reason});
  }
  async function cancel(qa, fixture, deliveryId, reason) {
    const ref = qa.collection("deliveryRequests").doc(deliveryId);
    await qa.runTransaction(async (tx) => {
      const snap = await tx.get(ref); const row = snap.data();
      if (!row || row.status === "completed") fail("Completed delivery cannot be pre-completion cancelled.");
      if (reason !== "cleanup" && !["booked", "cancelled"].includes(row.status) && !tracking.canTransitionDeliveryStatus(row.status, "cancelled")) fail("QA cancellation unavailable at this stage.");
      tx.set(ref, {closing: true}, {merge: true});
      return row;
    });
    // Reconcile all persisted simulation captures, including interrupted capture bookkeeping.
    const provider = simulatedProvider(qa, fixture);
    for (const kind of ["base", "tip"]) {
      const intentId = `qa_pi_${hash(`qa_${kind}_${deliveryId}`)}`;
      const object = await qa.collection("qaProviderObjects").doc(intentId).get();
      if (!object.exists) continue;
      const intent = await provider.paymentIntents.retrieve(intentId);
      if (kind === "base") await refundProvider(qa, fixture, deliveryId, intentId, 2000, "cancel");
      else {
await qa.runTransaction(async (tx) => {
        const tipRef = qa.collection("deliveryTips").doc(deliveryId); const tip = await tx.get(tipRef);
        if (!tip.exists) tx.create(tipRef, {tipId: deliveryId, deliveryId, senderId: fixture.senderId, riderId: fixture.riderId, amountPence: intent.amount, amount: intent.amount / 100, currency: "GBP", stripePaymentIntentId: intentId, paymentMethod: "card", status: "captured"});
      });
}
    }
    await reverse(qa, fixture, deliveryId, "not_completed");
    await qa.runTransaction(async (tx) => {
 const current = await tx.get(ref); if (current.data().status === "completed") fail("Completion won cancellation race."); tx.set(ref, {status: "cancelled", deliveryState: "cancelled", cancellationReason: reason}, {merge: true});
});
    return {cancelled: true};
  }
  async function cleanup(fixture) {
    const qa = scopedDatabase(db, fixture, true);
    const root = db.collection(ROOT).doc(fixture.id);
    await db.runTransaction(async (tx) => {
 const row = await tx.get(root); if (!row.exists || row.data().isSyntheticQa !== true) fail("Invalid cleanup scope."); tx.update(root, {closing: true});
});
    for (const doc of (await qa.collection("deliveryRequests").limit(3).get()).docs) if (!["completed", "cancelled"].includes(doc.data().status)) await cancel(qa, fixture, doc.id, "cleanup");
    for (const name of ["offers", "deliveryEvidence"]) {
      const docs = await qa.collection(name).limit(50).get();
      await qa.runTransaction(async (tx) => {
 for (const doc of docs.docs) tx.delete(doc.ref);
});
    }
    await db.runTransaction(async (tx) => {
      const lock = db.collection("qaLifecycleOperators").doc(fixture.qaCreatedBy);
      const [current, owner] = await tx.getAll(root, lock);
      if (!current.data().archived) tx.update(root, {archived: true, cleanupState: "complete", cleanupDueAt: FieldValue.delete(), archivedAt: FieldValue.serverTimestamp()});
      if (owner.exists && owner.data().activeFixtureId === fixture.id) tx.update(lock, {activeFixtureId: null});
    });
    return {archived: true};
  }
  async function expire() {
    config(env);
    const expired = await db.collection(ROOT).where("cleanupDueAt", "<=", Timestamp.now()).limit(20).get();
    for (const doc of expired.docs) await cleanup(doc.data());
    return {archived: expired.size};
  }
  return {handle, expire};
}
// No Stripe SDK calls: these immutable provider-shaped objects are explicitly simulated.
// The shared financial validators still check identity, currency, amount and mode.
function simulatedProvider(qa, fixture) {
  const objects = qa.collection("qaProviderObjects");
  return {
    paymentIntents: {
      create: async (input, options) => qa.runTransaction(async (tx) => {
        const delivery = await tx.get(qa.collection("deliveryRequests").doc(input.metadata.deliveryId));
        if (!delivery.exists || delivery.data().closing || delivery.data().status === "cancelled") fail("Capture is closing.");
        const key = `qa_pi_${hash(options.idempotencyKey)}`; const ref = objects.doc(key); const old = await tx.get(ref);
        const row = {id: key, providerSimulation: true, livemode: false, status: "succeeded", amount: input.amount, amount_received: input.amount, currency: input.currency, metadata: input.metadata};
        if (old.exists) {
 if (old.data().amount !== input.amount) fail("Simulation identity changed."); return old.data();
}
        tx.create(ref, row); return row;
      }),
      retrieve: async (key) => {
 if (!/^qa_pi_[a-f0-9]{64}$/.test(key)) fail("Only QA simulation references allowed."); const doc = await objects.doc(key).get(); if (!doc.exists || !doc.data().providerSimulation) fail("QA capture missing."); return doc.data();
},
    },
    refunds: {create: async (input, options) => qa.runTransaction(async (tx) => {
      const ref = objects.doc(`qa_re_${hash(options.idempotencyKey)}`); const [old, intent] = await tx.getAll(ref, objects.doc(input.payment_intent));
      if (!intent.exists || intent.data().metadata.qaFixtureId !== fixture.id || input.amount !== intent.data().amount) fail("QA refund mismatch.");
      if (old.exists) return old.data();
      const row = {id: ref.id, providerSimulation: true, payment_intent: input.payment_intent, amount: input.amount, status: "succeeded"}; tx.create(ref, row); return row;
    })},
  };
}
exports.callable = () => functions.runWith({timeoutSeconds: 120, enforceAppCheck: true}).https.onCall((data, context) => factory({db: getFirestore()}).handle(data, context));
exports.scheduled = () => functions.pubsub.schedule("every 15 minutes").onRun(() => factory({db: getFirestore()}).expire());
exports._test = {factory, config, authorize, scopedDatabase, assertFixture, assertProvider};
