/* eslint-disable max-len, require-jsdoc */
"use strict";

const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");

const SERVICE_TYPES = Object.freeze({
  STANDARD: "STANDARD",
  SCHEDULED: "SCHEDULED",
  HEAVY_DUTY: "HEAVY_DUTY",
  BUSINESS: "BUSINESS",
  VANGUARD: "VANGUARD",
  GIFTS: "GIFTS",
  HEALTH_PLUS: "HEALTH_PLUS",
});

function normalizedStatus(value) {
  return `${value || ""}`.trim().toLowerCase().replace(/[\s-]+/g, "_");
}

function firstDefined(...values) {
  return values.find((value) => value !== undefined && value !== null);
}

function specialFlowAuthority(data = {}, payment = {}) {
  const route = data.authoritativeRoute || data.route || data.routeMetrics || {};
  const pricing = data.authoritativePricing || payment.authoritativePricing || {};
  const riderEarning = firstDefined(data.riderEarning, data.riderPay, data.riderPayout, pricing.riderEarning, pricing.riderPay);
  return {
    ...(riderEarning !== undefined ? {riderEarning: Number(riderEarning)} : {}),
    ...(firstDefined(data.riderEligibleFare, pricing.riderEligibleFare) !== undefined ? {riderEligibleFare: Number(firstDefined(data.riderEligibleFare, pricing.riderEligibleFare))} : {}),
    ...(data.riderPayoutCalculationVersion || pricing.riderPayoutCalculationVersion ? {riderPayoutCalculationVersion: data.riderPayoutCalculationVersion || pricing.riderPayoutCalculationVersion} : {}),
    distance: firstDefined(data.distance, data.distanceText, route.distanceText, route.distance),
    distanceText: firstDefined(data.distanceText, route.distanceText),
    duration: firstDefined(data.duration, data.durationText, route.durationText, route.duration),
    durationText: firstDefined(data.durationText, route.durationText),
    routeDistanceMeters: firstDefined(data.routeDistanceMeters, route.distanceMeters),
    routeDurationSeconds: firstDefined(data.routeDurationSeconds, route.durationSeconds),
    pickupDetails: data.pickupDetails || data.pickupAddressData || data.pharmacyAddressData || null,
    dropoffDetails: data.dropoffDetails || data.deliveryAddressData || null,
    pickupLocality: firstDefined(data.pickupLocality, data.pharmacyLocality, data.pickupDetails && data.pickupDetails.locality, data.pickupAddressData && data.pickupAddressData.locality, data.pharmacyAddressData && data.pharmacyAddressData.locality),
    dropoffLocality: firstDefined(data.dropoffLocality, data.deliveryLocality, data.dropoffDetails && data.dropoffDetails.locality, data.deliveryAddressData && data.deliveryAddressData.locality),
    minimumVehicle: firstDefined(data.minimumVehicle, data.recommendedVehicle, data.vehicleType, pricing.vehicleType),
    iris: data.iris || data.irisAssessment || null,
    irisRequired: data.irisRequired === true,
    handlingInstructions: firstDefined(data.handlingInstructions, data.specialInstructions, data.riderInstructions),
  };
}

function isCompleted(value) {
  return ["completed", "complete", "delivered"].includes(normalizedStatus(value));
}

function giftReady(data) {
  const status = normalizedStatus(data.giftStatus || data.status);
  return data.readyForDispatch === true || data.dispatchReady === true ||
    ["packed", "ready_for_dispatch", "pending_assignment", "out_for_delivery"].includes(status);
}

function healthReady(data) {
  const status = normalizedStatus(data.status);
  return data.collectionDetailsReady === true || data.readyForCollection === true ||
    ["ready_for_collection", "pending_assignment", "requested"].includes(status);
}

function giftDeliveryStatus(data) {
  const status = normalizedStatus(data.giftStatus || data.status);
  if (isCompleted(status)) return "completed";
  if (status === "cancelled") return "cancelled";
  if (["out_for_delivery", "in_transit"].includes(status)) return "in_transit";
  if (giftReady(data)) return "requested";
  if (["procuring", "preparing", "approved"].includes(status)) return "awaiting_procurement";
  return "pending";
}

function healthDeliveryStatus(data) {
  const status = normalizedStatus(data.status);
  if (isCompleted(status)) return "completed";
  if (status === "cancelled") return "cancelled";
  if (["collected", "picked_up"].includes(status)) return "picked_up";
  if (["in_transit", "travelling", "out_for_delivery"].includes(status)) return "in_transit";
  if (healthReady(data)) return "requested";
  return "scheduled";
}

function giftMovement(giftId, data) {
  const ready = giftReady(data);
  return {
    ...specialFlowAuthority(data),
    id: `gift_${giftId}`,
    requestId: `gift_${giftId}`,
    deliveryId: `gift_${giftId}`,
    serviceType: SERVICE_TYPES.GIFTS,
    isGift: true,
    sourceModule: "gifts",
    giftOrderId: giftId,
    giftRequestId: giftId,
    status: giftDeliveryStatus(data),
    matchingStatus: ready ? "available" : "held",
    readyForDispatch: ready,
    customerId: data.senderId || data.customerId || data.userId || null,
    userId: data.senderId || data.userId || null,
    senderId: data.senderId || data.userId || null,
    senderName: data.senderName || null,
    senderEmail: data.senderEmail || null,
    assignedRiderId: data.assignedRiderId || data.riderId || null,
    riderId: data.assignedRiderId || data.riderId || null,
    pickupAddress: data.fulfilmentAddress || data.procurementAddress || data.pickupAddress || "",
    pickupAddressPending: !(data.fulfilmentAddress || data.procurementAddress || data.pickupAddress),
    dropoffAddress: data.deliveryAddress || "",
    scheduledAt: data.deliveryDate || null,
    scheduledPickupDate: data.deliveryDate || null,
    scheduledPickupWindow: data.deliveryTimeWindow || null,
    paymentStatus: data.paymentStatus || "pending",
    stripePaymentId: data.stripePaymentIntentId || data.stripeCheckoutSessionId || null,
    walletTransactionId: Number(data.walletContributionGbp || 0) > 0 ? `wallet_gifts_${giftId}` : null,
    trustPointsAwarded: data.trustPointsAwarded || 0,
    rothAwarded: data.rothAwarded || 0,
    price: Number(data.grossGiftBudget || data.grossBudget || data.budget || 0),
    currency: "GBP",
    displayTitle: `${data.occasion || "Gift"} Gift`,
    packageDescription: "Confidential Gifts by Circum experience",
    giftContentsConfidential: true,
    createdAt: data.createdAt || FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };
}

function healthMovement(pickupId, data, payment = {}) {
  const ready = healthReady(data);
  return {
    ...specialFlowAuthority(data, payment),
    id: `health_${pickupId}`,
    requestId: `health_${pickupId}`,
    deliveryId: `health_${pickupId}`,
    serviceType: SERVICE_TYPES.HEALTH_PLUS,
    isHealthPlus: true,
    sourceModule: "health_plus",
    healthPlusOrderId: pickupId,
    healthPlusPickupId: pickupId,
    profileId: data.profileId || payment.profileId || null,
    status: healthDeliveryStatus(data),
    matchingStatus: ready ? "available" : "held",
    readyForCollection: ready,
    customerId: data.senderId || data.userId || payment.userId || null,
    userId: data.senderId || data.userId || payment.userId || null,
    senderId: data.senderId || data.userId || payment.userId || null,
    senderEmail: data.email || payment.email || payment.userEmail || null,
    assignedRiderId: data.assignedRiderId || data.driverId || data.riderId || null,
    riderId: data.assignedRiderId || data.driverId || data.riderId || null,
    preferredRiderId: data.preferredRiderId || null,
    preferredRiderName: data.preferredRiderName || null,
    preferredRiderPriority: Boolean(data.preferredRiderId),
    pickupAddress: data.pharmacyAddress || data.pickupAddress || "",
    dropoffAddress: data.deliveryAddress || data.dropoffAddress || "",
    scheduledAt: data.scheduledAt || data.nextPickupAt || data.scheduledPickupDate || null,
    scheduledPickupDate: data.scheduledPickupDate || data.preferredDay || null,
    scheduledPickupWindow: data.scheduledPickupWindow || data.preferredTime || null,
    paymentStatus: payment.paymentStatus || payment.status || data.paymentStatus || "pending",
    stripePaymentId: payment.paymentIntentId || payment.checkoutSessionId || null,
    walletTransactionId: Number(payment.walletContributionGbp || 0) > 0 ? `wallet_health_${pickupId}` : null,
    trustPointsAwarded: data.trustPointsAwarded || 0,
    rothAwarded: data.rothAwarded || 0,
    price: Number(payment.amount || data.price || 0),
    currency: "GBP",
    displayTitle: "Prescription Collection",
    packageDescription: "Confidential sealed Health+ collection",
    healthPlusEnabled: true,
    isVanguard: true,
    trustPoints: 6,
    planType: data.planType || data.subscriptionPlan || "core",
    riskStatus: data.riskStatus || "scheduled",
    createdAt: data.createdAt || payment.createdAt || FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };
}

async function projectGift(db, giftId, data) {
  const deliveryId = `gift_${giftId}`;
  const ref = db.collection("deliveryRequests").doc(deliveryId);
  await db.runTransaction(async (transaction) => {
    const movement = giftMovement(giftId, data);
    transaction.set(ref, movement, {merge: true});
    if (data.deliveryId !== deliveryId || data.serviceType !== SERVICE_TYPES.GIFTS || data.sourceModule !== "gifts") {
      transaction.set(db.collection("giftRequests").doc(giftId), {
        deliveryId,
        serviceType: SERVICE_TYPES.GIFTS,
        sourceModule: "gifts",
        movementLinkedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    }
  });
  return deliveryId;
}

async function projectHealth(db, pickupId, data) {
  const paymentSnap = await db.collection("healthPlusPayments").doc(pickupId).get();
  const payment = paymentSnap.exists ? paymentSnap.data() : {};
  const deliveryId = `health_${pickupId}`;
  const movement = healthMovement(pickupId, data, payment);
  await db.runTransaction(async (transaction) => {
    transaction.set(db.collection("deliveryRequests").doc(deliveryId), movement, {merge: true});
    if (data.deliveryId !== deliveryId || data.serviceType !== SERVICE_TYPES.HEALTH_PLUS || data.sourceModule !== "health_plus") {
      transaction.set(db.collection("prescriptionPickups").doc(pickupId), {
        deliveryId,
        serviceType: SERVICE_TYPES.HEALTH_PLUS,
        sourceModule: "health_plus",
        movementLinkedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    }
  });
  return deliveryId;
}

exports.onGiftMovementWrite = functions.firestore.document("giftRequests/{giftId}").onWrite(async (change, context) => {
  if (!change.after.exists) return null;
  return projectGift(getFirestore(), context.params.giftId, change.after.data() || {});
});

exports.onHealthMovementWrite = functions.firestore.document("prescriptionPickups/{pickupId}").onWrite(async (change, context) => {
  if (!change.after.exists) return null;
  return projectHealth(getFirestore(), context.params.pickupId, change.after.data() || {});
});

exports.onHealthPaymentMovementWrite = functions.firestore.document("healthPlusPayments/{pickupId}").onWrite(async (change, context) => {
  if (!change.after.exists) return null;
  const pickup = await getFirestore().collection("prescriptionPickups").doc(context.params.pickupId).get();
  if (!pickup.exists) return null;
  return projectHealth(getFirestore(), context.params.pickupId, pickup.data() || {});
});

module.exports.SERVICE_TYPES = SERVICE_TYPES;
module.exports.giftMovement = giftMovement;
module.exports.healthMovement = healthMovement;
module.exports.giftReady = giftReady;
module.exports.healthReady = healthReady;
module.exports.projectGift = projectGift;
module.exports.projectHealth = projectHealth;
