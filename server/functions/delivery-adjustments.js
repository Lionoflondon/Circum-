/* eslint-disable max-len, require-jsdoc */
const functions = require("firebase-functions/v1");
const crypto = require("crypto");
const {getFirestore} = require("firebase-admin/firestore");
const communicationEngine = require("./communication-engine");
const stripeConfig = functions.config().stripe || {};
const {resolveStripeRuntimeConfig} = require("./stripe-config");
let cachedStripe = null;

function getStripeClient() {
  if (!cachedStripe) {
    const runtimeConfig = resolveStripeRuntimeConfig({config: stripeConfig});
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
const {repriceWeightFromQuote, weightBandFor, WEIGHT_POLICY_VERSION} = require("./canonical-weight-policy");
const {normalizeVehicleClass, vehicleCanHandle} = require("./vehicle-dispatch");
const {enforceIrisRequestLimit} = require("./iris-request-guard");
const {
  DISCREPANCY_REASONS,
  buildAdjustment,
  isMaterialDiscrepancy,
} = require("./delivery-adjustment-core");

async function notifyUser(userId, recipientRole, title, body, data) {
  if (!userId) return;
  const type = `${data && data.type || "delivery_adjustment"}`;
  const adjustmentId = `${data && data.adjustmentId || ""}`;
  await communicationEngine.emitNotification({
    recipientId: userId,
    recipientRole,
    type,
    title,
    body,
    data: {
      adjustmentId,
      deliveryId: `${data && data.deliveryId || data && data.requestId || ""}`,
      correlationId: `${type}:${adjustmentId}:${userId}`,
      category: "deliveries",
    },
  });
}

async function bookingReference(db, requestId) {
  const direct = db.collection("deliveryRequests").doc(requestId);
  const directSnapshot = await direct.get();
  if (directSnapshot.exists) return directSnapshot;
  const query = await db.collection("deliveryRequests")
      .where("requestId", "==", requestId).limit(1).get();
  return query.empty ? null : query.docs[0];
}

exports.reportLoadDiscrepancy = functions.runWith({enforceAppCheck: true}).https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Authentication required.");
  const {requestId, reason, evidencePhotos = [], observedWeightKg, observedDescription, observedVehicleType, riderNotes, dimensions} = data;
  if (!requestId || !DISCREPANCY_REASONS.includes(reason)) throw new functions.https.HttpsError("invalid-argument", "A booking and supported discrepancy reason are required.");
  if (!Array.isArray(evidencePhotos) || evidencePhotos.length === 0) throw new functions.https.HttpsError("invalid-argument", "At least one evidence photo is required.");

  const db = getFirestore();
  await enforceIrisRequestLimit({db, uid: context.auth.uid, action: "report_load_discrepancy"});
  const bookingSnapshot = await bookingReference(db, requestId);
  if (!bookingSnapshot) throw new functions.https.HttpsError("not-found", "Booking not found.");
  const requestRef = bookingSnapshot.ref;
  const booking = bookingSnapshot.data();
  const riderId = context.auth.uid;
  if (![booking.riderId, booking.driverId, booking.assignedDriverId].includes(riderId)) throw new functions.https.HttpsError("permission-denied", "Only the assigned rider can report this discrepancy.");
  if (booking.status === "awaiting_sender_adjustment") throw new functions.https.HttpsError("failed-precondition", "This booking already has a pending adjustment.");

  const paidQuote = booking.pricingBreakdown && typeof booking.pricingBreakdown === "object" ? booking.pricingBreakdown : {};
  const originalWeightKg = Number(booking.finalWeightUsed || booking.finalChargeableWeight || booking.confirmedWeightKg || booking.weightKg || paidQuote.weightKg || booking.parcel && booking.parcel.weightKg || 0);
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
  const proposedWeightKg = Number(observedWeightKg) || originalWeightKg;
  const originalQuoteSnapshot = {
    ...paidQuote,
    weightKg: originalWeightKg,
    total: Number(paidQuote.total || booking.paidAmount || booking.price || booking.quote || 0),
  };
  const revisedQuoteSnapshot = repriceWeightFromQuote(originalQuoteSnapshot, proposedWeightKg);
  const revisedQuote = revisedQuoteSnapshot.total;
  const originalQuote = originalQuoteSnapshot.total;
  const senderId = booking.senderId || booking.userId;
  const adjustmentId = crypto.createHash("sha256").update(JSON.stringify({
    requestId: requestRef.id,
    riderId,
    reason,
    observedWeightKg: Number(observedWeightKg) || null,
    observedDescription: description,
    observedVehicleType: observedVehicleType || null,
    dimensions: dimensions || null,
    evidencePhotos: evidencePhotos.slice().sort(),
  })).digest("hex").slice(0, 40);
  const adjustmentRef = db.collection("deliveryAdjustments").doc(adjustmentId);
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
      proposedWeightBand: weightBandFor(proposedWeightKg),
    },
    irisCalculationMetadata: {
      engineVersion: recalculated.engineVersion || recalculated.version,
      knowledgeVersion: recalculated.knowledgeVersion || null,
      recommendation: recalculated.recommendation,
      financialAuthority: false,
    },
    originalQuoteSnapshot,
    revisedQuoteSnapshot,
  });

  let idempotent = false;
  await db.runTransaction(async (transaction) => {
    const existingAdjustment = await transaction.get(adjustmentRef);
    if (existingAdjustment.exists) {
      idempotent = true;
      return;
    }
    const latest = await transaction.get(requestRef);
    const latestStatus = latest.data().status;
    if (latestStatus === "awaiting_sender_adjustment" || latestStatus === "awaiting_adjustment_review") throw new functions.https.HttpsError("failed-precondition", "A pending adjustment already exists.");
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
  if (idempotent) {
    return {success: true, idempotent: true, adjustmentId: adjustmentRef.id, additionalAmount: adjustment.additionalAmount, status: "awaiting_admin_review"};
  }
  await notifyUser(senderId, "sender", "Parcel details under review", "Your rider believes the parcel may not match the selected weight band. CIRCUM is reviewing the evidence; no additional charge is final yet.", {type: "delivery_adjustment_review", requestId, adjustmentId: adjustmentRef.id});
  return {success: true, idempotent: false, adjustmentId: adjustmentRef.id, additionalAmount: adjustment.additionalAmount, status: "awaiting_admin_review"};
});

exports.reviewDeliveryAdjustment = functions.runWith({enforceAppCheck: true}).https.onCall(async (data, context) => {
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
    const booking = bookingSnapshot.data();
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
      const finalWeightKg = Number(adjustment.observations && (adjustment.observations.observedWeightKg || adjustment.observations.originalWeightKg) || 0);
      const finalWeightBand = weightBandFor(finalWeightKg);
      const requiredVehicle = normalizeVehicleClass(
          adjustment.observations && adjustment.observations.observedVehicleType ||
          (finalWeightKg >= 40 ? "van" : booking.requiredVehicle || booking.vehicleRequirement || "any"),
          "any",
      );
      const assignedVehicle = normalizeVehicleClass(booking.assignedVehicleClass || booking.assignedVehicleSnapshot && booking.assignedVehicleSnapshot.type || booking.vehicleType, null);
      const vehicleCompatible = !assignedVehicle || vehicleCanHandle(assignedVehicle, requiredVehicle);
      const needsPayment = Number(adjustment.additionalAmount || 0) > 0;
      const nextStatus = needsPayment ? "awaiting_sender_payment" : !vehicleCompatible ? "vehicle_reassignment_required" : "resolved_no_charge";
      transaction.update(adjustmentRef, {
        ...review,
        status: nextStatus,
        senderDecision: needsPayment ? "pending" : "not_required",
        finalCanonicalWeightKg: finalWeightKg,
        finalCanonicalWeightBand: finalWeightBand,
        requiredVehicle,
        vehicleCompatible,
        pricingConsequenceReference: adjustmentRef.id,
      });
      transaction.update(bookingRef, {
        "status": !vehicleCompatible ? "awaiting_vehicle_reassignment" : needsPayment ? "awaiting_sender_adjustment" : previousStatus,
        "finalWeightUsed": finalWeightKg,
        "finalChargeableWeight": finalWeightKg,
        "confirmedWeightKg": finalWeightKg,
        "confirmedWeightBand": finalWeightBand.label,
        "weightPolicyVersion": WEIGHT_POLICY_VERSION,
        "requiredVehicle": requiredVehicle,
        "vehicleRequirement": requiredVehicle,
        "loadDiscrepancy.adminDecision": "approved",
        "loadDiscrepancy.adminReviewNote": note,
        "loadDiscrepancy.adminReviewedAt": reviewedAt,
        "updatedAt": reviewedAt,
      });
      transaction.set(db.collection("irisLearningCases").doc(`weight_discrepancy_${adjustmentId}`), {
        caseType: "weight_discrepancy",
        deliveryId: adjustment.bookingId,
        adjustmentId,
        rawRiderObservation: adjustment.observations || {},
        evidenceReferences: adjustment.evidencePhotos || [],
        adminAdjudication: {
          decision: "approved",
          finalWeightKg,
          finalWeightBand: finalWeightBand.label,
          reviewedBy: context.auth.uid,
          reviewedAt,
        },
        learningStatus: "pending_review",
        reviewStatus: "pending_review",
        productionKnowledgeEligible: false,
        createdAt: reviewedAt,
        updatedAt: reviewedAt,
      }, {merge: true});
      if (!vehicleCompatible) {
        transaction.set(db.collection("operationalIncidents").doc(`weight_vehicle_mismatch_${adjustment.bookingId}`), {
          deliveryId: adjustment.bookingId,
          incidentType: "weight_vehicle_mismatch",
          severity: "RED",
          status: "OPEN",
          currentDeliveryState: "awaiting_vehicle_reassignment",
          assignedRider: adjustment.riderId,
          adjustmentId,
          detectedAt: reviewedAt,
          updatedAt: reviewedAt,
        }, {merge: true});
      }
      notify = needsPayment ? {userId: adjustment.senderId, recipientRole: "sender", title: "Booking update approved", body: `Additional payment required: £${Number(adjustment.additionalAmount || 0).toFixed(2)}`, type: "delivery_adjustment"} : {userId: adjustment.senderId, recipientRole: "sender", title: "Parcel review complete", body: "CIRCUM reviewed the parcel details. No additional payment is required.", type: "delivery_adjustment_resolved"};
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
      notify = {userId: adjustment.riderId, recipientRole: "rider", title: "Parcel report reviewed", body: "Circum rejected the parcel adjustment after review.", type: "delivery_adjustment_rejected"};
      return;
    }
    transaction.update(adjustmentRef, {...review, status: "more_evidence_requested"});
    transaction.update(bookingRef, {
      "loadDiscrepancy.adminDecision": "more_evidence_requested",
      "loadDiscrepancy.adminReviewNote": note,
      "updatedAt": reviewedAt,
    });
    notify = {userId: adjustment.riderId, recipientRole: "rider", title: "More evidence needed", body: "Circum needs more evidence for the parcel report.", type: "delivery_adjustment_more_evidence"};
  });
  if (notify) await notifyUser(notify.userId, notify.recipientRole, notify.title, notify.body, {type: notify.type, adjustmentId});
  return {success: true, adjustmentId, decision};
});

exports.cancelAdjustedCollection = functions.runWith({enforceAppCheck: true}).https.onCall(async (data, context) => {
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
  await notifyUser(adjustment.data().riderId, "rider", "Collection cancelled", "The sender cancelled after the verified load discrepancy.", {type: "delivery_adjustment_cancelled", adjustmentId: adjustment.id});
  return {success: true};
});

exports.createDeliveryAdjustmentPayment = functions.runWith({enforceAppCheck: true}).https.onCall(async (data, context) => {
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

exports.finalizeDeliveryAdjustmentPayment = functions.runWith({enforceAppCheck: true}).https.onCall(async (data, context) => {
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
    const revisedSnapshot = latest.data().revisedQuoteSnapshot || {};
    transaction.update(bookingRef, {"status": latest.data().vehicleCompatible === false ? "awaiting_vehicle_reassignment" : booking.data().preAdjustmentStatus || "accepted", "price": latest.data().revisedQuote, "paidAmount": latest.data().revisedQuote, "pricingBreakdown": revisedSnapshot, "riderPayout": revisedSnapshot.riderPayout, "driverPayout": revisedSnapshot.driverPayout, "riderEarning": revisedSnapshot.riderEarning, "platformRevenue": revisedSnapshot.platformRevenue, "finalWeightUsed": latest.data().finalCanonicalWeightKg, "confirmedWeightKg": latest.data().finalCanonicalWeightKg, "confirmedWeightBand": latest.data().finalCanonicalWeightBand && latest.data().finalCanonicalWeightBand.label, "weightPolicyVersion": WEIGHT_POLICY_VERSION, "adjustmentResolvedBy": "sender_payment", "loadDiscrepancy.senderDecision": "approved_and_paid", "updatedAt": Date.now()});
  });
  await notifyUser(
      adjustment.data().riderId,
      "rider",
      "Booking adjustment paid",
      adjustment.data().vehicleCompatible === false ?
        "The revised quote is paid. Keep collection paused while CIRCUM arranges a compatible vehicle." :
        "The sender paid the revised quote. You may continue the collection.",
      {type: "delivery_adjustment_paid", adjustmentId: adjustment.id},
  );
  return {success: true};
});
