/* eslint-disable max-len, require-jsdoc */
"use strict";

const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const scheduled = require("./scheduled-delivery-core");
const {canonicalGiftDeliveryPricing} = require("./gift-delivery-pricing-core");
const {canonicalHealthPlusDeliveryPricing} = require("./health-plus-delivery-pricing-core");
const {coordinate, getAuthoritativeRouteFacts} = require("./route-authority");

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
    ["ready_for_collection", "pending_assignment", "requested"].includes(status);
}

function giftDeliveryStatus(data) {
  const status = normalizedStatus(data.giftStatus || data.status);
  if (isCompleted(status)) return "delivered";
  if (status === "cancelled") return "cancelled";
  if (["scheduled", "ready"].includes(status)) return status;
  if (["out_for_delivery", "in_transit"].includes(status)) return "in_transit";
  if (giftReady(data)) return "requested";
  if (["procuring", "preparing", "approved"].includes(status)) return "awaiting_procurement";
  return "pending";
}

function healthDeliveryStatus(data) {
  const status = normalizedStatus(data.status);
  if (isCompleted(status)) return "delivered";
  if (status === "cancelled") return "cancelled";
  if (["collected", "picked_up"].includes(status)) return "picked_up";
  if (["in_transit", "travelling", "out_for_delivery"].includes(status)) return "in_transit";
  if (healthReady(data)) return "requested";
  return "scheduled";
}

function giftMovement(giftId, data) {
  const operationallyReady = giftReady(data);
  const scheduledAt = data.scheduledAt || data.deliveryDate || null;
  const pricing = canonicalGiftDeliveryPricing({
    giftRequestId: giftId,
    authoritativeRouteFacts: data.authoritativeRouteFacts,
    selectedVehicle: data.selectedVehicle || data.vehicleType,
    selectedSpeed: data.selectedSpeed,
    scheduledAt,
  });
  const ready = operationallyReady && pricing !== null;
  const movement = {
    id: `gift_${giftId}`,
    requestId: `gift_${giftId}`,
    deliveryId: `gift_${giftId}`,
    serviceType: SERVICE_TYPES.GIFTS,
    sourceModule: "gifts",
    giftOrderId: giftId,
    giftRequestId: giftId,
    status: giftDeliveryStatus(data),
    matchingStatus: ready ? "available" : "held",
    dispatchStatus: ready ? "requested" : "held",
    readyForDispatch: ready,
    giftOperationallyReady: operationallyReady,
    productType: "gift",
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
    scheduledAt,
    scheduledPickupDate: scheduledAt,
    scheduledPickupWindow: data.scheduledWindow || data.deliveryTimeWindow || null,
    paymentStatus: data.paymentStatus || "pending",
    stripePaymentId: data.stripePaymentIntentId || data.stripeCheckoutSessionId || null,
    walletTransactionId: Number(data.walletContributionGbp || 0) > 0 ? `wallet_gifts_${giftId}` : null,
    trustPointsAwarded: data.trustPointsAwarded || 0,
    rothAwarded: data.rothAwarded || 0,
    price: pricing && pricing.deliveryCharge || 0,
    currency: "GBP",
    displayTitle: `${data.occasion || "Gift"} Gift`,
    packageDescription: "Confidential Gifts by Circum experience",
    giftContentsConfidential: true,
    isGift: true,
    giftBudget: Number(data.grossGiftBudget || data.grossBudget || data.budget || 0),
    giftSpend: Number(data.giftSpend || data.giftPurchaseAmount || data.purchaseAmount || 0),
    deliveryCharge: pricing && pricing.deliveryCharge || null,
    riderSettlementAuthority: pricing && pricing.authority || null,
    riderEarning: pricing && pricing.riderEarning || 0,
    riderPayout: pricing && pricing.riderEarning || 0,
    driverPayout: pricing && pricing.riderEarning || 0,
    platformShare: pricing && pricing.platformShare || 0,
    giftDeliveryPricing: pricing,
    createdAt: data.createdAt || FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };
  movement.fulfilmentStrategy = scheduled.fulfilmentStrategy(movement);
  movement.fulfilmentMode = movement.fulfilmentStrategy === scheduled.STRATEGIES.OPEN_DISPATCH ?
    "open" : "scheduled";
  if (movement.fulfilmentMode === "scheduled" &&
      scheduled.activationState(movement) === "scheduled") {
    movement.status = "scheduled";
    movement.matchingStatus = "held";
    movement.dispatchStatus = "held";
  } else if (operationallyReady && !pricing) {
    movement.status = "scheduled";
    movement.dispatchHoldReason = "awaiting_logistics";
  }
  return movement;
}

function healthMovement(pickupId, data, payment = {}) {
  const ready = healthReady(data);
  const scheduledAt = data.scheduledAt || data.nextPickupAt || data.scheduledPickupDate || null;
  const pricing = canonicalHealthPlusDeliveryPricing({
    healthPlusPickupId: pickupId,
    authoritativeRouteFacts: data.authoritativeRouteFacts,
    selectedVehicle: data.selectedVehicle || data.vehicleType,
    selectedSpeed: data.selectedSpeed,
    scheduledAt,
  });
  const customerCharge = Number(payment.amount || data.amount || data.price || 0);
  const movement = {
    id: `health_${pickupId}`,
    requestId: `health_${pickupId}`,
    deliveryId: `health_${pickupId}`,
    serviceType: SERVICE_TYPES.HEALTH_PLUS,
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
    scheduledAt,
    scheduledPickupDate: data.scheduledPickupDate || data.preferredDay || null,
    scheduledPickupWindow: data.scheduledPickupWindow || data.preferredTime || null,
    paymentStatus: payment.paymentStatus || payment.status || data.paymentStatus || "pending",
    stripePaymentId: payment.paymentIntentId || payment.checkoutSessionId || null,
    walletTransactionId: Number(payment.walletContributionGbp || 0) > 0 ? `wallet_health_${pickupId}` : null,
    trustPointsAwarded: data.trustPointsAwarded || 0,
    rothAwarded: data.rothAwarded || 0,
    price: pricing && pricing.deliveryCharge || 0,
    currency: "GBP",
    healthPlusCharge: Number.isFinite(customerCharge) ? customerCharge : 0,
    healthPlusPaymentType: payment.recurring === true || data.recurring === true ? "subscription" : "one_off",
    healthPlusSubscriptionId: payment.subscriptionId || data.subscriptionId || null,
    deliveryCharge: pricing && pricing.deliveryCharge || null,
    logisticsValue: pricing && pricing.logisticsValue || null,
    healthPlusDeliveryPricing: pricing,
    displayTitle: "Prescription Collection",
    packageDescription: "Confidential sealed Health+ collection",
    healthPlusEnabled: true,
    isHealthPlus: true,
    productType: "health_plus",
    useScheduledDeliveryEngine: data.useScheduledDeliveryEngine === true,
    isVanguard: true,
    requiresVanguard: true,
    riderSettlementAuthority: pricing && pricing.authority || null,
    riderEarning: pricing && pricing.riderEarning || 0,
    riderPayout: pricing && pricing.riderEarning || 0,
    driverPayout: pricing && pricing.riderEarning || 0,
    platformShare: pricing && pricing.platformShare || 0,
    trustPoints: 6,
    planType: data.planType || data.subscriptionPlan || "core",
    riskStatus: data.riskStatus || "scheduled",
    createdAt: data.createdAt || payment.createdAt || FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };
  movement.fulfilmentStrategy = scheduled.fulfilmentStrategy(movement);
  movement.fulfilmentMode = movement.fulfilmentStrategy === scheduled.STRATEGIES.OPEN_DISPATCH ?
    "open" : "scheduled";
  if (movement.fulfilmentMode === "scheduled" &&
      scheduled.activationState(movement) === "scheduled") {
    movement.status = "scheduled";
    movement.matchingStatus = "held";
    movement.dispatchStatus = "held";
  }
  if (ready && !pricing) {
    movement.matchingStatus = "held";
    movement.dispatchStatus = "held";
    movement.readyForCollection = false;
    movement.dispatchHoldReason = "awaiting_logistics";
  }
  return movement;
}

async function projectTerminalMovement(db, deliveryId, before, after) {
  const status = normalizedStatus(after.status || after.deliveryStatus);
  const previousStatus = normalizedStatus(before.status || before.deliveryStatus);
  if (status === previousStatus || !["delivered", "cancelled"].includes(status)) return null;
  const patch = {
    status,
    deliveryStatus: status,
    assignedRiderId: after.assignedRiderId || after.riderId || null,
    updatedAt: FieldValue.serverTimestamp(),
  };
  if (status === "delivered") {
    patch.deliveredAt = after.deliveredAt || after.completedAt || FieldValue.serverTimestamp();
    patch.completedAt = after.completedAt || after.deliveredAt || FieldValue.serverTimestamp();
  } else {
    patch.cancelledAt = after.cancelledAt || FieldValue.serverTimestamp();
  }
  if (after.sourceModule === "gifts" && after.giftRequestId) {
    return db.collection("giftRequests").doc(after.giftRequestId).set(patch, {merge: true});
  }
  if (after.sourceModule === "health_plus" && after.healthPlusPickupId) {
    return db.collection("prescriptionPickups").doc(after.healthPlusPickupId).set({
      ...patch,
      assignedDriverId: patch.assignedRiderId,
    }, {merge: true});
  }
  return null;
}

async function projectGift(db, giftId, data, routeResolver = getAuthoritativeRouteFacts) {
  const deliveryId = `gift_${giftId}`;
  const ref = db.collection("deliveryRequests").doc(deliveryId);
  const existingPricing = canonicalGiftDeliveryPricing({
    giftRequestId: giftId,
    authoritativeRouteFacts: data.authoritativeRouteFacts,
    selectedVehicle: data.selectedVehicle || data.vehicleType,
    selectedSpeed: data.selectedSpeed,
    scheduledAt: data.scheduledAt || data.deliveryDate,
  });
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
  if (giftReady(data) && !existingPricing) {
    const pickupSource = data.pickupPosition && data.pickupPosition.geopoint ||
      data.pickupPosition || data.fulfilmentAddressData || data.procurementAddressData ||
      data.pickupAddressData || data.pickupCoordinates;
    const dropoffSource = data.dropoffPosition && data.dropoffPosition.geopoint ||
      data.dropoffPosition || data.deliveryAddressData || data.dropoffAddressData || {
        latitude: data.latitude || data.lat,
        longitude: data.longitude || data.lng,
      };
    const origin = coordinate(pickupSource);
    const destination = coordinate(dropoffSource);
    if (origin && destination) {
      const canonicalData = {
        ...data,
        authoritativeRouteFacts: await routeResolver({
          origin,
          destination,
          at: data.scheduledAt || data.deliveryDate ?
            new Date(data.scheduledAt || data.deliveryDate) : undefined,
        }),
      };
      const movement = giftMovement(giftId, canonicalData);
      await db.runTransaction(async (transaction) => {
        transaction.set(ref, movement, {merge: true});
        transaction.set(db.collection("giftRequests").doc(giftId), {
          authoritativeRouteFacts: canonicalData.authoritativeRouteFacts,
          giftDeliveryPricing: movement.giftDeliveryPricing,
          deliveryCharge: movement.deliveryCharge,
          riderEarning: movement.riderEarning,
          platformShare: movement.platformShare,
          riderSettlementAuthority: movement.riderSettlementAuthority,
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
      });
    }
  }
  if (existingPricing) {
    await db.runTransaction(async (transaction) => {
      const movement = giftMovement(giftId, data);
      transaction.set(ref, movement, {merge: true});
      transaction.set(db.collection("giftRequests").doc(giftId), {
        giftDeliveryPricing: movement.giftDeliveryPricing,
        deliveryCharge: movement.deliveryCharge,
        riderEarning: movement.riderEarning,
        platformShare: movement.platformShare,
        riderSettlementAuthority: movement.riderSettlementAuthority,
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    });
  }
  return deliveryId;
}

async function projectHealth(db, pickupId, data, routeResolver = getAuthoritativeRouteFacts) {
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
  if (healthReady(data) && !movement.healthPlusDeliveryPricing) {
    const pickupSource = data.pickupPosition && data.pickupPosition.geopoint ||
      data.pickupPosition || data.pharmacyAddressCanonical || data.pharmacyPosition ||
      data.pickupAddressData || data.pickupCoordinates;
    const dropoffSource = data.dropoffPosition && data.dropoffPosition.geopoint ||
      data.dropoffPosition || data.deliveryAddressCanonical || data.deliveryPosition ||
      data.dropoffAddressData || data.dropoffCoordinates;
    const origin = coordinate(pickupSource);
    const destination = coordinate(dropoffSource);
    if (origin && destination) {
      const canonicalData = {
        ...data,
        authoritativeRouteFacts: await routeResolver({
          origin,
          destination,
          at: data.scheduledAt || data.nextPickupAt || data.scheduledPickupDate ?
            new Date(data.scheduledAt || data.nextPickupAt || data.scheduledPickupDate) : undefined,
        }),
      };
      const pricedMovement = healthMovement(pickupId, canonicalData, payment);
      await db.runTransaction(async (transaction) => {
        transaction.set(db.collection("deliveryRequests").doc(deliveryId), pricedMovement, {merge: true});
        transaction.set(db.collection("prescriptionPickups").doc(pickupId), {
          authoritativeRouteFacts: canonicalData.authoritativeRouteFacts,
          healthPlusDeliveryPricing: pricedMovement.healthPlusDeliveryPricing,
          deliveryCharge: pricedMovement.deliveryCharge,
          logisticsValue: pricedMovement.logisticsValue,
          riderEarning: pricedMovement.riderEarning,
          platformShare: pricedMovement.platformShare,
          riderSettlementAuthority: pricedMovement.riderSettlementAuthority,
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
      });
    }
  }
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

exports.onMovementDeliveryWrite = functions.firestore.document("deliveryRequests/{deliveryId}").onWrite(async (change, context) => {
  if (!change.after.exists) return null;
  return projectTerminalMovement(
      getFirestore(),
      context.params.deliveryId,
      change.before.exists ? change.before.data() || {} : {},
      change.after.data() || {},
  );
});

module.exports.SERVICE_TYPES = SERVICE_TYPES;
module.exports.giftMovement = giftMovement;
module.exports.healthMovement = healthMovement;
module.exports.giftReady = giftReady;
module.exports.healthReady = healthReady;
module.exports.projectGift = projectGift;
module.exports.projectHealth = projectHealth;
module.exports.projectTerminalMovement = projectTerminalMovement;
