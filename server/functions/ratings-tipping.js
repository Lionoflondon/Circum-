/* eslint-disable max-len, require-jsdoc */
"use strict";

const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const core = require("./ratings-tipping-core");
const rothLedger = require("./roth-ledger");
const communication = require("./communication-engine");

const text = (value) => `${value || ""}`.trim();
const money = (value) => Math.round(Number(value || 0) * 100) / 100;

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
  return functions.runWith({enforceAppCheck: true, secrets: ["STRIPE_SECRET_KEY"]}).https.onCall(async (data, context) => {
    const sender = requireAuth(context);
    const deliveryId = text(data && (data.deliveryId || data.requestId));
    if (!deliveryId) throw new functions.https.HttpsError("invalid-argument", "Delivery is required.");
    try {
      const input = core.normalizeTipInput(data || {});
      const db = getFirestore();
      const delivery = await resolveDelivery(db, deliveryId);
      const parties = core.assertCompletedDelivery(delivery && delivery.data, sender.uid);
      const tipRef = db.collection("deliveryTips").doc(delivery.id);
      const existing = await tipRef.get();
      const current = existing.data() || {};
      if (existing.exists && current.status === "succeeded") {
        return {ok: true, status: "succeeded", tipId: tipRef.id, amount: current.amount};
      }
      if (existing.exists && (Number(current.amountPence) !== input.amountPence || current.paymentMethod !== input.paymentMethod)) {
        throw new functions.https.HttpsError("already-exists", "A tip is already being processed for this delivery.");
      }
      const now = FieldValue.serverTimestamp();
      const base = {
        tipId: tipRef.id, deliveryId: delivery.id, requestId: text(delivery.data.requestId) || delivery.id,
        senderId: sender.uid, customerId: sender.uid, riderId: parties.riderId, driverId: parties.riderId,
        amountPence: input.amountPence, amount: input.amount, currency: "GBP",
        paymentMethod: input.paymentMethod, status: "processing", paymentStatus: "processing",
        immutable: true, createdAt: current.createdAt || now, updatedAt: now,
      };
      await tipRef.set(base, {merge: true});

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
        if (intent.metadata.tipId !== tipRef.id || intent.metadata.senderId !== sender.uid) {
          throw new functions.https.HttpsError("permission-denied", "Tip payment does not belong to this account.");
        }
        if (intent.status !== "succeeded") {
          return {ok: true, status: intent.status, tipId: tipRef.id, paymentIntentId: intent.id};
        }
        const result = await finalizeTip(db, tipRef, {...base, stripePaymentIntentId: intent.id}, intent.id);
        return {ok: true, ...result, amount: input.amount, paymentMethod: input.paymentMethod};
      }

      const customerId = await ensureStripeCustomer(stripe, db, sender);
      const paymentMethodId = text(data.paymentMethodId);
      if (paymentMethodId) {
        const method = await stripe.paymentMethods.retrieve(paymentMethodId);
        if (method.customer !== customerId) throw new functions.https.HttpsError("permission-denied", "Saved card is unavailable.");
      }
      const ephemeralKey = await stripe.ephemeralKeys.create({customer: customerId}, {apiVersion: "2020-08-27"});
      const attempt = Number(current.paymentAttempt || 0) + 1;
      const intent = await stripe.paymentIntents.create({
        amount: input.amountPence, currency: "gbp", customer: customerId,
        automatic_payment_methods: {enabled: true},
        payment_method: paymentMethodId || undefined,
        setup_future_usage: paymentMethodId ? undefined : "off_session",
        metadata: {paymentType: "delivery_tip", tipId: tipRef.id, deliveryId: delivery.id, senderId: sender.uid, riderId: parties.riderId},
      }, {idempotencyKey: `delivery_tip_${delivery.id}_${attempt}`});
      await tipRef.set({stripeCustomerId: customerId, stripePaymentIntentId: intent.id, paymentAttempt: attempt, paymentStatus: intent.status, status: intent.status, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
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
  if (intent.status === "succeeded") return {handled: true, ...(await finalizeTip(db, tipRef, tipSnap.data(), intent.id))};
  await tipRef.set({status: intent.status, paymentStatus: intent.status, stripePaymentIntentId: intent.id, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
  return {handled: true, status: intent.status};
}

exports.submitDeliveryRating = functions.runWith({enforceAppCheck: true}).https.onCall(submitRating);
exports.submitDeliveryTip = submitTip;
exports.reportRating = functions.runWith({enforceAppCheck: true}).https.onCall(reportRating);
exports.processStripeTipIntent = processStripeTipIntent;
exports._test = {submitRating, reportRating, finalizeTip, resolveDelivery};
