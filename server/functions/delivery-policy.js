/* eslint-disable max-len, require-jsdoc */
const functions = require("firebase-functions/v1");
const {riderCallable} = require("./rider-app-check");
const {senderPaymentCallable} = require("./sender-app-check");
const {getFirestore, FieldValue, Timestamp} = require("firebase-admin/firestore");
const core = require("./delivery-policy-core");
const communicationEngine = require("./communication-engine");
const rothLedger = require("./roth-ledger");

function requireAuth(context) {
  if (!context.auth || !context.auth.uid) {
    throw new functions.https.HttpsError("unauthenticated", "Sign in first.");
  }
  return context.auth.uid;
}

function text(value) {
  return `${value || ""}`.trim();
}

function assertSender(uid, delivery) {
  const sender = text(delivery.senderId || delivery.userId);
  if (!sender || sender !== uid) {
    throw new functions.https.HttpsError("permission-denied", "Only the sender can request this action.");
  }
}

function assertAssignedRider(uid, delivery) {
  const rider = text(delivery.riderId || delivery.assignedRiderId);
  if (!rider || rider !== uid) {
    throw new functions.https.HttpsError("permission-denied", "Only the assigned rider can request this action.");
  }
}

async function deliverySnapshot(transaction, deliveryId) {
  const ref = getFirestore().collection("deliveryRequests").doc(deliveryId);
  const snapshot = await transaction.get(ref);
  if (!snapshot.exists) {
    throw new functions.https.HttpsError("not-found", "Delivery not found.");
  }
  const delivery = {...snapshot.data(), id: snapshot.id};
  if (delivery.cancellationSettlementStatus) {
    throw new functions.https.HttpsError("failed-precondition", "Cancellation is being reconciled. Delivery actions are paused.");
  }
  return {ref, delivery};
}

function idempotencyRef(deliveryId, key) {
  return getFirestore()
      .collection("deliveryPolicyEvents")
      .doc(`${deliveryId}_${Buffer.from(key).toString("base64url")}`);
}

function policyPatch({state, event, evidenceId, extra = {}}) {
  return {
    state,
    status: state,
    deliveryStatus: state,
    deliveryStage: state,
    updatedAt: FieldValue.serverTimestamp(),
    policyEvidenceId: evidenceId,
    auditHistory: FieldValue.arrayUnion(event),
    ...extra,
  };
}

function recordRiderCompensation(transaction, db, financial) {
  const riderId = text(financial && financial.riderId);
  const amount = Number(financial && financial.riderCompensation || 0);
  if (!riderId || amount <= 0) return;
  const transactionId = `policy_${Buffer.from(financial.idempotencyKey).toString("base64url")}`;
  transaction.create(db.collection("riderEarningTransactions").doc(transactionId), {
    transactionId,
    deliveryId: financial.deliveryId,
    riderId,
    type: financial.chargeType === "no_show_fee" ? "no_show_compensation" : "cancellation_compensation",
    amount,
    currency: "GBP",
    status: "completed",
    idempotencyKey: financial.idempotencyKey,
    createdAt: FieldValue.serverTimestamp(),
  });
  transaction.set(db.collection("riderEarnings").doc(riderId), {
    availableBalance: FieldValue.increment(amount),
    lifetimeEarnings: FieldValue.increment(amount),
    totalAmountEarned: FieldValue.increment(amount),
    waitingNoShowTotal: FieldValue.increment(
        financial.chargeType === "no_show_fee" ? amount : 0,
    ),
    adjustmentsTotal: FieldValue.increment(
        financial.chargeType === "no_show_fee" ? 0 : amount,
    ),
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
}

function clearRiderAssignment(transaction, db, riderId) {
  if (!riderId) return;
  for (const collection of ["riderPresence", "riders", "riderProfiles"]) {
    transaction.set(db.collection(collection).doc(riderId), {
      activeDeliveryId: FieldValue.delete(),
      currentDeliveryId: FieldValue.delete(),
      ...(collection === "riderPresence" ? {busy: false} : {}),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  }
}

function settlementRef(deliveryId) {
  return getFirestore().collection("deliveryCancellationSettlements").doc(deliveryId);
}

async function authoritativePaymentBreakdown(transaction, db, delivery) {
  const senderId = text(delivery.senderId || delivery.userId);
  const paymentSessionId = text(delivery.paymentSessionId);
  const invalid = () => new functions.https.HttpsError("failed-precondition", "Payment records require reconciliation before cancellation.");
  if (!paymentSessionId) throw invalid();
  const session = await transaction.get(db.collection("senderPaymentSessions").doc(paymentSessionId));
  if (!session.exists) throw invalid();
  const payment = session.data();
  if (payment.userId !== senderId || text(payment.currency).toUpperCase() !== "GBP" ||
      (payment.deliveryId && payment.deliveryId !== delivery.id)) throw invalid();
  const grossDeliveryTotal = payment.amountDue;
  const rothPaid = payment.rothAppliedAmount;
  const stripePaid = payment.remainingAmount;
  // Validate even before preview; missing/non-finite authority is never zero money.
  core.cancellationSettlement({grossDeliveryTotal, rothPaid, stripePaid, cancellationFee: 0});
  const paymentIntentId = text(payment.stripePaymentIntentId);
  if (stripePaid > 0 && (!paymentIntentId || paymentIntentId !== text(delivery.stripePaymentIntentId))) throw invalid();
  let senderEmail = text(payment.userEmail);
  if (rothPaid > 0) {
    const debitId = text(payment.rothDebitTransactionId) || `wallet_delivery_${paymentSessionId}`;
    const debit = await transaction.get(db.collection("walletTransactions").doc(debitId));
    const data = debit.exists ? debit.data() : {};
    if (data.uid !== senderId || data.status !== "completed" ||
        data.relatedEntityId !== delivery.id || Number(data.amount) !== -Number(rothPaid) ||
        data.balanceType !== "rothCredit") throw invalid();
    senderEmail = text(data.userEmail || data.normalizedEmail);
    if (!senderEmail) throw invalid();
  }
  return {grossDeliveryTotal, stripePaid, rothPaid, senderEmail,
    paymentSessionId, stripePaymentIntentId: paymentIntentId || null,
    paymentStatus: text(payment.paymentStatus || payment.status)};
}

async function reconcileStripeCancellation(stripe, settlement) {
  const breakdown = settlement.breakdown || settlement;
  const amountPence = Math.round(Number(breakdown.stripeRefund) * 100);
  const paidPence = Math.round(Number(breakdown.stripePaid) * 100);
  const retainedPence = paidPence - amountPence;
  if (![amountPence, paidPence, retainedPence].every((n) => Number.isSafeInteger(n) && n >= 0)) {
    throw new Error("Invalid Stripe cancellation allocation.");
  }
  if (paidPence === 0) return {status: "not_required", refundedPence: 0};
  const paymentIntentId = text(settlement.stripePaymentIntentId);
  if (!paymentIntentId) throw new Error("Stripe payment reference is missing.");
  const options = {timeout: 10000, maxNetworkRetries: 1};
  let intent = await stripe.paymentIntents.retrieve(paymentIntentId, {expand: ["latest_charge"]}, options);
  const metadata = intent.metadata || {};
  const ownerId = text(metadata.userId || metadata.senderId || metadata.uid);
  if (!ownerId || ownerId !== settlement.senderId) throw new Error("Stripe payment ownership mismatch.");
  if (text(intent.currency).toLowerCase() !== "gbp") throw new Error("Stripe payment currency mismatch.");
  if (settlement.paymentSessionId && metadata.paymentSessionId !== settlement.paymentSessionId) {
    throw new Error("Stripe payment session mismatch.");
  }
  if (Number(intent.amount) !== paidPence) throw new Error("Stripe payment amount mismatch.");
  if (intent.status === "requires_capture") {
    if (retainedPence > 0) {
      intent = await stripe.paymentIntents.capture(paymentIntentId, {amount_to_capture: retainedPence}, {
        ...options, idempotencyKey: `cancel_capture_${settlement.deliveryId}_${retainedPence}`,
      });
      if (intent.status !== "succeeded" || Number(intent.amount_received) !== retainedPence) {
        throw new Error("Stripe capture is not yet settled.");
      }
      return {status: "released_after_partial_capture", refundedPence: amountPence};
    }
    intent = await stripe.paymentIntents.cancel(paymentIntentId, {}, {
      ...options, idempotencyKey: `cancel_intent_${settlement.deliveryId}`,
    });
  } else if (["requires_confirmation", "requires_payment_method", "requires_action"].includes(intent.status)) {
    if (retainedPence > 0) throw new Error("Unfunded Stripe payment cannot retain the cancellation fee.");
    intent = await stripe.paymentIntents.cancel(paymentIntentId, {}, {
      ...options, idempotencyKey: `cancel_intent_${settlement.deliveryId}`,
    });
  }
  if (intent.status === "canceled") {
    if (retainedPence > 0) throw new Error("Canceled Stripe authorization cannot retain the cancellation fee.");
    return {status: "already_released", refundedPence: paidPence};
  }
  if (intent.status !== "succeeded") throw new Error("Stripe payment is not in a refundable state.");
  const received = Number(intent.amount_received);
  if (!Number.isSafeInteger(received) || received < retainedPence || received > paidPence) {
    throw new Error("Stripe captured amount does not reconcile.");
  }
  // A prior partial capture already released paidPence - received. Never refund that again.
  const refundTarget = received - retainedPence;
  const refunds = await stripe.refunds.list({payment_intent: paymentIntentId, limit: 100}, options);
  if (refunds.has_more) throw new Error("Stripe refund history requires reconciliation.");
  const completed = refunds.data.filter((refund) => refund.status === "succeeded");
  const refunded = completed.reduce((sum, refund) => sum + Number(refund.amount), 0);
  if (refunded > refundTarget) throw new Error("Stripe payment has an ambiguous excess prior refund.");
  if (refunds.data.some((refund) => !["succeeded", "failed", "canceled"].includes(refund.status))) {
    throw new Error("Stripe refund is pending; settlement will retry.");
  }
  if (refunded < refundTarget) {
    // The same observed refund history yields the same key across concurrent/time-out retries.
    // Failed refunds change the history and permit a new attempt; successful ones reduce the delta.
    const history = require("node:crypto").createHash("sha256")
        .update(refunds.data.map((refund) => `${refund.id}:${refund.status}`).sort().join("|"))
        .digest("hex").slice(0, 24);
    const refund = await stripe.refunds.create({
      payment_intent: paymentIntentId, amount: refundTarget - refunded,
      metadata: {cancellationDeliveryId: settlement.deliveryId},
    }, {...options, idempotencyKey: `cancel_refund_${settlement.deliveryId}_${refundTarget}_${history}`});
    if (refund.status !== "succeeded") throw new Error("Stripe refund is pending or failed; settlement will retry.");
  }
  return {status: refunded === refundTarget ? "already_refunded" : "refunded", refundedPence: amountPence};
}

async function restoreCancellationRoth(settlement) {
  const amount = Number(settlement.breakdown && settlement.breakdown.rothRestoration || settlement.rothRestoration || 0);
  if (amount <= 0) return {status: "not_required"};
  const result = await rothLedger.recordRothMovement({
    userId: settlement.senderId,
    userEmail: settlement.senderEmail || null,
    uid: settlement.senderId,
    amount,
    balanceType: rothLedger.BALANCE_TYPES.rothCredit,
    type: rothLedger.TRANSACTION_TYPES.refundCredit,
    reason: "Roth restored after delivery cancellation.",
    relatedEntityId: settlement.deliveryId,
    transactionId: `cancellation_roth_${settlement.deliveryId}`,
    idempotencyKey: `cancellation_roth_${settlement.deliveryId}`,
    metadata: {source: "delivery_cancellation", deliveryId: settlement.deliveryId},
  });
  return {status: "restored", transactionId: result.transactionId};
}

async function emitCancellationNotification(payload) {
  const id = await communicationEngine.emitNotification({...payload, retryExisting: true});
  const notification = await getFirestore().collection("notifications").doc(id).get();
  if (notification.exists && ["pending", "failed"].includes(notification.data().pushDeliveryStatus)) {
    throw new Error("Cancellation notification push requires retry.");
  }
  return id;
}

async function deliverCancellationNotifications(settlement) {
  const db = getFirestore();
  const ref = settlementRef(settlement.deliveryId);
  if (settlement.notificationStatus === "completed") return true;
  try {
    await emitCancellationNotification({
      recipientId: "circum-support", recipientRole: "admin", type: "delivery_cancelled",
      title: "Delivery cancelled", body: `Delivery ${settlement.deliveryId} was cancelled and financially settled.`,
      data: {deliveryId: settlement.deliveryId}, dedupeKey: `${settlement.deliveryId}:cancelled:admin`,
    });
    if (settlement.riderId) {
      await emitCancellationNotification({
        recipientId: settlement.riderId, recipientRole: "rider", type: "delivery_cancelled",
        title: "Delivery cancelled", body: "A delivery assigned to you was cancelled.",
        data: {deliveryId: settlement.deliveryId}, dedupeKey: `${settlement.deliveryId}:cancelled:rider:${settlement.riderId}`,
      });
    }
    await ref.set({notificationStatus: "completed", notificationCompletedAt: FieldValue.serverTimestamp()}, {merge: true});
    return true;
  } catch (error) {
    await db.collection("deliveryCancellationSettlements").doc(settlement.deliveryId).set({
      notificationStatus: "pending_retry",
      notificationLastError: text(error && (error.code || error.message)) || "notification_failed",
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    return false;
  }
}

async function reconcileCancellationSettlementUnlocked(stripe, deliveryId) {
  const db = getFirestore();
  const ref = settlementRef(deliveryId);
  let snapshot = await ref.get();
  if (!snapshot.exists) throw new Error("Cancellation settlement was not found.");
  let settlement = {deliveryId, ...snapshot.data()};
  if (settlement.status !== "settled") {
    const stripeResult = await reconcileStripeCancellation(stripe, settlement);
    await ref.set({stripeStatus: stripeResult.status, stripeRefundedPence: stripeResult.refundedPence, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
    const rothResult = await restoreCancellationRoth(settlement);
    await ref.set({rothStatus: rothResult.status, rothTransactionId: rothResult.transactionId || null, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
    await db.runTransaction(async (transaction) => {
      const [currentSettlement, deliverySnapshot] = await Promise.all([
        transaction.get(ref),
        transaction.get(db.collection("deliveryRequests").doc(deliveryId)),
      ]);
      const current = currentSettlement.data() || {};
      if (current.status === "settled") return;
      if (!deliverySnapshot.exists) throw new Error("Delivery was removed during cancellation settlement.");
      const assignments = current.riderId ? await Promise.all(
          ["riderPresence", "riders", "riderProfiles"].map((name) =>
            transaction.get(db.collection(name).doc(current.riderId))),
      ) : [];
      recordRiderCompensation(transaction, db, current.financial);
      for (const assigned of assignments) {
        const data = assigned.exists ? assigned.data() : {};
        const activeId = text(data.activeDeliveryId || data.currentDeliveryId);
        if (activeId === deliveryId) {
transaction.set(assigned.ref, {
          activeDeliveryId: FieldValue.delete(), currentDeliveryId: FieldValue.delete(),
          busy: false, updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
}
      }
      transaction.update(deliverySnapshot.ref, policyPatch({
        state: "cancelled_by_sender",
        event: current.event,
        evidenceId: current.evidenceId,
        extra: {
          cancellationSettlementStatus: "settled",
          cancellationPolicy: current.decision,
          cancellationFinancial: current.financial,
          cancellationSettlement: current.breakdown,
          cancelledAt: FieldValue.serverTimestamp(),
          cancelledBy: current.senderId,
          cancellationReason: current.cancellationReason,
          matchingStatus: "cancelled", dispatchStatus: "cancelled",
          broadcastBlocked: true, broadcastBlockReason: "sender_cancelled",
          active: false, archived: true, removedFromActiveQueues: true,
          previousLifecycleState: current.previousLifecycleState,
          refundReviewRequired: false, refundReviewStatus: "settled_automatically",
        },
      }));
      transaction.set(ref, {status: "settled", settledAt: FieldValue.serverTimestamp(), notificationStatus: "pending"}, {merge: true});
    });
    snapshot = await ref.get();
    settlement = {deliveryId, ...snapshot.data()};
  }
  const notificationsComplete = await deliverCancellationNotifications(settlement);
  return {...settlement, success: true, notificationsComplete};
}

// A short renewable-by-retry lease keeps two workers from interleaving financial side effects.
async function reconcileCancellationSettlement(stripe, deliveryId) {
  const db = getFirestore();
  const ref = settlementRef(deliveryId);
  const owner = require("node:crypto").randomUUID();
  await db.runTransaction(async (transaction) => {
    const snap = await transaction.get(ref);
    if (!snap.exists) throw new Error("Cancellation settlement was not found.");
    if (Number(snap.data().leaseExpiresAt || 0) > Date.now()) {
      throw new Error("Cancellation reconciliation is already running.");
    }
    transaction.update(ref, {leaseOwner: owner, leaseExpiresAt: Date.now() + 120000});
  });
  try {
    return await reconcileCancellationSettlementUnlocked(stripe, deliveryId);
  } finally {
    await db.runTransaction(async (transaction) => {
      const snap = await transaction.get(ref);
      if (snap.exists && snap.data().leaseOwner === owner) {
        transaction.update(ref, {leaseOwner: FieldValue.delete(), leaseExpiresAt: FieldValue.delete()});
      }
    });
  }
}

function cancellationQuoteToken(deliveryId, breakdown) {
  return require("node:crypto").createHash("sha256")
      .update(JSON.stringify({deliveryId, breakdown})).digest("hex");
}

async function recordCancellationFailure(deliveryId, error) {
  const reviewRequired = /mismatch|ambiguous|cannot retain|captured amount|reference is missing|history requires/.test(text(error && error.message));
  const db = getFirestore(); const ref = settlementRef(deliveryId);
  await db.runTransaction(async (transaction) => {
    const snap = await transaction.get(ref);
    if (!snap.exists) return;
    transaction.update(ref, {
      ...(reviewRequired && snap.data().status !== "settled" ? {status: "manual_review"} : {}),
      lastErrorCode: text(error && (error.code || error.type)) || (reviewRequired ? "payment_authority_review" : "reconciliation_failed"),
      lastAttemptAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
    });
  });
}

exports.requestSenderCancellation = (stripe) => senderPaymentCallable(async (data, context) => {
  const uid = requireAuth(context);
  const deliveryId = text(data.deliveryId || data.requestId);
  const cancellationReason = text(data.reason || data.cancellationReason) || "Sender requested cancellation";
  const idempotencyKey = text(data.idempotencyKey || `${deliveryId}:sender_cancel:${uid}`);
  if (!deliveryId) throw new functions.https.HttpsError("invalid-argument", "deliveryId is required.");

  const db = getFirestore();
  const result = await db.runTransaction(async (transaction) => {
    const canonicalSettlementRef = settlementRef(deliveryId);
    const existingSettlement = await transaction.get(canonicalSettlementRef);
    if (existingSettlement.exists) {
      const existingData = existingSettlement.data() || {};
      if (existingData.senderId !== uid) {
        throw new functions.https.HttpsError("permission-denied", "Only the sender can request this action.");
      }
      if (existingData.status === "manual_review") {
        throw new functions.https.HttpsError("failed-precondition", "Payment records require support reconciliation.");
      }
      return {success: true, reconciliationRequired: true};
    }
    const idemRef = idempotencyRef(deliveryId, idempotencyKey);
    const {ref, delivery} = await deliverySnapshot(transaction, deliveryId);
    assertSender(uid, delivery);
    const now = Date.now();
    const previousLifecycleState = text(delivery.state || delivery.deliveryStage || delivery.deliveryStatus || delivery.status);
    const decision = core.cancellationDecision({
      delivery,
      state: delivery.state || delivery.status,
      serverNow: now,
    });
    if (!decision.canCancel) {
      return {success: false, decision};
    }
    const payment = await authoritativePaymentBreakdown(transaction, db, delivery);
    let breakdown;
    try {
      breakdown = core.cancellationSettlement({
        ...payment,
        cancellationFee: decision.feeAmount,
        riderCompensation: decision.riderCompensation,
        circumRetained: decision.platformRetainedAmount,
      });
    } catch (error) {
      throw new functions.https.HttpsError("failed-precondition", "Payment records require reconciliation before cancellation.");
    }

    if (data.quoteToken !== cancellationQuoteToken(deliveryId, breakdown)) {
      return {success: false, decision: {...decision,
        userFacingMessage: "Cancellation terms must be reviewed again before confirming."}};
    }

    const financial = decision.feeApplies ? core.financialAction({
      idempotencyKey: `${deliveryId}:sender_cancellation`,
      chargeType: "cancellation_fee",
      amount: decision.feeAmount,
      riderCompensation: decision.riderCompensation,
      platformRetainedAmount: decision.platformRetainedAmount,
      deliveryId,
      riderId: delivery.riderId || delivery.assignedRiderId,
      actorId: uid,
      actorType: "sender",
      reason: decision.cancellationType,
      serverNow: now,
    }) : null;
    const evidence = core.evidencePackage({
      deliveryId,
      actorId: uid,
      actorType: "sender",
      idempotencyKey,
      delivery,
      policyDecision: decision,
      serverNow: now,
    });
    const evidenceRef = db.collection("deliveryPolicyEvidence").doc();
    transaction.set(evidenceRef, evidence);
    const event = {
      type: "sender_cancellation_requested", deliveryId, actorId: uid, actorType: "sender",
      decision, financial, evidenceId: evidenceRef.id, createdAt: now,
    };
    const result = {success: true, decision, financial, breakdown, evidenceId: evidenceRef.id, createdAt: now,
      deliveryId, riderId: text(delivery.riderId || delivery.assignedRiderId) || null,
      senderId: uid, senderEmail: payment.senderEmail,
      paymentSessionId: payment.paymentSessionId,
      stripePaymentIntentId: payment.stripePaymentIntentId,
      paymentStatus: payment.paymentStatus, cancellationReason, previousLifecycleState, event};
    transaction.set(canonicalSettlementRef, {...result, status: "pending_reconciliation", notificationStatus: "pending", updatedAt: FieldValue.serverTimestamp()});
    transaction.set(idemRef, {deliveryId, settlementId: canonicalSettlementRef.id, status: "pending_reconciliation", createdAt: FieldValue.serverTimestamp()});
    transaction.update(ref, {
      cancellationSettlementStatus: "pending_reconciliation",
      cancellationRequestedAt: FieldValue.serverTimestamp(),
      cancellationRequestedBy: uid,
      broadcastBlocked: true,
      broadcastBlockReason: "sender_cancellation_pending",
      matchingStatus: "blocked",
      dispatchStatus: "blocked",
      updatedAt: FieldValue.serverTimestamp(),
    });
    transaction.set(db.collection("deliveryTimeline").doc(), event);
    return result;
  });
  if (!result.success) return result;
  try {
    return await reconcileCancellationSettlement(stripe, deliveryId);
  } catch (error) {
    await recordCancellationFailure(deliveryId, error);
    throw new functions.https.HttpsError(
        "unavailable",
        "Cancellation is being reconciled safely. Refresh shortly before trying again.",
    );
  }
}, {secrets: ["STRIPE_SECRET_KEY"]});

exports.reconcilePendingSenderCancellations = (stripe) => functions
    .runWith({secrets: ["STRIPE_SECRET_KEY"]}).pubsub
    .schedule("every 5 minutes")
    .onRun(async () => {
      const collection = getFirestore().collection("deliveryCancellationSettlements");
      const [financialPending, notificationPending] = await Promise.all([
        collection.where("status", "==", "pending_reconciliation").limit(50).get(),
        collection.where("notificationStatus", "in", ["pending", "pending_retry"]).limit(50).get(),
      ]);
      const pending = new Map();
      for (const doc of [...financialPending.docs, ...notificationPending.docs]) pending.set(doc.id, doc);
      const results = [];
      for (const doc of pending.values()) {
        const data = doc.data() || {};
        if (data.status === "manual_review" || data.status === "settled" && data.notificationStatus === "completed") continue;
        try {
          await reconcileCancellationSettlement(stripe, doc.id);
          results.push({deliveryId: doc.id, status: "reconciled"});
        } catch (error) {
          await recordCancellationFailure(doc.id, error);
          results.push({deliveryId: doc.id, status: "retry_pending"});
        }
      }
      return {processed: results.length, results};
    });

exports.previewSenderCancellation = senderPaymentCallable(async (data, context) => {
  const uid = requireAuth(context);
  const deliveryId = text(data.deliveryId || data.requestId);
  if (!deliveryId) throw new functions.https.HttpsError("invalid-argument", "deliveryId is required.");
  const db = getFirestore();
  const ref = db.collection("deliveryRequests").doc(deliveryId);
  const preview = await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (!snapshot.exists) throw new functions.https.HttpsError("not-found", "Delivery not found.");
    const delivery = {...snapshot.data(), id: snapshot.id};
    assertSender(uid, delivery);
    const decision = core.cancellationDecision({delivery, state: delivery.state || delivery.status, serverNow: Date.now()});
    if (!decision.canCancel) return {decision, breakdown: null};
    const payment = await authoritativePaymentBreakdown(transaction, db, delivery);
    try {
      return {decision, breakdown: core.cancellationSettlement({
        ...payment,
        cancellationFee: decision.feeAmount,
        riderCompensation: decision.riderCompensation,
        circumRetained: decision.platformRetainedAmount,
      })};
    } catch (error) {
      throw new functions.https.HttpsError("failed-precondition", "Payment records require reconciliation before cancellation.");
    }
  });
  const {decision, breakdown} = preview;
  return {
    success: true,
    decision,
    cancellationFee: breakdown && breakdown.cancellationFee || decision.feeAmount,
    feeAmount: decision.feeAmount,
    amount: decision.feeAmount,
    currency: "GBP",
    backendReason: decision.userFacingMessage || decision.adminFacingReason || "",
    reason: decision.cancellationType,
    amountToChargeOrRefund: decision.feeApplies ? decision.feeAmount : 0,
    riderCompensation: breakdown && breakdown.riderCompensation || decision.riderCompensation,
    circumRetained: breakdown && breakdown.circumRetained || decision.platformRetainedAmount,
    stripeRefund: breakdown && breakdown.stripeRefund || 0,
    rothRestoration: breakdown && breakdown.rothRestoration || 0,
    totalRefundValue: breakdown && breakdown.totalRefundValue || 0,
    refundAmount: breakdown && breakdown.totalRefundValue || 0,
    finalRefund: breakdown && breakdown.totalRefundValue || 0,
    allocationPolicy: breakdown && breakdown.allocationPolicy || "stripe_first",
    quoteToken: breakdown ? cancellationQuoteToken(deliveryId, breakdown) : null,
    canCancel: decision.canCancel,
    requiresAdminReview: decision.requiresAdminReview,
    interventionAvailable: !decision.canCancel,
  };
});

exports._test = {
  reconcileStripeCancellation,
  authoritativePaymentBreakdown,
  restoreCancellationRoth,
  cancellationQuoteToken,
  reconcileCancellationSettlement,
};

exports.recordRiderArrival = riderCallable(async (data, context) => {
  const uid = requireAuth(context);
  const deliveryId = text(data.deliveryId);
  if (!deliveryId) throw new functions.https.HttpsError("invalid-argument", "deliveryId is required.");
  const phase = data.phase === "dropoff" ? "dropoff" : "pickup";
  const db = getFirestore();
  return db.runTransaction(async (transaction) => {
    const {ref, delivery} = await deliverySnapshot(transaction, deliveryId);
    assertAssignedRider(uid, delivery);
    const existingArrival = phase === "dropoff" ?
      delivery.dropoffArrivedAt : delivery.pickupArrivedAt;
    if (existingArrival && delivery.waiting && delivery.waiting.phase === phase) {
      return {
        success: true,
        duplicate: true,
        decision: {
          state: phase === "dropoff" ? "arrived_at_dropoff" : "arrived_at_pickup",
          waiting: delivery.waiting,
        },
      };
    }
    const now = Date.now();
    const decision = core.validateArrival({
      deliveryId,
      riderId: uid,
      delivery,
      phase,
      location: data.location || null,
      gpsAccuracyMeters: data.gpsAccuracyMeters,
      serverNow: now,
    });
    if (!decision.accepted) return {success: false, decision};
    const event = decision.auditEvent;
    const field = phase === "dropoff" ? "dropoffArrivedAt" : "pickupArrivedAt";
    transaction.update(ref, policyPatch({
      state: decision.state,
      event,
      evidenceId: delivery.policyEvidenceId || null,
      extra: {
        status: decision.state,
        deliveryStatus: decision.state,
        deliveryStage: decision.state,
        // Persist the same server-owned instant used by waiting/no-show deadlines.
        arrivedAt: Timestamp.fromMillis(decision.arrivedAt),
        [field]: Timestamp.fromMillis(decision.arrivedAt),
        arrivalLocation: decision.arrivalLocation || null,
        arrivalDistanceMeters: decision.distanceMeters || null,
        arrivalGpsAccuracyMeters: decision.gpsAccuracyMeters || null,
        waiting: decision.waiting,
        pendingNotification: {
          recipient: phase === "dropoff" ? "receiver" : "sender",
          message: phase === "dropoff" ? "Your rider is outside." : "Your rider is outside waiting for collection.",
          createdAt: now,
          triggeredByState: decision.state,
        },
      },
    }));
    return {success: true, decision};
  });
});

exports.recordArrivalZoneCheck = riderCallable(async (data, context) => {
  const uid = requireAuth(context);
  const deliveryId = text(data.deliveryId);
  if (!deliveryId) throw new functions.https.HttpsError("invalid-argument", "deliveryId is required.");
  const phase = data.phase === "dropoff" ? "dropoff" : "pickup";
  const db = getFirestore();
  return db.runTransaction(async (transaction) => {
    const {ref, delivery} = await deliverySnapshot(transaction, deliveryId);
    assertAssignedRider(uid, delivery);
    const now = Date.now();
    const decision = core.geofenceReentryDecision({
      deliveryId,
      riderId: uid,
      delivery,
      phase,
      location: data.location || null,
      gpsAccuracyMeters: data.gpsAccuracyMeters,
      serverNow: now,
    });
    const extra = decision.waitingPaused ? {
      "waiting.paused": true,
      "waiting.pausedAt": now,
      "leftArrivalZoneAt": now,
      "lastKnownDistanceMeters": decision.lastKnownDistanceMeters || null,
      "arrivalGpsAccuracyMeters": decision.gpsAccuracyMeters || null,
    } : {
      "waiting.paused": false,
      "waiting.resumedAt": decision.reenteredArrivalZoneAt || now,
      "reenteredArrivalZoneAt": decision.reenteredArrivalZoneAt || null,
      "lastKnownDistanceMeters": decision.lastKnownDistanceMeters || null,
    };
    transaction.update(ref, {
      ...extra,
      updatedAt: FieldValue.serverTimestamp(),
      auditHistory: FieldValue.arrayUnion(decision.auditEvent),
    });
    return {success: true, decision};
  });
});

exports.recordCustomerArrivalResponse = senderPaymentCallable(async (data, context) => {
  const uid = requireAuth(context);
  const deliveryId = text(data.deliveryId);
  if (!deliveryId) throw new functions.https.HttpsError("invalid-argument", "deliveryId is required.");
  const db = getFirestore();
  return db.runTransaction(async (transaction) => {
    const {ref, delivery} = await deliverySnapshot(transaction, deliveryId);
    assertSender(uid, delivery);
    const now = Date.now();
    const decision = core.customerResponseDecision({deliveryId, senderId: uid, delivery, response: data.response, serverNow: now});
    if (!decision.accepted) return {success: false, decision};
    transaction.update(ref, {
      customerArrivalResponses: FieldValue.arrayUnion(decision.auditEvent),
      customerWaitExtensions: FieldValue.increment(decision.extensionGranted ? 1 : 0),
      updatedAt: FieldValue.serverTimestamp(),
      auditHistory: FieldValue.arrayUnion(decision.auditEvent),
    });
    return {success: true, decision};
  });
});

exports.reportWaitingContext = riderCallable(async (data, context) => {
  const uid = requireAuth(context);
  const deliveryId = text(data.deliveryId);
  const waitingType = text(data.type);
  const waitingNote = text(data.note);
  const idempotencyKey = text(data.idempotencyKey ||
    `${deliveryId}:waiting_context:${uid}:${waitingType}:${waitingNote}`);
  if (!deliveryId) throw new functions.https.HttpsError("invalid-argument", "deliveryId is required.");
  if (!waitingType) throw new functions.https.HttpsError("invalid-argument", "type is required.");
  const db = getFirestore();
  return db.runTransaction(async (transaction) => {
    const idemRef = idempotencyRef(deliveryId, idempotencyKey);
    const existing = await transaction.get(idemRef);
    if (existing.exists) return {...existing.data(), duplicate: true};
    const {ref, delivery} = await deliverySnapshot(transaction, deliveryId);
    assertAssignedRider(uid, delivery);
    const now = Date.now();
    const decision = core.waitingContextDecision({
      deliveryId,
      riderId: uid,
      type: waitingType,
      note: waitingNote,
      serverNow: now,
    });
    const result = {success: true, decision, createdAt: now};
    transaction.set(idemRef, result);
    transaction.update(ref, {
      waitingContextState: decision.state,
      requiresAdminReview: decision.requiresAdminReview,
      updatedAt: FieldValue.serverTimestamp(),
      auditHistory: FieldValue.arrayUnion(decision.auditEvent),
    });
    return result;
  });
});

exports.markRiderNoShow = riderCallable(async (data, context) => {
  const uid = requireAuth(context);
  const deliveryId = text(data.deliveryId);
  const idempotencyKey = text(data.idempotencyKey || `${deliveryId}:no_show:${uid}`);
  if (!deliveryId) throw new functions.https.HttpsError("invalid-argument", "deliveryId is required.");
  const db = getFirestore();
  return db.runTransaction(async (transaction) => {
    const idemRef = idempotencyRef(deliveryId, idempotencyKey);
    const existing = await transaction.get(idemRef);
    if (existing.exists) return {...existing.data(), duplicate: true};
    const {ref, delivery} = await deliverySnapshot(transaction, deliveryId);
    assertAssignedRider(uid, delivery);
    const now = Date.now();
    const decision = core.noShowDecision({deliveryId, riderId: uid, delivery, serverNow: now});
    if (!decision.allowed) return {success: false, decision};
    const financial = core.financialAction({
      idempotencyKey,
      chargeType: "no_show_fee",
      amount: decision.feeAmount,
      riderCompensation: decision.riderCompensation,
      platformRetainedAmount: decision.platformRetainedAmount,
      deliveryId,
      riderId: uid,
      actorId: uid,
      actorType: "rider",
      reason: "sender_no_show_after_free_wait",
      startTime: decision.waitStartedAt,
      endTime: now,
      serverNow: now,
    });
    const evidence = core.evidencePackage({
      deliveryId,
      riderId: uid,
      actorId: uid,
      actorType: "rider",
      idempotencyKey,
      delivery,
      policyDecision: decision,
      serverNow: now,
    });
    const evidenceRef = db.collection("deliveryPolicyEvidence").doc();
    const event = {...decision.auditEvent, financial, evidenceId: evidenceRef.id};
    transaction.set(evidenceRef, evidence);
    transaction.set(idemRef, {success: true, decision, financial, evidenceId: evidenceRef.id, createdAt: now});
    recordRiderCompensation(transaction, db, financial);
    clearRiderAssignment(transaction, db, uid);
    transaction.update(ref, policyPatch({
      state: "sender_no_show_pickup",
      event,
      evidenceId: evidenceRef.id,
      extra: {
        noShowPolicy: decision,
        noShowFinancial: financial,
        noShowMarkedAt: FieldValue.serverTimestamp(),
      },
    }));
    return {success: true, decision, financial, evidenceId: evidenceRef.id};
  });
});

exports._core = core;
