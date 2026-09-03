/* eslint-disable max-len, require-jsdoc */
const functions = require("firebase-functions/v1");
const {getFirestore} = require("firebase-admin/firestore");
const {getMessaging} = require("firebase-admin/messaging");
const {resolveStripeRuntimeConfig} = require("./stripe-config");
const {senderPaymentCallable} = require("./sender-app-check");
let cachedStripe = null;

function getStripeClient() {
  if (!cachedStripe) {
    const runtimeConfig = resolveStripeRuntimeConfig();
    cachedStripe = require("stripe")(runtimeConfig.secretKey);
    cachedStripe._circumStripeMode = runtimeConfig.mode;
  }
  return cachedStripe;
}

const stripe = new Proxy({}, {
  get(_target, property) {
    return getStripeClient()[property];
  },
});
const iris = require("./iris-core");
const {
  DISCREPANCY_REASONS,
  buildAdjustment,
  isMaterialDiscrepancy,
} = require("./delivery-adjustment-core");

async function notifyUser(userId, title, body, data) {
  if (!userId) return;
  for (const collection of ["users", "riders"]) {
    const snapshot = await getFirestore().collection(collection).doc(userId).get();
    const token = snapshot.exists && snapshot.data().fcmToken;
    if (!token) continue;
    await getMessaging().send({
      token,
      notification: {title, body},
      data: Object.fromEntries(Object.entries(data).map(([key, value]) => [key, String(value)])),
    }).catch((error) => console.error("Adjustment notification failed", error));
    return;
  }
}

async function bookingReference(db, requestId) {
  const direct = db.collection("deliveryRequests").doc(requestId);
  const directSnapshot = await direct.get();
  if (directSnapshot.exists) return directSnapshot;
  const query = await db.collection("deliveryRequests")
      .where("requestId", "==", requestId).limit(1).get();
  return query.empty ? null : query.docs[0];
}

exports.reportLoadDiscrepancy = functions.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Authentication required.");
  const {requestId, reason, evidencePhotos = [], observedWeightKg, observedDescription, observedVehicleType, riderNotes, dimensions} = data;
  if (!requestId || !DISCREPANCY_REASONS.includes(reason)) throw new functions.https.HttpsError("invalid-argument", "A booking and supported discrepancy reason are required.");
  if (!Array.isArray(evidencePhotos) || evidencePhotos.length === 0) throw new functions.https.HttpsError("invalid-argument", "At least one evidence photo is required.");

  const db = getFirestore();
  const bookingSnapshot = await bookingReference(db, requestId);
  if (!bookingSnapshot) throw new functions.https.HttpsError("not-found", "Booking not found.");
  const requestRef = bookingSnapshot.ref;
  const booking = bookingSnapshot.data();
  const riderId = context.auth.uid;
  if (![booking.riderId, booking.driverId, booking.assignedDriverId].includes(riderId)) throw new functions.https.HttpsError("permission-denied", "Only the assigned rider can report this discrepancy.");
  if (booking.status === "awaiting_sender_adjustment") throw new functions.https.HttpsError("failed-precondition", "This booking already has a pending adjustment.");

  const originalWeightKg = Number(booking.finalWeightUsed || booking.finalChargeableWeight || booking.confirmedWeightKg || booking.weightKg || 0);
  const description = observedDescription || booking.packageDescription || booking.description || "Parcel";
  const recalculated = iris.classifyIris({
    description: dimensions ? `${description}; dimensions ${dimensions}` : description,
    declaredWeightText: observedWeightKg ? `${observedWeightKg} kg` : `${originalWeightKg} kg`,
    distanceMiles: booking.distanceMiles || booking.estimatedDistanceMiles || 0,
    express: booking.urgent === true || booking.serviceLevel === "express",
    vehicleType: observedVehicleType || booking.vehicleType || booking.vehicle,
  });
  const previousVehicle = `${booking.vehicleType || booking.vehicle || ""}`.toLowerCase();
  const recalculatedVehicle = `${observedVehicleType || (recalculated.recommendation && recalculated.recommendation.vehicleType) || ""}`.toLowerCase();
  const vehicleSuitabilityChanged = Boolean(recalculatedVehicle && recalculatedVehicle !== previousVehicle);
  if (!isMaterialDiscrepancy({reason, originalWeightKg, observedWeightKg, vehicleSuitabilityChanged})) throw new functions.https.HttpsError("failed-precondition", "The reported difference does not meet the material adjustment threshold.");
  const revisedQuote = Number(recalculated.recommendation && recalculated.recommendation.estimatedPrice || booking.price || booking.quote || 0);
  const originalQuote = Number(booking.paidAmount || booking.price || booking.quote || 0);
  const senderId = booking.senderId || booking.userId;
  const adjustmentRef = db.collection("deliveryAdjustments").doc();
  const adjustment = buildAdjustment({
    bookingId: requestRef.id,
    bookingRequestId: requestId,
    senderId,
    riderId,
    originalQuote,
    revisedQuote,
    riderReason: reason,
    riderNotes,
    evidencePhotos,
    observations: {
      originalWeightKg,
      observedWeightKg: Number(observedWeightKg) || null,
      observedDescription: description,
      observedVehicleType: observedVehicleType || null,
      dimensions: dimensions || null,
    },
    irisCalculationMetadata: recalculated,
  });

  await db.runTransaction(async (transaction) => {
    const latest = await transaction.get(requestRef);
    const latestStatus = latest.data().status;
    if (latestStatus === "awaiting_sender_adjustment" || latestStatus === "awaiting_adjustment_review") throw new functions.https.HttpsError("failed-precondition", "A pending adjustment already exists.");
    if (adjustment.additionalAmount <= 0) {
      transaction.set(adjustmentRef, {...adjustment, status: "closed_no_charge", adminDecision: "not_required", senderDecision: "not_required"});
      transaction.update(requestRef, {lastAdjustmentId: adjustmentRef.id, updatedAt: Date.now()});
      return;
    }
    const discrepancySummary = {
      adjustmentId: adjustmentRef.id,
      originalQuote: adjustment.originalQuote,
      revisedQuote: adjustment.revisedQuote,
      additionalAmount: adjustment.additionalAmount,
      riderReason: reason,
      evidencePhotos,
      adminDecision: "pending",
      senderDecision: "pending",
      reportedAt: Date.now(),
    };
    transaction.set(adjustmentRef, {
      ...adjustment,
      status: "awaiting_admin_review",
      adminDecision: "pending",
      adminReviewStatus: "pending",
    });
    transaction.update(requestRef, {
      status: "awaiting_adjustment_review",
      adjustmentId: adjustmentRef.id,
      adjustmentAdditionalAmount: adjustment.additionalAmount,
      preAdjustmentStatus: latest.data().status,
      loadDiscrepancy: discrepancySummary,
      requiresAdminReview: true,
      updatedAt: Date.now(),
    });
  });
  if (adjustment.additionalAmount > 0) await notifyUser(senderId, "Booking adjustment under review", "A rider has reported a parcel difference. Circum is reviewing the evidence.", {type: "delivery_adjustment_review", requestId, adjustmentId: adjustmentRef.id});
  return {success: true, adjustmentId: adjustmentRef.id, additionalAmount: adjustment.additionalAmount, status: adjustment.additionalAmount > 0 ? "awaiting_admin_review" : "closed_no_charge"};
});

exports.reviewDeliveryAdjustment = functions.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Authentication required.");
  const token = context.auth.token || {};
  const role = `${token.role || token.adminRole || ""}`.toLowerCase();
  const roles = Array.isArray(token.roles) ? token.roles.map((item) => `${item}`.toLowerCase()) : [];
  const admin = token.admin === true || token.superAdmin === true || ["super_admin", "operations_admin", "support_agent", "driver_manager"].includes(role) || roles.some((item) => ["super_admin", "operations_admin", "support_agent", "driver_manager"].includes(item));
  if (!admin) throw new functions.https.HttpsError("permission-denied", "Admin access required.");
  const adjustmentId = `${data.adjustmentId || ""}`.trim();
  const decision = `${data.decision || ""}`.trim();
  const note = `${data.note || ""}`.trim();
  if (!adjustmentId || !["approve", "reject", "request_more_evidence"].includes(decision)) throw new functions.https.HttpsError("invalid-argument", "A supported review decision is required.");
  const db = getFirestore();
  const adjustmentRef = db.collection("deliveryAdjustments").doc(adjustmentId);
  let notify = null;
  await db.runTransaction(async (transaction) => {
    const adjustmentSnapshot = await transaction.get(adjustmentRef);
    if (!adjustmentSnapshot.exists) throw new functions.https.HttpsError("not-found", "Adjustment not found.");
    const adjustment = adjustmentSnapshot.data();
    if (adjustment.status !== "awaiting_admin_review") throw new functions.https.HttpsError("failed-precondition", "This adjustment is not awaiting Admin review.");
    const bookingRef = db.collection("deliveryRequests").doc(adjustment.bookingId);
    const bookingSnapshot = await transaction.get(bookingRef);
    if (!bookingSnapshot.exists) throw new functions.https.HttpsError("not-found", "Booking not found.");
    const previousStatus = bookingSnapshot.data().preAdjustmentStatus || "accepted";
    const reviewedAt = Date.now();
    const review = {
      adminDecision: decision,
      adminReviewStatus: decision,
      adminReviewedBy: context.auth.uid,
      adminReviewNote: note,
      adminReviewedAt: reviewedAt,
      updatedAt: reviewedAt,
    };
    if (decision === "approve") {
      transaction.update(adjustmentRef, {...review, status: "awaiting_sender_payment", senderDecision: "pending"});
      transaction.update(bookingRef, {
        "status": "awaiting_sender_adjustment",
        "loadDiscrepancy.adminDecision": "approved",
        "loadDiscrepancy.adminReviewNote": note,
        "loadDiscrepancy.adminReviewedAt": reviewedAt,
        "updatedAt": reviewedAt,
      });
      notify = {userId: adjustment.senderId, title: "Booking update approved", body: `Additional payment required: £${Number(adjustment.additionalAmount || 0).toFixed(2)}`, type: "delivery_adjustment"};
      return;
    }
    if (decision === "reject") {
      transaction.update(adjustmentRef, {...review, status: "rejected_by_admin", senderDecision: "not_required"});
      transaction.update(bookingRef, {
        "status": previousStatus,
        "adjustmentRejectedAt": reviewedAt,
        "loadDiscrepancy.adminDecision": "rejected",
        "loadDiscrepancy.adminReviewNote": note,
        "requiresAdminReview": false,
        "updatedAt": reviewedAt,
      });
      notify = {userId: adjustment.riderId, title: "Parcel report reviewed", body: "Circum rejected the parcel adjustment after review.", type: "delivery_adjustment_rejected"};
      return;
    }
    transaction.update(adjustmentRef, {...review, status: "more_evidence_requested"});
    transaction.update(bookingRef, {
      "loadDiscrepancy.adminDecision": "more_evidence_requested",
      "loadDiscrepancy.adminReviewNote": note,
      "updatedAt": reviewedAt,
    });
    notify = {userId: adjustment.riderId, title: "More evidence needed", body: "Circum needs more evidence for the parcel report.", type: "delivery_adjustment_more_evidence"};
  });
  if (notify) await notifyUser(notify.userId, notify.title, notify.body, {type: notify.type, adjustmentId});
  return {success: true, adjustmentId, decision};
});

exports.cancelAdjustedCollection = functions.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Authentication required.");
  const db = getFirestore();
  const adjustmentRef = db.collection("deliveryAdjustments").doc(data.adjustmentId);
  const adjustment = await adjustmentRef.get();
  if (!adjustment.exists || adjustment.data().senderId !== context.auth.uid) throw new functions.https.HttpsError("permission-denied", "Only the sender can cancel this collection.");
  const bookingRef = db.collection("deliveryRequests").doc(adjustment.data().bookingId);
  await db.runTransaction(async (transaction) => {
    transaction.update(adjustmentRef, {status: "cancelled_by_sender", senderDecision: "cancelled", updatedAt: Date.now()});
    transaction.update(bookingRef, {"status": "cancelled_verified_discrepancy", "cancellationReason": "verified_load_discrepancy", "loadDiscrepancy.senderDecision": "cancelled", "updatedAt": Date.now()});
  });
  await notifyUser(adjustment.data().riderId, "Collection cancelled", "The sender cancelled after the verified load discrepancy.", {type: "delivery_adjustment_cancelled", adjustmentId: adjustment.id});
  return {success: true};
});

exports.createDeliveryAdjustmentPayment = senderPaymentCallable(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Authentication required.");
  const db = getFirestore();
  const adjustmentRef = db.collection("deliveryAdjustments").doc(data.adjustmentId);
  const adjustment = await adjustmentRef.get();
  if (!adjustment.exists || adjustment.data().senderId !== context.auth.uid) throw new functions.https.HttpsError("permission-denied", "Only the sender can pay this adjustment.");
  if (adjustment.data().status !== "awaiting_sender_payment" || adjustment.data().adminDecision !== "approve") throw new functions.https.HttpsError("failed-precondition", "This adjustment is not approved for payment.");
  const amount = Math.round(Number(adjustment.data().additionalAmount) * 100);
  if (amount <= 0) throw new functions.https.HttpsError("failed-precondition", "No additional payment is due.");
  const intent = await stripe.paymentIntents.create({
    amount,
    currency: "gbp",
    payment_method_types: ["card"],
    metadata: {feature: "delivery_adjustment", adjustmentId: adjustment.id, bookingId: adjustment.data().bookingId, senderId: context.auth.uid},
  }, {idempotencyKey: `delivery-adjustment-${adjustment.id}`});
  await adjustmentRef.update({paymentIntentId: intent.id, paymentStatus: intent.status, updatedAt: Date.now()});
  return {clientSecret: intent.client_secret, paymentIntentId: intent.id, amount};
});

exports.finalizeDeliveryAdjustmentPayment = senderPaymentCallable(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Authentication required.");
  const db = getFirestore();
  const adjustmentRef = db.collection("deliveryAdjustments").doc(data.adjustmentId);
  const adjustment = await adjustmentRef.get();
  if (!adjustment.exists || adjustment.data().senderId !== context.auth.uid) throw new functions.https.HttpsError("permission-denied", "Only the sender can finalize this adjustment.");
  if (!adjustment.data().paymentIntentId) throw new functions.https.HttpsError("failed-precondition", "Adjustment payment was not created.");
  const intent = await stripe.paymentIntents.retrieve(adjustment.data().paymentIntentId);
  if (intent.status !== "succeeded") throw new functions.https.HttpsError("failed-precondition", "The additional payment has not succeeded.");
  const bookingRef = db.collection("deliveryRequests").doc(adjustment.data().bookingId);
  await db.runTransaction(async (transaction) => {
    const latest = await transaction.get(adjustmentRef);
    const booking = await transaction.get(bookingRef);
    if (latest.data().status === "paid") return;
    const riderAdjustmentAmount = Number(latest.data().additionalAmount) || 0;
    transaction.update(adjustmentRef, {status: "paid", paymentStatus: "succeeded", senderDecision: "approved_and_paid", paidAt: Date.now(), updatedAt: Date.now()});
    transaction.update(bookingRef, {"status": booking.data().preAdjustmentStatus || "accepted", "price": latest.data().revisedQuote, "paidAmount": latest.data().revisedQuote, "adjustmentResolvedBy": "sender_payment", "loadDiscrepancy.senderDecision": "approved_and_paid", "riderAdjustment": riderAdjustmentAmount, "updatedAt": Date.now()});
  });
  await notifyUser(adjustment.data().riderId, "Booking adjustment paid", "The sender paid the revised quote. You may continue the collection.", {type: "delivery_adjustment_paid", adjustmentId: adjustment.id});
  return {success: true};
});
