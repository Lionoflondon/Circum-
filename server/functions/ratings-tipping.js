/* eslint-disable max-len, require-jsdoc */
"use strict";

const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue, FieldPath} = require("firebase-admin/firestore");
const core = require("./ratings-tipping-core");
const rothLedger = require("./roth-ledger");
const communication = require("./communication-engine");

const text = (value) => `${value || ""}`.trim();
const money = (value) => Math.round(Number(value || 0) * 100) / 100;
const callableRuntime = functions.runWith({enforceAppCheck: true});
const ACTIVE_TIP_STATES = new Set(["requires_payment_method", "requires_confirmation", "requires_action", "processing"]);

function requireAuth(context) {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Sign in to continue.");
  return {uid: context.auth.uid, email: context.auth.token.email || ""};
}

function isRatingAdmin(context) {
  const token = context.auth && context.auth.token || {};
  const role = text(token.role || token.adminRole).toLowerCase();
  const roles = Array.isArray(token.roles) ? token.roles.map((value) => text(value).toLowerCase()) : [];
  return token.admin === true || token.super_admin === true ||
    [role, ...roles].some((value) => ["super_admin", "operations_admin", "support_agent", "driver_manager"].includes(value));
}

function isFinanceAdmin(context) {
  const token = context.auth && context.auth.token || {};
  const role = text(token.role || token.adminRole).toLowerCase();
  const roles = Array.isArray(token.roles) ? token.roles.map((value) => text(value).toLowerCase()) : [];
  return token.super_admin === true ||
    [role, ...roles].some((value) => ["super_admin", "finance_admin", "finance_manager"].includes(value));
}

function asHttpsError(error) {
  if (error instanceof functions.https.HttpsError) return error;
  const code = `${error && error.message || error}`;
  const map = {
    "delivery-not-found": ["not-found", "Delivery not found."],
    "delivery-not-completed": ["failed-precondition", "This delivery is not complete yet."],
    "delivery-not-owned": ["permission-denied", "This delivery does not belong to this account."],
    "delivery-rider-missing": ["failed-precondition", "This delivery has no confirmed Rider."],
    "rating-window-closed": ["failed-precondition", "The appreciation window has closed."],
    "invalid-rating": ["invalid-argument", "Choose a whole-star rating from one to five."],
    "feedback-too-long": ["invalid-argument", "Feedback is limited to 500 characters."],
    "invalid-feedback-tag": ["invalid-argument", "One or more feedback choices are unavailable."],
    "invalid-tip-amount": ["invalid-argument", "Choose a tip between £1 and £100."],
    "invalid-payment-method": ["invalid-argument", "Choose an available payment method."],
  };
  const mapped = map[code] || ["internal", "We could not process your appreciation. Please try again."];
  return new functions.https.HttpsError(mapped[0], mapped[1]);
}

async function resolveDelivery(db, deliveryId) {
  const direct = await db.collection("deliveryRequests").doc(deliveryId).get();
  if (direct.exists) return {id: direct.id, ref: direct.ref, data: direct.data() || {}};
  const query = await db.collection("deliveryRequests").where("requestId", "==", deliveryId).limit(1).get();
  if (query.empty) return null;
  const doc = query.docs[0];
  return {id: doc.id, ref: doc.ref, data: doc.data() || {}};
}

function ratingTitle(stars) {
  return ["", "Poor Experience", "Needs Improvement", "Good Delivery", "Great Delivery", "Outstanding Delivery"][stars];
}

async function notifyOnce({eventId, recipientId, recipientRole, type, title, body, deliveryId, data = {}}) {
  const db = getFirestore();
  const ref = db.collection("notificationEvents").doc(eventId);
  let created = false;
  await db.runTransaction(async (transaction) => {
    const existing = await transaction.get(ref);
    if (existing.exists) return;
    created = true;
    transaction.create(ref, {
      eventId, recipientId, recipientRole, type, title, body, deliveryId,
      status: "created", data, createdAt: FieldValue.serverTimestamp(),
    });
  });
  if (!created) return;
  const notificationId = await communication.emitNotification({
    recipientId, recipientRole, type, title, body,
    data: {...data, deliveryId, bookingId: deliveryId},
  });
  await ref.set({notificationId, status: "sent", sentAt: FieldValue.serverTimestamp()}, {merge: true});
}

async function submitRating(data, context) {
  const sender = requireAuth(context);
  const deliveryId = text(data && (data.deliveryId || data.requestId));
  if (!deliveryId) throw new functions.https.HttpsError("invalid-argument", "Delivery is required.");
  try {
    const input = core.normalizeRatingInput(data || {});
    const db = getFirestore();
    const delivery = await resolveDelivery(db, deliveryId);
    const parties = core.assertCompletedDelivery(delivery && delivery.data, sender.uid);
    const ratingRef = db.collection("driverRatings").doc(delivery.id);
    const profileRef = db.collection("riderProfiles").doc(parties.riderId);
    const riderRef = db.collection("riders").doc(parties.riderId);
    const metricRef = db.collection("driverPerformanceMetrics").doc(parties.riderId);
    let created = false;
    await db.runTransaction(async (transaction) => {
      const [existing, profile, metric] = await Promise.all([
        transaction.get(ratingRef), transaction.get(profileRef), transaction.get(metricRef),
      ]);
      if (existing.exists) throw new functions.https.HttpsError("already-exists", "This delivery has already been rated.");
      created = true;
      const current = {...(profile.data() || {}), ...(metric.data() || {})};
      const stats = core.nextRatingStats(current, input.stars);
      const now = FieldValue.serverTimestamp();
      transaction.create(ratingRef, {
        ratingId: delivery.id,
        deliveryId: delivery.id,
        requestId: text(delivery.data.requestId) || delivery.id,
        customerId: sender.uid,
        senderId: sender.uid,
        driverId: parties.riderId,
        riderId: parties.riderId,
        starRating: input.stars,
        ratingTitle: ratingTitle(input.stars),
        feedbackText: input.feedback,
        feedbackTags: input.feedbackTags,
        reportStatus: "clear",
        hiddenByAdmin: false,
        immutable: true,
        createdAt: now,
      });
      const statsPatch = {...stats, lastRatedAt: now, updatedAt: now};
      transaction.set(profileRef, statsPatch, {merge: true});
      transaction.set(riderRef, statsPatch, {merge: true});
      transaction.set(metricRef, statsPatch, {merge: true});
      transaction.set(delivery.ref, {
        appreciation: {ratingId: ratingRef.id, ratingSubmitted: true, ratedAt: now},
        updatedAt: now,
      }, {merge: true});
    });
    if (created) {
      await Promise.all([
        notifyOnce({
          eventId: `rating_sender_${delivery.id}`, recipientId: sender.uid, recipientRole: "sender",
          type: "delivery_rating_submitted", title: "Thank you", body: "Thanks for rating your rider.", deliveryId: delivery.id,
        }),
        notifyOnce({
          eventId: `rating_rider_${delivery.id}`, recipientId: parties.riderId, recipientRole: "rider",
          type: "delivery_rating_received", title: "\u2605".repeat(input.stars), body: `You received a new ${input.stars}-star rating.`, deliveryId: delivery.id,
          data: {ratingId: ratingRef.id, stars: input.stars},
        }),
      ]);
    }
    return {ok: true, ratingId: ratingRef.id, stars: input.stars, title: ratingTitle(input.stars)};
  } catch (error) {
    throw asHttpsError(error);
  }
}

async function ensureStripeCustomer(stripe, db, sender) {
  const userRef = db.collection("users").doc(sender.uid);
  const senderRef = db.collection("senders").doc(sender.uid);
  const [user, senderProfile] = await Promise.all([userRef.get(), senderRef.get()]);
  const existing = text((user.data() || {}).stripeCustomerId || (senderProfile.data() || {}).stripeCustomerId);
  if (existing) return existing;
  const customer = await stripe.customers.create({email: sender.email || undefined, metadata: {uid: sender.uid, product: "circum_sender"}}, {idempotencyKey: `circum_sender_customer_${sender.uid}`});
  await Promise.all([
    userRef.set({stripeCustomerId: customer.id, updatedAt: FieldValue.serverTimestamp()}, {merge: true}),
    senderRef.set({stripeCustomerId: customer.id, updatedAt: FieldValue.serverTimestamp()}, {merge: true}),
  ]);
  return customer.id;
}

function assertStripeTipIntent(intent, tip, expectedCustomerId) {
  const metadata = intent && intent.metadata || {};
  if (!intent || Number(intent.amount) !== Number(tip.amountPence) ||
      text(intent.currency).toLowerCase() !== "gbp" ||
      text(intent.customer) !== text(expectedCustomerId || tip.stripeCustomerId) ||
      metadata.paymentType !== "delivery_tip" || metadata.tipId !== tip.tipId ||
      metadata.deliveryId !== tip.deliveryId || metadata.senderId !== tip.senderId ||
      metadata.riderId !== tip.riderId) {
    throw new functions.https.HttpsError("permission-denied", "Tip payment details do not match this delivery.");
  }
}

async function finalizeTip(db, tipRef, tip, stripeIntentId = null) {
  const earningsRef = db.collection("riderEarnings").doc(tip.riderId);
  const profileRef = db.collection("riderProfiles").doc(tip.riderId);
  const riderRef = db.collection("riders").doc(tip.riderId);
  const metricRef = db.collection("driverPerformanceMetrics").doc(tip.riderId);
  const ledgerRef = db.collection("walletTransactions").doc(`delivery_tip_${tip.deliveryId}`);
  const compatibilityRef = db.collection("riderWalletTransactions").doc(`delivery_tip_${tip.deliveryId}`);
  let credited = false;
  await db.runTransaction(async (transaction) => {
    const [currentTip, earnings, profile, metric, ledgerSnapshot] = await Promise.all([
      transaction.get(tipRef), transaction.get(earningsRef), transaction.get(profileRef),
      transaction.get(metricRef), transaction.get(ledgerRef),
    ]);
    const current = currentTip.data() || tip;
    if (current.status === "succeeded" && ledgerSnapshot.exists) return;
    credited = true;
    const now = FieldValue.serverTimestamp();
    const amount = money(current.amount);
    const currentEarnings = earnings.data() || {};
    const availableBefore = money(currentEarnings.availableBalance || currentEarnings.availableEarnings);
    const availableAfter = money(availableBefore + amount);
    const tipStats = core.nextTipStats({...currentEarnings, ...(profile.data() || {}), ...(metric.data() || {})}, amount);
    const date = new Date();
    const todayKey = date.toISOString().slice(0, 10);
    const weekStart = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate() - ((date.getUTCDay() + 6) % 7)));
    const weekKey = weekStart.toISOString().slice(0, 10);
    const tipsToday = money((currentEarnings.tipsTodayDate === todayKey ? Number(currentEarnings.tipsToday || 0) : 0) + amount);
    const tipsThisWeek = money((currentEarnings.tipsWeekKey === weekKey ? Number(currentEarnings.tipsThisWeek || 0) : 0) + amount);
    const ledger = {
      transactionId: ledgerRef.id, idempotencyKey: ledgerRef.id,
      userId: current.riderId, riderId: current.riderId, deliveryId: current.deliveryId,
      walletType: "rider", type: "tip", category: "tip", direction: "credit",
      amount, currency: "GBP", balanceBefore: availableBefore, balanceAfter: availableAfter,
      status: "available", source: "delivery_tip", paymentMethod: current.paymentMethod,
      grossTipAmount: amount, riderTipAmount: amount, platformTipRevenue: 0,
      stripePaymentIntentId: stripeIntentId || current.stripePaymentIntentId || null,
      createdAt: now,
    };
    transaction.set(ledgerRef, ledger);
    transaction.set(compatibilityRef, ledger);
    transaction.set(earningsRef, {
      availableBalance: availableAfter, availableEarnings: availableAfter,
      tipsTotal: tipStats.tipTotal, tipTotal: tipStats.tipTotal,
      tipCount: tipStats.tipCount, averageTip: tipStats.averageTip,
      tipsToday, tipsTodayDate: todayKey,
      tipsThisWeek, tipsWeekKey: weekKey,
      updatedAt: now,
    }, {merge: true});
    const statsPatch = {...tipStats, lastTipAt: now, updatedAt: now};
    transaction.set(profileRef, statsPatch, {merge: true});
    transaction.set(riderRef, statsPatch, {merge: true});
    transaction.set(metricRef, statsPatch, {merge: true});
    transaction.set(tipRef, {
      status: "succeeded", paymentStatus: "succeeded", credited: true,
      riderCreditAmount: amount, platformRevenueAmount: 0,
      walletTransactionId: ledgerRef.id, stripePaymentIntentId: stripeIntentId || current.stripePaymentIntentId || null,
      paidAt: now, creditedAt: now, updatedAt: now,
    }, {merge: true});
  });
  if (credited) {
    await notifyOnce({
      eventId: `tip_rider_${tip.deliveryId}`, recipientId: tip.riderId, recipientRole: "rider",
      type: "delivery_tip_received", title: "Tip received", body: `You received a £${money(tip.amount).toFixed(2)} tip.`, deliveryId: tip.deliveryId,
      data: {tipId: tipRef.id, amount: money(tip.amount), currency: "GBP"},
    });
  }
  return {credited, status: "succeeded", tipId: tipRef.id};
}

function submitTip(stripe) {
  return functions.runWith({enforceAppCheck: true}).https.onCall(async (data, context) => {
    const sender = requireAuth(context);
    const deliveryId = text(data && (data.deliveryId || data.requestId));
    if (!deliveryId) throw new functions.https.HttpsError("invalid-argument", "Delivery is required.");
    try {
      const input = core.normalizeTipInput(data || {});
      const db = getFirestore();
      const delivery = await resolveDelivery(db, deliveryId);
      const parties = core.assertCompletedDelivery(delivery && delivery.data, sender.uid);
      const tipRef = db.collection("deliveryTips").doc(delivery.id);
      let reservation;
      await db.runTransaction(async (transaction) => {
        const existing = await transaction.get(tipRef);
        const current = existing.data() || {};
        if (existing.exists && current.status === "succeeded") {
          reservation = {mode: "succeeded", tip: current};
          return;
        }
        if (existing.exists && (Number(current.amountPence) !== input.amountPence || current.paymentMethod !== input.paymentMethod)) {
          throw new functions.https.HttpsError("already-exists", "A tip is already being processed for this delivery.");
        }
        const status = text(current.status).toLowerCase();
        if (current.stripePaymentIntentId && ACTIVE_TIP_STATES.has(status)) {
          reservation = {mode: "existing_intent", tip: current};
          return;
        }
        if (status === "reserving") {
          const reservedAt = current.reservedAt && current.reservedAt.toMillis ? current.reservedAt.toMillis() : 0;
          if (reservedAt && Date.now() - reservedAt < 120000) {
            reservation = {mode: input.paymentMethod === "roth" ? "roth" : "pending", tip: current};
            return;
          }
        }
        const attempt = Number(current.paymentAttempt || 0) + 1;
        const now = FieldValue.serverTimestamp();
        const base = {
          tipId: tipRef.id, deliveryId: delivery.id, requestId: text(delivery.data.requestId) || delivery.id,
          senderId: sender.uid, customerId: sender.uid, riderId: parties.riderId, driverId: parties.riderId,
          amountPence: input.amountPence, amount: input.amount, currency: "GBP",
          paymentMethod: input.paymentMethod, status: "reserving", paymentStatus: "reserving",
          paymentAttempt: attempt, immutable: true, createdAt: current.createdAt || now,
          reservedAt: now, updatedAt: now,
        };
        transaction.set(tipRef, base, {merge: true});
        reservation = {mode: input.paymentMethod === "roth" ? "roth" : "create_intent", tip: base};
      });

      if (reservation.mode === "succeeded") {
        return {ok: true, status: "succeeded", tipId: tipRef.id, amount: reservation.tip.amount};
      }
      if (reservation.mode === "pending") {
        return {ok: true, status: "processing", tipId: tipRef.id};
      }
      let base = reservation.tip;

      if (input.paymentMethod === "roth") {
        await rothLedger.applyWalletDebit({
          userId: sender.uid, userEmail: sender.email, uid: sender.uid,
          amount: input.amount, type: "delivery_tip", referenceId: delivery.id,
          notes: "Roth tip for a completed Circum delivery.",
          transactionId: `wallet_tip_${delivery.id}`,
          metadata: {deliveryId: delivery.id, tipId: tipRef.id},
        });
        const result = await finalizeTip(db, tipRef, base);
        return {ok: true, ...result, amount: input.amount, paymentMethod: input.paymentMethod};
      }

      const suppliedIntentId = text(data.paymentIntentId);
      if (suppliedIntentId) {
        const intent = await stripe.paymentIntents.retrieve(suppliedIntentId);
        assertStripeTipIntent(intent, base, base.stripeCustomerId);
        if (intent.status !== "succeeded") {
          return {ok: true, status: intent.status, tipId: tipRef.id, paymentIntentId: intent.id};
        }
        const result = await finalizeTip(db, tipRef, {...base, stripePaymentIntentId: intent.id}, intent.id);
        return {ok: true, ...result, amount: input.amount, paymentMethod: input.paymentMethod};
      }

      const customerId = text(base.stripeCustomerId) || await ensureStripeCustomer(stripe, db, sender);
      const paymentMethodId = text(data.paymentMethodId);
      if (paymentMethodId) {
        const method = await stripe.paymentMethods.retrieve(paymentMethodId);
        if (method.customer !== customerId) throw new functions.https.HttpsError("permission-denied", "Saved card is unavailable.");
      }
      const ephemeralKey = await stripe.ephemeralKeys.create({customer: customerId}, {apiVersion: "2020-08-27"});
      let intent;
      if (reservation.mode === "existing_intent") {
        intent = await stripe.paymentIntents.retrieve(base.stripePaymentIntentId);
        assertStripeTipIntent(intent, base, customerId);
      } else {
        intent = await stripe.paymentIntents.create({
          amount: input.amountPence, currency: "gbp", customer: customerId,
          automatic_payment_methods: {enabled: true},
          payment_method: paymentMethodId || undefined,
          setup_future_usage: paymentMethodId ? undefined : "off_session",
          metadata: {paymentType: "delivery_tip", tipId: tipRef.id, deliveryId: delivery.id, senderId: sender.uid, riderId: parties.riderId},
        }, {idempotencyKey: `delivery_tip_${delivery.id}_${base.paymentAttempt}`});
        await tipRef.set({stripeCustomerId: customerId, stripePaymentIntentId: intent.id, paymentStatus: intent.status, status: intent.status, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
        base = {...base, stripeCustomerId: customerId, stripePaymentIntentId: intent.id};
      }
      return {
        ok: true, status: intent.status, tipId: tipRef.id, paymentIntentId: intent.id,
        clientSecret: intent.client_secret, customerId, ephemeralKeySecret: ephemeralKey.secret,
        amount: input.amount, currency: "GBP", paymentMethod: input.paymentMethod,
      };
    } catch (error) {
      throw asHttpsError(error);
    }
  });
}

async function reportRating(data, context) {
  const actor = requireAuth(context);
  const ratingId = text(data && (data.ratingId || data.deliveryId));
  const reason = text(data && data.reason).slice(0, 500);
  if (!ratingId || !reason) throw new functions.https.HttpsError("invalid-argument", "Rating and reason are required.");
  const db = getFirestore();
  const ratingRef = db.collection("driverRatings").doc(ratingId);
  const rating = await ratingRef.get();
  if (!rating.exists) throw new functions.https.HttpsError("not-found", "Rating not found.");
  const record = rating.data() || {};
  const admin = isRatingAdmin(context);
  if (!admin && ![record.senderId, record.customerId, record.riderId, record.driverId].includes(actor.uid)) {
    throw new functions.https.HttpsError("permission-denied", "You cannot report this rating.");
  }
  const action = text(data && data.action || "report").toLowerCase();
  if (admin && !["report", "investigate", "hide", "unhide"].includes(action)) {
    throw new functions.https.HttpsError("invalid-argument", "Moderation action is unavailable.");
  }
  const reportRef = db.collection("ratingReports").doc(`${ratingId}_${actor.uid}`);
  await db.runTransaction(async (transaction) => {
    const existing = await transaction.get(reportRef);
    if (!existing.exists) {
      transaction.create(reportRef, {ratingId, deliveryId: record.deliveryId, reportedBy: actor.uid, reason, action, status: action === "report" ? "reported" : action, createdAt: FieldValue.serverTimestamp()});
    }
    transaction.set(ratingRef, {
      reportStatus: action === "report" ? "reported" : action === "investigate" ? "investigating" : record.reportStatus || "clear",
      hiddenByAdmin: action === "hide" ? true : action === "unhide" ? false : record.hiddenByAdmin === true,
      moderationStatus: admin ? action : record.moderationStatus || null,
      moderationReason: admin ? reason : record.moderationReason || null,
      investigatedAt: admin ? FieldValue.serverTimestamp() : record.investigatedAt || null,
      investigatedBy: admin ? actor.uid : record.investigatedBy || null,
      reportedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    if (admin) {
      transaction.create(db.collection("adminAuditLogs").doc(), {
        adminUserId: actor.uid, actionType: `rating_${action}`, recordType: "driverRatings",
        recordId: ratingId, oldValue: {reportStatus: record.reportStatus, hiddenByAdmin: record.hiddenByAdmin},
        newValue: {action, reason}, createdAt: FieldValue.serverTimestamp(),
      });
    }
  });
  return {ok: true, reportId: reportRef.id, status: action === "report" ? "reported" : action};
}

async function processStripeTipIntent(stripe, intent) {
  const metadata = intent && intent.metadata || {};
  if (metadata.paymentType !== "delivery_tip" || !metadata.tipId) return {handled: false};
  const db = getFirestore();
  const tipRef = db.collection("deliveryTips").doc(metadata.tipId);
  const tipSnap = await tipRef.get();
  if (!tipSnap.exists) return {handled: false, reason: "tip_missing"};
  const tip = tipSnap.data() || {};
  assertStripeTipIntent(intent, tip, tip.stripeCustomerId);
  if (intent.status === "succeeded") return {handled: true, ...(await finalizeTip(db, tipRef, tip, intent.id))};
  await tipRef.set({status: intent.status, paymentStatus: intent.status, stripePaymentIntentId: intent.id, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
  return {handled: true, status: intent.status};
}

async function reverseTip(db, tipRef, tip, reason, providerEventId = null) {
  const earningsRef = db.collection("riderEarnings").doc(tip.riderId);
  const profileRef = db.collection("riderProfiles").doc(tip.riderId);
  const riderRef = db.collection("riders").doc(tip.riderId);
  const metricRef = db.collection("driverPerformanceMetrics").doc(tip.riderId);
  const creditRef = db.collection("walletTransactions").doc(`delivery_tip_${tip.deliveryId}`);
  const reversalRef = db.collection("walletTransactions").doc(`delivery_tip_reversal_${tip.deliveryId}`);
  const compatibilityRef = db.collection("riderWalletTransactions").doc(reversalRef.id);
  const reviewRef = db.collection("tipReconciliations").doc(`tip_reversal_${tip.deliveryId}`);
  let status = "reversed";
  await db.runTransaction(async (transaction) => {
    const [currentTip, earnings, profile, rider, metric, credit, reversal] = await Promise.all([
      transaction.get(tipRef), transaction.get(earningsRef), transaction.get(profileRef),
      transaction.get(riderRef), transaction.get(metricRef), transaction.get(creditRef), transaction.get(reversalRef),
    ]);
    if (reversal.exists) return;
    const current = currentTip.data() || tip;
    const wallet = earnings.data() || {};
    const amount = money(current.riderCreditAmount || current.amount);
    const availableBefore = money(wallet.availableBalance || wallet.availableEarnings);
    const creditData = credit.data() || {};
    const alreadyPaidOut = ["reserved", "processing", "paid", "completed"].includes(text(creditData.payoutStatus).toLowerCase());
    if (alreadyPaidOut || availableBefore < amount) {
      status = "finance_review";
      transaction.set(reviewRef, {
        tipId: tipRef.id, deliveryId: current.deliveryId, riderId: current.riderId,
        reason, status: "review_required", amount, availableBalance: availableBefore,
        providerEventId, createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
      transaction.set(tipRef, {
        status: "reversal_review", paymentStatus: reason, reversalStatus: "finance_review",
        providerEventId, updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
      return;
    }
    const availableAfter = money(availableBefore - amount);
    const now = FieldValue.serverTimestamp();
    const reversalRow = {
      transactionId: reversalRef.id, idempotencyKey: reversalRef.id,
      userId: current.riderId, riderId: current.riderId, deliveryId: current.deliveryId,
      walletType: "rider", type: "reversal", category: "tip_reversal", direction: "debit",
      amount, currency: "GBP", balanceBefore: availableBefore, balanceAfter: availableAfter,
      status: "completed", source: "delivery_tip_reversal", reason, providerEventId, createdAt: now,
    };
    transaction.create(reversalRef, reversalRow);
    transaction.create(compatibilityRef, reversalRow);
    const nextTipTotal = money(Math.max(0, Number(wallet.tipTotal || wallet.tipsTotal || 0) - amount));
    const nextTipCount = Math.max(0, Number(wallet.tipCount || 0) - 1);
    transaction.set(earningsRef, {
      availableBalance: availableAfter, availableEarnings: availableAfter,
      tipTotal: nextTipTotal, tipsTotal: nextTipTotal, tipCount: nextTipCount,
      averageTip: nextTipCount ? money(nextTipTotal / nextTipCount) : 0,
      reversalTotal: FieldValue.increment(amount), updatedAt: now,
    }, {merge: true});
    for (const [ref, snapshot] of [[profileRef, profile], [riderRef, rider], [metricRef, metric]]) {
      const projection = snapshot.data() || {};
      const projectionTotal = money(Math.max(0, Number(projection.tipTotal || projection.tipsTotal || 0) - amount));
      const projectionCount = Math.max(0, Number(projection.tipCount || 0) - 1);
      transaction.set(ref, {
        tipTotal: projectionTotal, tipsTotal: projectionTotal, tipCount: projectionCount,
        averageTip: projectionCount ? money(projectionTotal / projectionCount) : 0,
        updatedAt: now,
      }, {merge: true});
    }
    transaction.set(tipRef, {
      status: "reversed", paymentStatus: reason, reversalStatus: "completed",
      reversalTransactionId: reversalRef.id, reversedAt: now, providerEventId, updatedAt: now,
    }, {merge: true});
    transaction.set(reviewRef, {
      tipId: tipRef.id, deliveryId: current.deliveryId, riderId: current.riderId,
      reason, status: "repaired", amount, providerEventId, createdAt: now, updatedAt: now,
    }, {merge: true});
  });
  return {handled: true, status, tipId: tipRef.id};
}

async function processStripeTipReversal(stripe, object, eventId = null, reason = "refunded") {
  let paymentIntentId = text(object && object.payment_intent);
  if (!paymentIntentId && object && object.charge) {
    const charge = await stripe.charges.retrieve(text(object.charge));
    paymentIntentId = text(charge && charge.payment_intent);
  }
  if (!paymentIntentId) return {handled: false};
  const db = getFirestore();
  const matches = await db.collection("deliveryTips").where("stripePaymentIntentId", "==", paymentIntentId).limit(2).get();
  if (matches.empty) return {handled: false};
  if (matches.size !== 1) return {handled: true, status: "finance_review", reason: "ambiguous_tip_payment"};
  const doc = matches.docs[0];
  const tip = doc.data() || {};
  if (tip.paymentMethod === "roth") return {handled: false};
  const intent = await stripe.paymentIntents.retrieve(paymentIntentId);
  assertStripeTipIntent(intent, tip, tip.stripeCustomerId);
  if (reason === "refunded" && Number(object.amount_refunded || 0) < Number(intent.amount || 0)) {
    await db.collection("tipReconciliations").doc(`tip_reversal_${tip.deliveryId}`).set({
      tipId: doc.id, deliveryId: tip.deliveryId, riderId: tip.riderId,
      reason: "partial_refund", status: "review_required", providerEventId: eventId,
      refundedAmountPence: Number(object.amount_refunded || 0), tipAmountPence: Number(intent.amount || 0),
      createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    return {handled: true, status: "finance_review", reason: "partial_refund"};
  }
  return reverseTip(db, doc.ref, tip, reason, eventId);
}

async function reverseRothTip(data, context) {
  const admin = requireAuth(context);
  if (!isFinanceAdmin(context)) {
    throw new functions.https.HttpsError("permission-denied", "Finance permission is required.");
  }
  const deliveryId = text(data && data.deliveryId);
  const reason = text(data && data.reason || "approved_roth_tip_refund").slice(0, 160);
  if (!deliveryId) throw new functions.https.HttpsError("invalid-argument", "Delivery is required.");
  const db = getFirestore();
  const tipRef = db.collection("deliveryTips").doc(deliveryId);
  const snapshot = await tipRef.get();
  if (!snapshot.exists) throw new functions.https.HttpsError("not-found", "Tip not found.");
  const tip = snapshot.data() || {};
  if (tip.paymentMethod !== "roth" || tip.status !== "succeeded") {
    throw new functions.https.HttpsError("failed-precondition", "This Roth tip is not reversible.");
  }
  await rothLedger.recordRothMovement({
    db,
    userId: tip.senderId,
    uid: tip.senderId,
    amount: money(tip.amount),
    balanceType: rothLedger.BALANCE_TYPES.rothCredit,
    type: rothLedger.TRANSACTION_TYPES.refund,
    reason,
    relatedEntityId: deliveryId,
    paymentProvider: "roth_internal",
    providerTransactionId: `roth_tip_refund_${deliveryId}`,
    issuedByAdminId: admin.uid,
    transactionId: `roth_tip_refund_${deliveryId}`,
    metadata: {deliveryId, tipId: tipRef.id, source: "delivery_tip_reversal"},
  });
  return reverseTip(db, tipRef, tip, reason, `roth_tip_refund_${deliveryId}`);
}

function reconcileDeliveryTips(stripe) {
  return functions.pubsub.schedule("every 15 minutes").onRun(async () => {
    const db = getFirestore();
    const cursorRef = db.collection("operationsState").doc("tip_reconciliation_cursor");
    const cursorSnapshot = await cursorRef.get();
    const cursor = text((cursorSnapshot.data() || {}).lastTipId);
    let query = db.collection("deliveryTips").orderBy(FieldPath.documentId()).limit(100);
    if (cursor) query = query.startAfter(cursor);
    let snapshot = await query.get();
    if (snapshot.empty && cursor) snapshot = await db.collection("deliveryTips").orderBy(FieldPath.documentId()).limit(100).get();
    const results = [];
    for (const doc of snapshot.docs) {
      const tip = doc.data() || {};
      const ledger = await db.collection("walletTransactions").doc(`delivery_tip_${tip.deliveryId}`).get();
      try {
        const updatedMillis = tip.updatedAt && tip.updatedAt.toMillis ? tip.updatedAt.toMillis() : 0;
        if (["reserving", "processing"].includes(text(tip.status).toLowerCase()) &&
            updatedMillis > 0 && Date.now() - updatedMillis > 30 * 60 * 1000) {
          await db.collection("tipReconciliations").doc(`tip_${doc.id}`).set({
            tipId: doc.id, deliveryId: text(tip.deliveryId), riderId: text(tip.riderId),
            status: "review_required", reason: "pending_timeout", updatedAt: FieldValue.serverTimestamp(),
          }, {merge: true});
        }
        if (tip.status === "succeeded" && !ledger.exists) {
          if (tip.paymentMethod === "roth") {
            results.push(await finalizeTip(db, doc.ref, tip));
          } else if (tip.stripePaymentIntentId) {
            const intent = await stripe.paymentIntents.retrieve(tip.stripePaymentIntentId);
            assertStripeTipIntent(intent, tip, tip.stripeCustomerId);
            if (intent.status === "succeeded") results.push(await finalizeTip(db, doc.ref, tip, intent.id));
          }
        } else if (tip.credited === true && tip.paymentMethod !== "roth" && tip.stripePaymentIntentId) {
          const intent = await stripe.paymentIntents.retrieve(tip.stripePaymentIntentId);
          assertStripeTipIntent(intent, tip, tip.stripeCustomerId);
          if (intent.status !== "succeeded") results.push(await reverseTip(db, doc.ref, tip, `payment_${intent.status}`));
        }
      } catch (error) {
        await db.collection("tipReconciliations").doc(`tip_${doc.id}`).set({
          tipId: doc.id, deliveryId: text(tip.deliveryId), riderId: text(tip.riderId),
          status: "review_required", reason: "reconciliation_failed",
          errorCode: text(error.code || error.message).slice(0, 120), updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
      }
    }
    if (!snapshot.empty) {
      await cursorRef.set({lastTipId: snapshot.docs[snapshot.docs.length - 1].id, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
    }
    console.log("Tip reconciliation completed", {scanned: snapshot.size, repaired: results.length});
    return null;
  });
}

async function getDeliveryAppreciation(data, context) {
  const sender = requireAuth(context);
  const deliveryId = text(data && data.deliveryId);
  const db = getFirestore();
  const delivery = await resolveDelivery(db, deliveryId);
  core.assertCompletedDelivery(delivery && delivery.data, sender.uid);
  const [rating, tip] = await Promise.all([
    db.collection("driverRatings").doc(delivery.id).get(),
    db.collection("deliveryTips").doc(delivery.id).get(),
  ]);
  const ratingData = rating.data() || {};
  const tipData = tip.data() || {};
  return {
    deliveryId: delivery.id,
    rating: rating.exists ? {
      stars: Number(ratingData.starRating || 0),
      feedbackTags: Array.isArray(ratingData.feedbackTags) ? ratingData.feedbackTags : [],
      feedbackText: text(ratingData.feedbackText),
      createdAt: ratingData.createdAt || null,
    } : null,
    tip: tip.exists ? {
      amountPence: Number(tipData.amountPence || 0),
      currency: "GBP",
      status: text(tipData.status),
      paidAt: tipData.paidAt || null,
    } : null,
  };
}

async function getRiderAppreciation(data, context) {
  const rider = requireAuth(context);
  const db = getFirestore();
  const limit = Math.min(30, Math.max(1, Number(data && data.limit || 20)));
  const cursorMillis = Number(data && data.beforeMillis || 0);
  let tipsQuery = db.collection("walletTransactions")
      .where("riderId", "==", rider.uid)
      .where("category", "in", ["tip", "tip_reversal"])
      .orderBy("createdAt", "desc");
  if (cursorMillis > 0) tipsQuery = tipsQuery.where("createdAt", "<", new Date(cursorMillis));
  const now = new Date();
  const today = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
  const week = new Date(today);
  week.setUTCDate(today.getUTCDate() - ((today.getUTCDay() + 6) % 7));
  const periodTipsQuery = db.collection("walletTransactions")
      .where("riderId", "==", rider.uid)
      .where("category", "in", ["tip", "tip_reversal"])
      .where("createdAt", ">=", week)
      .orderBy("createdAt", "desc")
      .limit(500);
  const [profile, metrics, tips, periodTips, recentRatings] = await Promise.all([
    db.collection("riderProfiles").doc(rider.uid).get(),
    db.collection("driverPerformanceMetrics").doc(rider.uid).get(),
    tipsQuery.limit(limit + 1).get(),
    periodTipsQuery.get(),
    db.collection("driverRatings").where("driverId", "==", rider.uid).orderBy("createdAt", "desc").limit(20).get(),
  ]);
  const stats = {...(profile.data() || {}), ...(metrics.data() || {})};
  const tipDocs = tips.docs.slice(0, limit);
  const periodRows = periodTips.docs.map((doc) => doc.data() || {});
  const signedAmount = (row) => money((text(row.direction) === "debit" ? -1 : 1) * Number(row.amount || 0));
  const tipsThisWeek = money(periodRows.reduce((sum, row) => sum + signedAmount(row), 0));
  const tipsToday = money(periodRows.filter((row) => {
    const created = row.createdAt && row.createdAt.toDate ? row.createdAt.toDate() : null;
    return created && created >= today;
  }).reduce((sum, row) => sum + signedAmount(row), 0));
  const safeRatings = recentRatings.docs.map((doc) => doc.data() || {}).filter((row) =>
    row.hiddenByAdmin !== true && text(row.reportStatus || "clear") === "clear" && Number(row.starRating) >= 4);
  return {
    summary: {
      averageRating: Number(stats.averageRating || stats.rating || 0),
      ratingTotal: Number(stats.ratingTotal || 0),
      totalRatings: Number(stats.totalRatings || 0),
      distribution: [1, 2, 3, 4, 5].map((stars) => Number(stats[[null, "oneStarCount", "twoStarCount", "threeStarCount", "fourStarCount", "fiveStarCount"][stars]] || 0)),
      lifetimeTips: money(stats.tipTotal || stats.tipsTotal),
      tipCount: Number(stats.tipCount || 0),
      averageTip: money(stats.averageTip),
      tipsToday,
      tipsThisWeek,
    },
    recentPraise: safeRatings.map((row) => ({
      stars: Number(row.starRating),
      compliments: Array.isArray(row.feedbackTags) ? row.feedbackTags : [],
      comment: text(row.feedbackText),
      createdAt: row.createdAt || null,
    })),
    tips: tipDocs.map((doc) => {
      const row = doc.data() || {};
      return {
        id: doc.id, deliveryId: text(row.deliveryId), amount: money(row.amount), currency: "GBP",
        status: text(row.category) === "tip_reversal" ? "reversed" : text(row.status || "available"),
        createdAt: row.createdAt || null,
        payoutStatus: text(row.payoutStatus || "available"),
        direction: text(row.direction || "credit"),
      };
    }),
    hasMore: tips.docs.length > limit,
  };
}

exports.submitDeliveryRating = callableRuntime.https.onCall(submitRating);
exports.submitDeliveryTip = submitTip;
exports.reportRating = callableRuntime.https.onCall(reportRating);
exports.getDeliveryAppreciation = callableRuntime.https.onCall(getDeliveryAppreciation);
exports.getRiderAppreciation = callableRuntime.https.onCall(getRiderAppreciation);
exports.reverseRothDeliveryTip = callableRuntime.https.onCall(reverseRothTip);
exports.processStripeTipIntent = processStripeTipIntent;
exports.processStripeTipReversal = processStripeTipReversal;
exports.reconcileDeliveryTips = reconcileDeliveryTips;
exports._test = {submitRating, reportRating, finalizeTip, reverseTip, reverseRothTip, resolveDelivery, assertStripeTipIntent, getDeliveryAppreciation, getRiderAppreciation};
