/* eslint-disable max-len, require-jsdoc */
"use strict";

const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const core = require("./ratings-tipping-core");
const tipRefunds = require("./tip-refunds");
const rothLedger = require("./roth-ledger");
const communication = require("./communication-engine");
const {senderPaymentCallable} = require("./sender-app-check");

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
    "rating-reconciliation-required": ["failed-precondition", "Rating history needs reconciliation. Please contact support."],
    "invalid-rating": ["invalid-argument", "Choose a whole-star rating from one to five."],
    "invalid-feedback": ["invalid-argument", "Feedback must be text."],
    "feedback-too-long": ["invalid-argument", "Feedback is limited to 500 characters."],
    "invalid-feedback-tag": ["invalid-argument", "One or more feedback choices are unavailable."],
    "invalid-tip-currency": ["invalid-argument", "Tips must use GBP."],
    "invalid-tip-amount": ["invalid-argument", "Choose a tip between £1 and £100."],
    "invalid-payment-method": ["invalid-argument", "Choose an available payment method."],
  };
  const mapped = map[code] || ["internal", "We could not process your appreciation. Please try again."];
  return new functions.https.HttpsError(mapped[0], mapped[1]);
}

async function resolveDelivery(db, deliveryId) {
  const direct = await db.collection("deliveryRequests").doc(deliveryId).get();
  if (direct.exists) return {id: direct.id, ref: direct.ref, data: direct.data() || {}};
  const query = await db.collection("deliveryRequests").where("requestId", "==", deliveryId).limit(2).get();
  if (query.empty) return null;
  if (query.size !== 1) throw new functions.https.HttpsError("failed-precondition", "Delivery reference is ambiguous.");
  const doc = query.docs[0];
  return {id: doc.id, ref: doc.ref, data: doc.data() || {}};
}

function ratingTitle(stars) {
  return ["", "Poor Experience", "Needs Improvement", "Good Delivery", "Great Delivery", "Outstanding Delivery"][stars];
}

async function notifyOnce({eventId, recipientId, recipientRole, type, title, body, deliveryId, data = {}}) {
  const db = getFirestore();
  const ref = db.collection("notificationEvents").doc(eventId);
  const created = await db.runTransaction(async (transaction) => {
    const existing = await transaction.get(ref);
    if (existing.exists) return existing.data().status !== "sent";
    transaction.create(ref, {
      eventId, recipientId, recipientRole, type, title, body, deliveryId,
      status: "created", data, createdAt: FieldValue.serverTimestamp(),
    });
    return true;
  });
  if (!created) return;
  const notificationId = await communication.emitNotification({
    recipientId, recipientRole, type, title, body,
    data: {...data, deliveryId, bookingId: deliveryId}, dedupeKey: eventId,
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
    if ((data.riderId && data.riderId !== parties.riderId) || (data.senderId && data.senderId !== sender.uid)) {
      throw new functions.https.HttpsError("permission-denied", "Rating participants do not match this delivery.");
    }
    const ratingRef = db.collection("driverRatings").doc(delivery.id);
    const feedbackRef = db.collection("ratingPrivateFeedback").doc(delivery.id);
    const profileRef = db.collection("riderProfiles").doc(parties.riderId);
    const riderRef = db.collection("riders").doc(parties.riderId);
    const metricRef = db.collection("driverPerformanceMetrics").doc(parties.riderId);
    const created = await db.runTransaction(async (transaction) => {
      const [existing, profile, metric, freshDelivery, privateFeedback] = await transaction.getAll(ratingRef, profileRef, metricRef, delivery.ref, feedbackRef);
      const fresh = freshDelivery.data() || {};
      const currentParties = core.assertCompletedDelivery(fresh, sender.uid);
      if (currentParties.riderId !== parties.riderId || parties.riderId === sender.uid) {
        throw new functions.https.HttpsError("failed-precondition", "The delivery participants are invalid.");
      }
      const paid = ["paid", "succeeded", "success"].includes(text(fresh.paymentStatus).toLowerCase());
      if (!paid || fresh.isTest === true || fresh.testData === true || text(fresh.environment).toLowerCase() === "test" ||
          [fresh.status, fresh.deliveryState].some((status) => ["cancelled", "canceled", "failed", "rejected", "refunded"].includes(text(status).toLowerCase())) ||
          fresh.refunded === true || fresh.refundStatus === "refunded") {
        throw new functions.https.HttpsError("failed-precondition", "Only a completed paid delivery can be rated.");
      }
      if (existing.exists) {
        const saved = existing.data();
        if (saved.senderId === sender.uid && saved.riderId === parties.riderId && saved.starRating === input.stars &&
            (privateFeedback.exists ? privateFeedback.data().feedbackText : saved.feedbackText || "") === input.feedback && JSON.stringify(privateFeedback.exists ? privateFeedback.data().feedbackTags : saved.feedbackTags) === JSON.stringify(input.feedbackTags)) return false;
        throw new functions.https.HttpsError("already-exists", "This delivery has already been rated.");
      }
      const current = {...(profile.data() || {}), ...(metric.data() || {})};
      const stats = core.nextRatingStats(current, input.stars);
      const now = FieldValue.serverTimestamp();
      const publishedRating = {
        ratingId: delivery.id,
        deliveryId: delivery.id,
        requestId: text(delivery.data.requestId) || delivery.id,
        customerId: sender.uid,
        senderId: sender.uid,
        driverId: parties.riderId,
        riderId: parties.riderId,
        starRating: input.stars,
        ratingTitle: ratingTitle(input.stars),
        feedbackText: core.publicRatingFeedback(input.feedback),
        deliveryCategories: core.ratingCategories(fresh),
        feedbackTags: input.feedbackTags.filter((tag) => !["Safety concern", "Damaged item"].includes(tag)),
        reportStatus: "clear",
        hiddenByAdmin: false,
        immutable: true,
        createdAt: now,
      };
      transaction.create(ratingRef, publishedRating);
      transaction.create(db.collection("publishedDriverRatings").doc(delivery.id), publishedRating);
      transaction.create(feedbackRef, {ratingId: delivery.id, deliveryId: delivery.id, senderId: sender.uid, riderId: parties.riderId, feedbackText: input.feedback, feedbackTags: input.feedbackTags, createdAt: now});
      if (input.feedbackTags.some((tag) => ["Safety concern", "Damaged item"].includes(tag))) {
        transaction.create(db.collection("supportTickets").doc(`rating_${delivery.id}`), {
          ticketId: `rating_${delivery.id}`, deliveryId: delivery.id, ratingId: delivery.id, senderId: sender.uid,
          userId: sender.uid, riderId: parties.riderId, category: "delivery_rating_issue", source: "delivery_rating",
          status: "open", subject: "Delivery feedback received", message: input.feedback,
          feedbackTags: input.feedbackTags, createdAt: now, updatedAt: now,
        });
      }
      const statsPatch = {...stats, lastRatedAt: now, updatedAt: now};
      transaction.set(profileRef, statsPatch, {merge: true});
      transaction.set(riderRef, statsPatch, {merge: true});
      transaction.set(metricRef, statsPatch, {merge: true});
      transaction.set(delivery.ref, {
        appreciation: {ratingId: ratingRef.id, ratingSubmitted: true, ratedAt: now},
        updatedAt: now,
      }, {merge: true});
      return true;
    });
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
    return {ok: true, idempotent: !created, ratingId: ratingRef.id, stars: input.stars, title: ratingTitle(input.stars)};
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

function assertTipIntent(tip, intent) {
  const metadata = intent.metadata || {};
  if (intent.status === "succeeded" && (intent.amount_received !== tip.amountPence || (!process.env.FIRESTORE_EMULATOR_HOST && intent.livemode !== true))) {
    throw new functions.https.HttpsError("failed-precondition", "A live captured tip payment is required.");
  }
  if (intent.id !== tip.stripePaymentIntentId || intent.amount !== tip.amountPence ||
      text(intent.currency).toUpperCase() !== "GBP" || metadata.paymentType !== "delivery_tip" ||
      metadata.tipId !== tip.tipId || metadata.deliveryId !== tip.deliveryId ||
      metadata.senderId !== tip.senderId || metadata.riderId !== tip.riderId ||
      (tip.stripeCustomerId && intent.customer !== tip.stripeCustomerId)) {
    throw new functions.https.HttpsError("permission-denied", "Tip payment details do not match.");
  }
}

function assertTipParties(tip, delivery) {
  const parties = core.deliveryParties(delivery);
  const currency = text(delivery.currency || delivery.paymentCurrency || "GBP").toUpperCase();
  if (currency !== tip.currency) throw new functions.https.HttpsError("failed-precondition", "Tip currency does not match delivery currency.");
  if (parties.senderId !== tip.senderId || parties.riderId !== tip.riderId || tip.senderId === tip.riderId) {
    throw new functions.https.HttpsError("permission-denied", "Tip delivery participants do not match.");
  }
  if (!Number.isSafeInteger(tip.amountPence) || tip.amountPence < 100 || tip.amountPence > 10000 || tip.currency !== "GBP") {
    throw new functions.https.HttpsError("failed-precondition", "Tip amount or currency is invalid.");
  }
}

async function finalizeTip(db, tipRef, tip, stripeIntentId = null) {
  const earningsRef = db.collection("riderEarnings").doc(tip.riderId);
  const profileRef = db.collection("riderProfiles").doc(tip.riderId);
  const riderRef = db.collection("riders").doc(tip.riderId);
  const metricRef = db.collection("driverPerformanceMetrics").doc(tip.riderId);
  const ledgerRef = db.collection("walletTransactions").doc(`delivery_tip_${tip.deliveryId}`);
  const compatibilityRef = db.collection("riderWalletTransactions").doc(`delivery_tip_${tip.deliveryId}`);
  const credited = await db.runTransaction(async (transaction) => {
    const [currentTip, earnings, profile, metric, ledgerSnapshot, deliverySnapshot] = await transaction.getAll(
      tipRef, earningsRef, profileRef, metricRef, ledgerRef, db.collection("deliveryRequests").doc(tip.deliveryId),
    );
    if (!currentTip.exists || !deliverySnapshot.exists) throw new functions.https.HttpsError("not-found", "Tip delivery not found.");
    const current = currentTip.data();
    if (current.riderId !== tip.riderId || current.senderId !== tip.senderId || current.deliveryId !== tip.deliveryId) {
      throw new functions.https.HttpsError("permission-denied", "Tip identity changed.");
    }
    assertTipParties(current, deliverySnapshot.data());
    if (ledgerSnapshot.exists) {
      const ledger = ledgerSnapshot.data();
      if (ledger.riderId !== current.riderId || ledger.deliveryId !== current.deliveryId || ledger.type !== "tip" || ledger.currency !== "GBP" || Math.round(ledger.amount * 100) !== current.amountPence) {
        throw new functions.https.HttpsError("failed-precondition", "Tip ledger identity mismatch.");
      }
      if (!["refund_pending", "refunded", "partially_refunded", "reversed"].includes(current.status)) transaction.set(tipRef, {status: "succeeded", credited: true}, {merge: true});
      return false;
    }
    if (["refund_pending", "refunded", "partially_refunded", "reversed"].includes(current.status)) return false;
    const completed = deliverySnapshot.data();
    if ((!completed.completedAt && !completed.deliveredAt && !core.COMPLETED_STATUSES.has(text(completed.deliveryState || completed.status).toLowerCase())) ||
        completed.isTest === true || completed.testData === true) {
      throw new functions.https.HttpsError("failed-precondition", "Tip delivery is not completed.");
    }
    if (current.paymentMethod === "roth") {
      const debit = await transaction.get(db.collection("walletTransactions").doc(`wallet_tip_${current.deliveryId}`));
      if (!debit.exists || debit.data().uid !== current.senderId || debit.data().type !== "delivery_tip" || debit.data().referenceId !== current.deliveryId || Math.abs(Number(debit.data().amount)) !== current.amountPence / 100) {
        throw new functions.https.HttpsError("failed-precondition", "Tip debit has not been confirmed.");
      }
    } else if (!stripeIntentId || stripeIntentId !== current.stripePaymentIntentId) {
      throw new functions.https.HttpsError("failed-precondition", "Tip payment has not been confirmed.");
    }
    const now = FieldValue.serverTimestamp();
    const amount = current.amountPence / 100;
    const currentEarnings = earnings.data() || {};
    const availableBeforePence = Math.round(Number(currentEarnings.availableBalance ?? currentEarnings.availableEarnings ?? 0) * 100);
    if (!Number.isSafeInteger(availableBeforePence)) throw new functions.https.HttpsError("failed-precondition", "Rider balance requires reconciliation.");
    const availableAfterPence = availableBeforePence + current.amountPence;
    const availableBefore = availableBeforePence / 100;
    const availableAfter = availableAfterPence / 100;
    const tipStats = core.nextTipStats({...currentEarnings, ...(profile.data() || {}), ...(metric.data() || {})}, amount);
    const date = new Date();
    const todayKey = date.toISOString().slice(0, 10);
    const weekStart = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate() - ((date.getUTCDay() + 6) % 7)));
    const weekKey = weekStart.toISOString().slice(0, 10);
    const tipsToday = ((currentEarnings.tipsTodayDate === todayKey ? Math.round(Number(currentEarnings.tipsToday || 0) * 100) : 0) + current.amountPence) / 100;
    const tipsThisWeek = ((currentEarnings.tipsWeekKey === weekKey ? Math.round(Number(currentEarnings.tipsThisWeek || 0) * 100) : 0) + current.amountPence) / 100;
    const ledger = {
      transactionId: ledgerRef.id, idempotencyKey: ledgerRef.id,
      userId: current.riderId, riderId: current.riderId, senderId: current.senderId, deliveryId: current.deliveryId,
      amountPence: current.amountPence, tipId: tipRef.id,
      walletType: "rider", type: "tip", category: "tip", direction: "credit",
      amount, currency: "GBP", balanceBefore: availableBefore, balanceAfter: availableAfter,
      status: "available", source: "delivery_tip", paymentMethod: current.paymentMethod,
      stripePaymentIntentId: stripeIntentId || current.stripePaymentIntentId || null,
      createdAt: now,
    };
    transaction.create(ledgerRef, ledger);
    transaction.create(compatibilityRef, ledger);
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
    return true;
  });
  const finalStatus = (await tipRef.get()).data().status;
  if (finalStatus === "succeeded") {
    await notifyOnce({
      eventId: `tip_rider_${tip.deliveryId}`, recipientId: tip.riderId, recipientRole: "rider",
      type: "delivery_tip_received", title: "Tip received", body: `You received a £${money(tip.amount).toFixed(2)} tip.`, deliveryId: tip.deliveryId,
      data: {tipId: tipRef.id, amount: money(tip.amount), currency: "GBP"},
    });
  }
  return {credited, status: finalStatus, tipId: tipRef.id};
}

function submitTip(stripe) {
  return senderPaymentCallable(async (data, context) => {
    const sender = requireAuth(context);
    const deliveryId = text(data && (data.deliveryId || data.requestId));
    if (!deliveryId) throw new functions.https.HttpsError("invalid-argument", "Delivery is required.");
    try {
      const input = core.normalizeTipInput(data || {});
      const db = getFirestore();
      const delivery = await resolveDelivery(db, deliveryId);
      const parties = core.assertCompletedDelivery(delivery && delivery.data, sender.uid);
      if ((data.riderId && data.riderId !== parties.riderId) || (data.senderId && data.senderId !== sender.uid)) throw new functions.https.HttpsError("permission-denied", "Tip participants do not match.");
      const tipRef = db.collection("deliveryTips").doc(delivery.id);
      const base = await db.runTransaction(async (transaction) => {
        const [existing, freshDelivery] = await transaction.getAll(tipRef, delivery.ref);
        const fresh = freshDelivery.data() || {};
        core.assertCompletedDelivery(fresh, sender.uid);
        const candidate = {tipId: tipRef.id, deliveryId: delivery.id, requestId: text(fresh.requestId) || delivery.id,
          senderId: sender.uid, customerId: sender.uid, riderId: parties.riderId, driverId: parties.riderId,
          amountPence: input.amountPence, amount: input.amount, currency: "GBP", paymentMethod: input.paymentMethod};
        assertTipParties(candidate, fresh);
        if (!["paid", "succeeded", "success"].includes(text(fresh.paymentStatus).toLowerCase()) || fresh.refunded === true || fresh.refundStatus === "refunded" ||
            fresh.isTest === true || fresh.testData === true || text(fresh.environment).toLowerCase() === "test") {
          throw new functions.https.HttpsError("failed-precondition", "Only a completed paid delivery can receive a tip.");
        }
        if (existing.exists) {
          const current = existing.data();
          for (const field of ["senderId", "riderId", "deliveryId", "amountPence", "currency", "paymentMethod"]) {
            if (current[field] !== candidate[field]) throw new functions.https.HttpsError("already-exists", "A different tip already exists for this delivery.");
          }
          return current;
        }
        const now = FieldValue.serverTimestamp();
        const record = {...candidate, status: "processing", paymentStatus: "processing", immutable: true, createdAt: now, updatedAt: now};
        transaction.create(tipRef, record);
        return record;
      });
      if (base.status === "succeeded") {
        return {ok: true, ...await finalizeTip(db, tipRef, base, base.stripePaymentIntentId), amount: base.amount};
      }
      if (["refunded", "refund_pending", "reversed"].includes(base.status)) {
        return {ok: true, status: base.status, tipId: tipRef.id, amount: base.amount};
      }

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
        assertTipIntent(base, intent);
        if (intent.status !== "succeeded") {
          return {ok: true, status: intent.status, tipId: tipRef.id, paymentIntentId: intent.id};
        }
        const result = await finalizeTip(db, tipRef, {...base, stripePaymentIntentId: intent.id}, intent.id);
        return {ok: true, ...result, amount: input.amount, paymentMethod: input.paymentMethod};
      }

      if (!base.stripePaymentIntentId && base.createdAt && typeof base.createdAt.toMillis === "function" && Date.now() - base.createdAt.toMillis() > 23 * 60 * 60 * 1000) {
        throw new functions.https.HttpsError("failed-precondition", "This tip needs payment reconciliation before retry.");
      }
      const customerId = await ensureStripeCustomer(stripe, db, sender);
      const paymentMethodId = text(data.paymentMethodId);
      if (paymentMethodId) {
        const method = await stripe.paymentMethods.retrieve(paymentMethodId);
        if (method.customer !== customerId) throw new functions.https.HttpsError("permission-denied", "Saved card is unavailable.");
      }
      const ephemeralKey = await stripe.ephemeralKeys.create({customer: customerId}, {apiVersion: "2020-08-27"});
      const intent = base.stripePaymentIntentId ? await stripe.paymentIntents.retrieve(base.stripePaymentIntentId) : await stripe.paymentIntents.create({
        amount: input.amountPence, currency: "gbp", customer: customerId,
        automatic_payment_methods: {enabled: true},
        payment_method: paymentMethodId || undefined,
        metadata: {paymentType: "delivery_tip", tipId: tipRef.id, deliveryId: delivery.id, senderId: sender.uid, riderId: parties.riderId},
      }, {idempotencyKey: `delivery_tip_${delivery.id}`});
      await db.runTransaction(async (transaction) => {
        const snapshot = await transaction.get(tipRef);
        const current = snapshot.data();
        if (current.stripePaymentIntentId && current.stripePaymentIntentId !== intent.id) throw new functions.https.HttpsError("failed-precondition", "Tip payment changed.");
        if (["succeeded", "refund_pending", "refunded", "reversed"].includes(current.status)) return;
        transaction.set(tipRef, {stripeCustomerId: customerId, stripePaymentIntentId: intent.id, paymentStatus: intent.status, status: intent.status, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
      });
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
  if (!["report", "investigate", "hide", "unhide"].includes(action)) {
    throw new functions.https.HttpsError("invalid-argument", "Moderation action is unavailable.");
  }
  if (!admin && action !== "report") {
    throw new functions.https.HttpsError("permission-denied", "Only moderators can change rating visibility.");
  }
  const reportRef = db.collection("ratingReports").doc(`${ratingId}_${actor.uid}`);
  const projectionId = text(record.deliveryId) || ratingId;
  await db.runTransaction(async (transaction) => {
    const privateRef = db.collection("ratingPrivateFeedback").doc(projectionId);
    const projectionRef = db.collection("publishedDriverRatings").doc(projectionId);
    const [existing, currentRating, privateFeedback, projection] = await transaction.getAll(reportRef, ratingRef, privateRef, projectionRef);
    if (!currentRating.exists) throw new functions.https.HttpsError("not-found", "Rating not found.");
    const record = currentRating.data();
    if (!admin && ![record.senderId, record.customerId, record.riderId, record.driverId].includes(actor.uid)) {
      throw new functions.https.HttpsError("permission-denied", "You cannot report this rating.");
    }
    if (admin && !privateFeedback.exists) transaction.create(privateRef, {ratingId, feedbackText: record.feedbackText || "", createdAt: FieldValue.serverTimestamp()});
    if (!existing.exists) {
      transaction.create(reportRef, {ratingId, deliveryId: record.deliveryId, reportedBy: actor.uid, reason, action, status: action === "report" ? "reported" : action, createdAt: FieldValue.serverTimestamp()});
    }
    transaction.set(ratingRef, admin ? {
      reportStatus: action === "report" ? "reported" : action === "investigate" ? "investigating" : record.reportStatus || "clear",
      feedbackText: action === "hide" ? "" : action === "unhide" ? core.publicRatingFeedback(privateFeedback.exists ? privateFeedback.data().feedbackText : record.feedbackText || "") : record.feedbackText || "",
      hiddenByAdmin: action === "hide" ? true : action === "unhide" ? false : record.hiddenByAdmin === true,
      moderationStatus: admin ? action : record.moderationStatus || null,
      moderationReason: admin ? reason : record.moderationReason || null,
      investigatedAt: admin ? FieldValue.serverTimestamp() : record.investigatedAt || null,
      investigatedBy: admin ? actor.uid : record.investigatedBy || null,
      reportedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    } : {
      reportStatus: record.reportStatus === "clear" || !record.reportStatus ? "reported" : record.reportStatus,
      reportedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    if (admin && projection.exists && ["hide", "unhide"].includes(action)) {
      transaction.set(projectionRef, {hiddenByAdmin: action === "hide", feedbackText: action === "hide" ? "" : core.publicRatingFeedback(privateFeedback.exists ? privateFeedback.data().feedbackText : record.feedbackText || ""), updatedAt: FieldValue.serverTimestamp()}, {merge: true});
    }
    if (!existing.exists && !admin) {
      transaction.create(db.collection("supportTickets").doc(`feedback_${ratingId}_${actor.uid}`), {
        ticketId: `feedback_${ratingId}_${actor.uid}`, userId: actor.uid, ratingId, deliveryId: record.deliveryId,
        subject: "Feedback review requested", message: reason, category: "rating_moderation", status: "open", createdAt: FieldValue.serverTimestamp(),
      });
    }
    if (admin) {
      transaction.create(db.collection("adminAuditLogs").doc(), {
        adminUserId: actor.uid, actionType: `rating_${action}`, recordType: "driverRatings",
        recordId: ratingId, oldValue: {reportStatus: record.reportStatus || "clear", hiddenByAdmin: record.hiddenByAdmin === true},
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
  assertTipIntent(tipSnap.data(), intent);
  if (intent.status === "succeeded") {
    const tip = tipSnap.data();
    const delivery = await db.collection("deliveryRequests").doc(tip.deliveryId).get();
    const record = delivery.data() || {};
    assertTipParties(tip, record);
    if (!record.completedAt && !record.deliveredAt && !core.COMPLETED_STATUSES.has(text(record.deliveryState || record.status).toLowerCase())) {
      return {handled: true, ...await tipRefunds.refundCapturedTip({db, stripe, tipId: tipRef.id, reason: "not_completed", actorId: "stripe_webhook"})};
    }
    return {handled: true, ...await finalizeTip(db, tipRef, tip, intent.id)};
  }
  await db.runTransaction(async (transaction) => {
    const current = await transaction.get(tipRef);
    if (["succeeded", "refund_pending", "refunded", "reversed"].includes(current.data().status)) return;
    transaction.set(tipRef, {status: intent.status, paymentStatus: intent.status, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
  });
  return {handled: true, status: intent.status};
}

async function tipReversalTarget(db, tipId, tipAmountPence, refundedPence) {
  if (!Number.isSafeInteger(refundedPence) || refundedPence < 0 || refundedPence > tipAmountPence) throw new Error("Invalid provider refund amount");
  const disputes = await db.collection("tipDisputes").where("tipId", "==", tipId).get();
  let total = refundedPence;
  for (const doc of disputes.docs) {
    const dispute = doc.data();
    if (dispute.status !== "lost") continue;
    if (!Number.isSafeInteger(dispute.amountPence) || dispute.amountPence <= 0 || dispute.amountPence > tipAmountPence) throw new Error("Invalid recorded dispute amount");
    total += dispute.amountPence;
  }
  return Math.min(tipAmountPence, total);
}

async function processStripeTipRefund(stripe, event) {
  const charge = event.data.object;
  const intentId = typeof charge.payment_intent === "string" ? charge.payment_intent : charge.payment_intent && charge.payment_intent.id;
  if (!intentId) return {handled: false};
  const intent = await stripe.paymentIntents.retrieve(intentId);
  if (!intent.metadata || intent.metadata.paymentType !== "delivery_tip") return {handled: false};
  const db = getFirestore();
  const tip = await db.collection("deliveryTips").doc(intent.metadata.tipId).get();
  if (!tip.exists) throw new Error("Tip refund record missing");
  assertTipIntent(tip.data(), intent);
  if (text(charge.currency).toUpperCase() !== "GBP" || charge.amount !== tip.data().amountPence) throw new Error("Tip refund currency/amount mismatch");
  const amountPence = await tipReversalTarget(db, tip.id, tip.data().amountPence, charge.amount_refunded);
  await tipRefunds.returnUnpaidTipAllocations({db, stripe, tipId: tip.id, amountPence});
  const result = await tipRefunds.reverseTipEarning({db, tipId: tip.id, amountPence,
    providerReference: charge.id, reason: "processor_reversal"});
  return {handled: true, ...result};
}

async function processStripeTipDispute(stripe, event) {
  const eventDispute = event.data.object;
  const dispute = await stripe.disputes.retrieve(eventDispute.id);
  const chargeId = typeof dispute.charge === "string" ? dispute.charge : dispute.charge && dispute.charge.id;
  if (!chargeId) throw new Error("Dispute charge missing");
  const charge = await stripe.charges.retrieve(chargeId);
  const intentId = typeof charge.payment_intent === "string" ? charge.payment_intent : charge.payment_intent && charge.payment_intent.id;
  if (!intentId) return {handled: false};
  const intent = await stripe.paymentIntents.retrieve(intentId);
  if (!intent.metadata || intent.metadata.paymentType !== "delivery_tip") return {handled: false};
  const db = getFirestore();
  const tip = await db.collection("deliveryTips").doc(intent.metadata.tipId).get();
  if (!tip.exists) throw new Error("Tip dispute record missing");
  assertTipIntent(tip.data(), intent);
  if (text(dispute.currency).toUpperCase() !== "GBP" || !Number.isSafeInteger(dispute.amount) || dispute.amount <= 0 || dispute.amount > tip.data().amountPence || charge.amount !== tip.data().amountPence) throw new Error("Tip dispute amount mismatch");
  const auditRef = db.collection("tipDisputes").doc(dispute.id);
  await auditRef.set({tipId: tip.id, riderId: tip.data().riderId, paymentIntentId: intent.id, chargeId,
    status: dispute.status, amountPence: dispute.amount, currency: "GBP", lastEventId: event.id,
    updatedAt: FieldValue.serverTimestamp()}, {merge: true});
  if (dispute.status !== "lost") return {handled: true, status: dispute.status};
  const refundPence = charge.amount_refunded || 0;
  const totalReversal = await tipReversalTarget(db, tip.id, tip.data().amountPence, refundPence);
  await tipRefunds.returnUnpaidTipAllocations({db, stripe, tipId: tip.id, amountPence: totalReversal});
  const result = await tipRefunds.reverseTipEarning({db, tipId: tip.id, amountPence: totalReversal, providerReference: dispute.id, reason: "processor_reversal"});
  await auditRef.set({reversalId: `tip_reversal_${tip.id}_${totalReversal}`, reconciledAt: FieldValue.serverTimestamp()}, {merge: true});
  return {handled: true, ...result};
}
async function repairRiderRatingFeedback(data, context) {
  const actor = requireAuth(context);
  const db = getFirestore();
  const cursors = data && data.cursors || {};
  const nextCursors = {};
  let published = 0; let rejected = 0;
  for (const field of ["riderId", "driverId"]) {
    if (cursors[field] === null) {
 nextCursors[field] = null; continue;
}
    let query = db.collection("driverRatings").where(field, "==", actor.uid).orderBy("__name__").limit(25);
    if (typeof cursors[field] === "string" && cursors[field]) query = query.startAfter(cursors[field]);
    const page = await query.get();
    for (const snapshot of page.docs) {
      const result = await db.runTransaction(async (tx) => {
        const original = await tx.get(snapshot.ref);
        const saved = original.data() || {};
        const deliveryId = text(saved.deliveryId);
        if (!deliveryId || deliveryId.includes("/")) return "rejected";
        const projectionRef = db.collection("publishedDriverRatings").doc(deliveryId);
        const privateRef = db.collection("ratingPrivateFeedback").doc(deliveryId);
        const [delivery, projection, privateFeedback] = await tx.getAll(db.collection("deliveryRequests").doc(deliveryId), projectionRef, privateRef);
        if (projection.exists) return "existing";
        let input; let parties;
        try {
          input = core.normalizeRatingInput({stars: saved.starRating, feedback: saved.feedbackText, feedbackTags: saved.feedbackTags});
          const ratedAt = saved.createdAt && saved.createdAt.toMillis ? saved.createdAt.toMillis() : 0;
          if (!ratedAt || ratedAt > Date.now()) return "rejected";
          const record = delivery.data() || {};
          parties = core.assertCompletedDelivery(record, text(saved.senderId || saved.customerId), ratedAt);
          if (parties.riderId !== actor.uid || text(saved.riderId || saved.driverId) !== actor.uid ||
              !["paid", "succeeded", "success"].includes(text(record.paymentStatus).toLowerCase()) ||
              record.isTest === true || record.testData === true || record.refunded === true || record.refundStatus === "refunded") return "rejected";
        } catch (_) {
 return "rejected";
}
        const publicRecord = {ratingId: original.id, originalRatingId: original.id, deliveryId,
          riderId: actor.uid, driverId: actor.uid, senderId: parties.senderId, customerId: parties.senderId,
          starRating: input.stars, feedbackText: saved.hiddenByAdmin === true ? "" : core.publicRatingFeedback(input.feedback),
          feedbackTags: input.feedbackTags.filter((tag) => !["Safety concern", "Damaged item"].includes(tag)),
          deliveryCategories: core.ratingCategories(delivery.data()), hiddenByAdmin: saved.hiddenByAdmin === true,
          createdAt: saved.createdAt, publishedAt: FieldValue.serverTimestamp()};
        tx.create(projectionRef, publicRecord);
        if (!privateFeedback.exists) {
tx.create(privateRef, {ratingId: original.id, deliveryId,
          senderId: parties.senderId, riderId: actor.uid, feedbackText: input.feedback, feedbackTags: input.feedbackTags,
          createdAt: saved.createdAt});
}
        return "published";
      });
      if (result === "published") published++;
      if (result === "rejected") rejected++;
    }
    nextCursors[field] = page.size === 25 ? page.docs[page.size - 1].id : null;
  }
  const hasMore = Object.values(nextCursors).some((value) => value !== null);
  if (!hasMore) {
await db.runTransaction(async (tx) => {
    const ratings = await tx.get(db.collection("publishedDriverRatings").where("riderId", "==", actor.uid));
    const profiles = await tx.getAll(...["riderProfiles", "riders", "driverPerformanceMetrics"].map((name) => db.collection(name).doc(actor.uid)));
    const names = [null, "oneStarCount", "twoStarCount", "threeStarCount", "fourStarCount", "fiveStarCount"];
    const stats = {ratingSum: 0, totalRatings: ratings.size, oneStarCount: 0, twoStarCount: 0, threeStarCount: 0, fourStarCount: 0, fiveStarCount: 0};
    for (const doc of ratings.docs) {
      const stars = doc.data().starRating;
      if (!Number.isInteger(stars) || stars < 1 || stars > 5) throw new Error("Published rating requires reconciliation");
      stats.ratingSum += stars; stats[names[stars]]++;
    }
    stats.averageRating = ratings.size ? Math.round(stats.ratingSum / ratings.size * 100) / 100 : 0;
    stats.rating = stats.averageRating;
    for (const profile of profiles) if (profile.exists) tx.set(profile.ref, stats, {merge: true});
  });
}
  return {published, rejected, cursors: nextCursors, hasMore};
}
exports.repairRiderRatingFeedback = functions.https.onCall(repairRiderRatingFeedback);
exports.processStripeTipDispute = processStripeTipDispute;

exports.refundDeliveryTip = (stripe) => functions.https.onCall(async (data, context) => {
  const actor = requireAuth(context);
  if (!isRatingAdmin(context)) throw new functions.https.HttpsError("permission-denied", "Support approval is required for a tip refund.");
  const reason = text(data && data.reason);
  if (!["duplicate_charge", "unauthorised_payment", "fraud", "serious_service_failure"].includes(reason)) {
    throw new functions.https.HttpsError("invalid-argument", "Choose an approved tip refund reason.");
  }
  return tipRefunds.refundCapturedTip({db: getFirestore(), stripe, tipId: text(data.tipId), reason, actorId: actor.uid});
});
exports.processStripeTipRefund = processStripeTipRefund;
exports.submitDeliveryRating = functions.https.onCall(submitRating);
exports.submitDeliveryTip = submitTip;
exports.reportRating = functions.https.onCall(reportRating);
exports.processStripeTipIntent = processStripeTipIntent;
exports._test = {repairRiderRatingFeedback, submitRating, reportRating, finalizeTip, resolveDelivery, assertTipIntent, assertTipParties};
