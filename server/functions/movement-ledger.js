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
    ["ready_for_collection", "pending_assignment", "requested", "assigned",
      "arrived_at_pickup", "collected", "out_for_delivery", "delivered"].includes(status);
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
  if (status === "assigned") return "accepted";
  if (["arrived_at_pickup", "awaiting_pharmacy_collection"].includes(status)) return "arrived_at_pickup";
  if (["collected", "picked_up"].includes(status)) return "collected";
  if (["in_transit", "travelling", "out_for_delivery"].includes(status)) return "navigating_to_dropoff";
  if (healthReady(data)) return "requested";
  return "scheduled";
}

function giftMovement(giftId, data) {
  const ready = giftReady(data);
  return {
    id: `gift_${giftId}`,
    requestId: `gift_${giftId}`,
    deliveryId: `gift_${giftId}`,
    serviceType: SERVICE_TYPES.GIFTS,
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
  const assignedRiderId = data.assignedRiderId || data.assignedDriverId || data.driverId || data.riderId || null;
  const pickupCanonical = data.pharmacyAddressCanonical || {};
  const dropoffCanonical = data.deliveryAddressCanonical || {};
  const handlingRequirements = [
    data.fragile === true ? "fragile" : null,
    data.coldChainRequired === true ? "cold_chain" : null,
    data.temperatureSensitive === true ? "temperature_sensitive" : null,
    data.vanguardRequired === true || data.requiresVanguard === true ? "vanguard" : null,
  ].filter(Boolean);
  return {
    id: `health_${pickupId}`,
    requestId: `health_${pickupId}`,
    deliveryId: `health_${pickupId}`,
    serviceType: SERVICE_TYPES.HEALTH_PLUS,
    sourceModule: "health_plus",
    healthPlusOrderId: pickupId,
    healthPlusPickupId: pickupId,
    profileId: data.profileId || payment.profileId || null,
    status: healthDeliveryStatus(data),
    matchingStatus: assignedRiderId ? "accepted" : ready ? "available" : "held",
    readyForCollection: ready,
    customerId: data.senderId || data.userId || payment.userId || null,
    userId: data.senderId || data.userId || payment.userId || null,
    senderId: data.senderId || data.userId || payment.userId || null,
    senderEmail: data.email || payment.email || payment.userEmail || null,
    assignedRiderId,
    assignedDriverId: assignedRiderId,
    riderId: assignedRiderId,
    preferredRiderId: data.preferredRiderId || null,
    preferredRiderName: data.preferredRiderName || null,
    preferredRiderPriority: Boolean(data.preferredRiderId),
    pickupAddress: data.pharmacyAddress || data.pickupAddress || "",
    dropoffAddress: data.deliveryAddress || data.dropoffAddress || "",
    pickupPosition: pickupCanonical.coordinates || null,
    dropoffPosition: dropoffCanonical.coordinates || null,
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
    isHealthPlus: true,
    requiredVehicle: data.requiredVehicle || data.vehicleRequirement || "",
    handlingRequirements,
    collectionPinRequired: data.collectionPinRequired === true,
    deliveryPinRequired: data.deliveryPinRequired === true,
    evidenceRequired: data.evidenceRequired === true,
    custodyRequired: true,
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

function healthSourceStatus(deliveryStatus) {
  const status = normalizedStatus(deliveryStatus);
  if (["accepted", "navigating_to_pickup"].includes(status)) return "assigned";
  if (["arrived_at_pickup", "pickup_verification", "pickup_verified", "waiting"].includes(status)) return "arrived_at_pickup";
  if (status === "collected") return "collected";
  if (["navigating_to_dropoff", "arrived_at_dropoff", "pin_required"].includes(status)) return "out_for_delivery";
  if (["completed", "delivered"].includes(status)) return "delivered";
  if (["cancelled", "failed"].includes(status)) return status;
  return "";
}

async function syncHealthSourceFromDelivery(db, deliveryId, delivery) {
  if (normalizedStatus(delivery.sourceModule) !== "health_plus") return null;
  const pickupId = `${delivery.healthPlusPickupId || delivery.healthPlusOrderId || ""}`.trim();
  const status = healthSourceStatus(delivery.deliveryStage || delivery.deliveryStatus || delivery.status);
  if (!pickupId || !status) return null;
  const ref = db.collection("prescriptionPickups").doc(pickupId);
  const snap = await ref.get();
  if (!snap.exists) return null;
  const pickup = snap.data() || {};
  const riderId = delivery.assignedRiderId || delivery.riderId || delivery.assignedDriverId || null;
  if (normalizedStatus(pickup.status) === status && `${pickup.assignedDriverId || ""}` === `${riderId || ""}`) return null;
  await ref.set({
    status,
    assignedDriverId: riderId,
    riderId,
    canonicalDeliveryId: deliveryId,
    lifecycleProjectedAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  return pickupId;
}

exports.onVerticalDeliveryMovementWrite = functions.firestore.document("deliveryRequests/{deliveryId}").onWrite(async (change, context) => {
  if (!change.after.exists) return null;
  return syncHealthSourceFromDelivery(getFirestore(), context.params.deliveryId, change.after.data() || {});
});

module.exports.SERVICE_TYPES = SERVICE_TYPES;
module.exports.giftMovement = giftMovement;
module.exports.healthMovement = healthMovement;
module.exports.giftReady = giftReady;
module.exports.healthReady = healthReady;
module.exports.projectGift = projectGift;
module.exports.projectHealth = projectHealth;
module.exports.healthSourceStatus = healthSourceStatus;
module.exports.syncHealthSourceFromDelivery = syncHealthSourceFromDelivery;
