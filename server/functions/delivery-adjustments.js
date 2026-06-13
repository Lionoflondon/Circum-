/* eslint-disable max-len, require-jsdoc */
const functions = require("firebase-functions/v1");
const {getFirestore} = require("firebase-admin/firestore");
const {getMessaging} = require("firebase-admin/messaging");
const stripeConfig = functions.config().stripe || {};
const stripe = require("stripe")(stripeConfig.livekey);
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
    if (latest.data().status === "awaiting_sender_adjustment") throw new functions.https.HttpsError("failed-precondition", "A pending adjustment already exists.");
    if (adjustment.additionalAmount <= 0) {
      transaction.set(adjustmentRef, {...adjustment, status: "closed_no_charge", senderDecision: "not_required"});
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
      senderDecision: "pending",
      reportedAt: Date.now(),
    };
    transaction.set(adjustmentRef, adjustment);
    transaction.update(requestRef, {
      status: "awaiting_sender_adjustment",
      adjustmentId: adjustmentRef.id,
      adjustmentAdditionalAmount: adjustment.additionalAmount,
      preAdjustmentStatus: latest.data().status,
      loadDiscrepancy: discrepancySummary,
      updatedAt: Date.now(),
    });
  });
  if (adjustment.additionalAmount > 0) await notifyUser(senderId, "Booking Update Required", `Additional payment required: £${adjustment.additionalAmount.toFixed(2)}`, {type: "delivery_adjustment", requestId, adjustmentId: adjustmentRef.id});
  return {success: true, adjustmentId: adjustmentRef.id, additionalAmount: adjustment.additionalAmount, status: adjustment.additionalAmount > 0 ? "awaiting_sender_adjustment" : "closed_no_charge"};
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

exports.createDeliveryAdjustmentPayment = functions.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Authentication required.");
  const db = getFirestore();
  const adjustmentRef = db.collection("deliveryAdjustments").doc(data.adjustmentId);
  const adjustment = await adjustmentRef.get();
  if (!adjustment.exists || adjustment.data().senderId !== context.auth.uid) throw new functions.https.HttpsError("permission-denied", "Only the sender can pay this adjustment.");
  if (adjustment.data().status !== "awaiting_sender_payment") throw new functions.https.HttpsError("failed-precondition", "This adjustment is not awaiting payment.");
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

exports.finalizeDeliveryAdjustmentPayment = functions.https.onCall(async (data, context) => {
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
    transaction.update(adjustmentRef, {status: "paid", paymentStatus: "succeeded", senderDecision: "approved_and_paid", paidAt: Date.now(), updatedAt: Date.now()});
    transaction.update(bookingRef, {"status": booking.data().preAdjustmentStatus || "accepted", "price": latest.data().revisedQuote, "paidAmount": latest.data().revisedQuote, "adjustmentResolvedBy": "sender_payment", "loadDiscrepancy.senderDecision": "approved_and_paid", "updatedAt": Date.now()});
  });
  await notifyUser(adjustment.data().riderId, "Booking adjustment paid", "The sender paid the revised quote. You may continue the collection.", {type: "delivery_adjustment_paid", adjustmentId: adjustment.id});
  return {success: true};
});
