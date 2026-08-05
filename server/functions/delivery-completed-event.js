/* eslint-disable max-len, require-jsdoc */
"use strict";

const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const giftStoryAutomation = require("./gift-story-automation");
const legends = require("./legends");
const referrals = require("./referrals");
const platformNotifications = require("./platform-notifications");
const {createDeliveryCore, DELIVERY_DOMAIN_VERSION} = require("./delivery-domain-core");

const EVENT_TYPE = "DeliveryCompleted";
const EVENT_VERSION = 1;
const PROCESSING_LEASE_MS = 10 * 60 * 1000;

function text(value) {
  return `${value || ""}`.trim();
}

function idFrom(delivery, ...keys) {
  for (const key of keys) {
    const value = text(delivery && delivery[key]);
    if (value) return value;
  }
  return null;
}

function buildDeliveryCompletedEvent({deliveryId, delivery = {}, riderId, trustPoints, completedAt, verification, evidence}) {
  const eventId = `delivery_completed_${deliveryId}`;
  const core = createDeliveryCore({
    id: deliveryId,
    status: "delivered",
    senderId: delivery.senderId || delivery.userId || delivery.customerId,
    recipientId: delivery.recipientId || delivery.receiverId || delivery.recipientUserId,
    riderId: riderId || delivery.riderId || delivery.assignedRiderId || delivery.driverId,
    createdAt: delivery.createdAt,
    completedAt: completedAt || delivery.completedAt || delivery.deliveredAt,
    dispatchId: delivery.dispatchId,
    trackingId: delivery.trackingId,
    pricingId: delivery.pricingId,
    paymentId: delivery.paymentId || delivery.stripePaymentIntentId,
    evidenceId: delivery.evidenceId,
  });
  const verified = verification || {
    pickupPinVerified: delivery.collectionPinVerified === true || delivery.pickupPinVerified === true,
    deliveryPinVerified: delivery.deliveryPinVerified === true || delivery.receiverPinVerified === true,
    evidenceVerified: delivery.evidenceVerified === true || Number(delivery.evidenceSummary?.verifiedPhotoCount || 0) > 0,
  };
  return {
    eventId,
    eventType: EVENT_TYPE,
    version: EVENT_VERSION,
    deliveryDomainVersion: DELIVERY_DOMAIN_VERSION,
    core,
    deliveryId,
    senderId: idFrom(delivery, "senderId", "userId", "customerId"),
    recipientId: idFrom(delivery, "recipientId", "receiverId", "recipientUserId"),
    riderId: riderId || idFrom(delivery, "riderId", "driverId", "assignedRiderId", "assignedDriverId"),
    completedAt: completedAt || FieldValue.serverTimestamp(),
    publishedAt: FieldValue.serverTimestamp(),
    deliveryType: text(delivery.deliveryType || delivery.type || delivery.serviceType || "standard"),
    bookingId: idFrom(delivery, "bookingId", "requestId") || deliveryId,
    paymentStatus: text(delivery.paymentStatus || delivery.paymentState),
    senderEmail: text(delivery.senderEmail),
    riderEmail: text(delivery.riderEmail),
    giftId: idFrom(delivery, "giftId", "giftRequestId"),
    storyId: idFrom(delivery, "storyId", "giftStoryId"),
    healthOrderId: idFrom(delivery, "healthOrderId", "healthPickupId", "prescriptionPickupId"),
    businessOrderId: idFrom(delivery, "businessOrderId", "businessDeliveryId", "orderId"),
    walletTransactionId: idFrom(delivery, "walletTransactionId", "settlementId"),
    rothRewardId: idFrom(delivery, "rothRewardId", "trustLedgerId"),
    vanguardEnabled: delivery.vanguardEnabled === true || delivery.vanguardProtocolEnabled === true || delivery.vanguardRequired === true,
    proofOfDeliveryPath: text(evidence?.photoUrl || delivery.evidenceSummary?.latestPhotoPath || delivery.proofOfDeliveryPath) || null,
    trustPoints: Number.isFinite(Number(trustPoints)) ? Number(trustPoints) : 0,
    vehicleType: text(delivery.vehicleType || delivery.selectedVehicle || delivery.requiredVehicle) || null,
    region: text(delivery.region || delivery.dispatchRegion || delivery.pickupRegion) || null,
    verification: verified,
    proofOfDelivery: evidence || delivery.evidenceSummary || delivery.proofOfDelivery || null,
  };
}

function eventRef(db, eventId) {
  return db.collection("platformEvents").doc(eventId);
}

function subscriberRef(db, eventId, subscriber) {
  return db.collection("platformEventSubscribers").doc(`${eventId}_${subscriber}`);
}

async function claimSubscriber(db, eventId, subscriber) {
  const ref = subscriberRef(db, eventId, subscriber);
  const now = Date.now();
  let claimed = false;
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    const current = snapshot.exists ? snapshot.data() || {} : {};
    const startedAt = Number(current.startedAt || 0);
    if (current.status === "done" || current.status === "processing" && now - startedAt < PROCESSING_LEASE_MS) return;
    transaction.set(ref, {
      eventId,
      subscriber,
      status: "processing",
      startedAt: now,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    claimed = true;
  });
  return {claimed, ref};
}

async function completeSubscriber(ref) {
  await ref.set({status: "done", completedAt: FieldValue.serverTimestamp()}, {merge: true});
}

async function runSubscriber(db, event, subscriber, handler) {
  const claim = await claimSubscriber(db, event.eventId, subscriber);
  if (!claim.claimed) return {subscriber, skipped: true};
  try {
    await handler(db, event);
    await completeSubscriber(claim.ref);
    return {subscriber, skipped: false};
  } catch (error) {
    await claim.ref.set({status: "failed", error: `${error && error.message ? error.message : error}`.slice(0, 1000), failedAt: FieldValue.serverTimestamp()}, {merge: true});
    throw error;
  }
}

const subscribers = {
  sender: async (db, event) => {
    await db.collection("deliveryActivity").doc(event.eventId).set({
      eventId: event.eventId,
      eventType: EVENT_TYPE,
      deliveryId: event.deliveryId,
      senderId: event.senderId,
      status: "delivered",
      completedAt: event.completedAt,
      createdAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  },
  rider: async (db, event) => {
    if (!event.riderId) return;
    await db.collection("riderCompletionEvents").doc(event.eventId).set({
      ...event,
      status: "completed",
      createdAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  },
  recipient: async (db, event) => {
    if (!event.recipientId) return;
    await db.collection("recipientNotifications").doc(event.eventId).set({
      eventId: event.eventId,
      eventType: EVENT_TYPE,
      recipientId: event.recipientId,
      deliveryId: event.deliveryId,
      type: "delivery_completed",
      read: false,
      createdAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  },
  gifts: async (db, event) => {
    if (!event.giftId) return;
    await giftStoryAutomation.handleGiftDeliveryCompleted({
      db,
      delivery: {giftRequestId: event.giftId, status: "delivered", deliveryId: event.deliveryId},
      deliveryId: event.deliveryId,
    });
  },
  healthPlus: async (db, event) => {
    if (!event.healthOrderId) return;
    await db.collection("prescriptionPickups").doc(event.healthOrderId).set({
      deliveryCompletedEventId: event.eventId,
      status: "delivered",
      completedAt: event.completedAt,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    await db.collection("healthPlusNotifications").doc(event.eventId).set({
      eventId: event.eventId,
      pickupId: event.healthOrderId,
      type: "delivered",
      read: false,
      createdAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  },
  business: async (db, event) => {
    if (!event.businessOrderId) return;
    await db.collection("businessOrders").doc(event.businessOrderId).set({
      deliveryCompletedEventId: event.eventId,
      status: "delivered",
      completedAt: event.completedAt,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  },
  notifications: async (db, event) => {
    await platformNotifications.handleDeliveryCompletedNotification({event});
    await db.collection("platformNotifications").doc(event.eventId).set({
      eventId: event.eventId,
      eventType: EVENT_TYPE,
      deliveryId: event.deliveryId,
      senderId: event.senderId,
      riderId: event.riderId,
      recipientId: event.recipientId,
      template: "delivery_completed",
      createdAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  },
  analytics: async (db, event) => {
    await db.collection("deliveryAnalytics").doc(event.eventId).set({
      eventId: event.eventId,
      deliveryId: event.deliveryId,
      eventType: EVENT_TYPE,
      completedAt: event.completedAt,
      deliveryType: event.deliveryType,
      vehicleType: event.vehicleType,
      createdAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  },
  admin: async (db, event) => {
    await db.collection("deliveryAuditEvents").doc(event.eventId).set({
      ...event,
      auditType: EVENT_TYPE,
      immutable: true,
      createdAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  },
  iris: async (db, event) => {
    await db.collection("irisCompletionRecords").doc(event.eventId).set({
      eventId: event.eventId,
      deliveryId: event.deliveryId,
      status: "finalized",
      createdAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  },
  vanguard: async (db, event) => {
    if (!event.vanguardEnabled) return;
    await db.collection("vanguardCompletionEvents").doc(event.eventId).set({
      eventId: event.eventId,
      deliveryId: event.deliveryId,
      status: "completed",
      createdAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  },
  legends: async (db, event) => {
    await legends.handleDeliveryCompleted({db, deliveryId: event.deliveryId});
  },
  referrals: async (_db, event) => {
    await referrals.handleDeliveryCompletedReferral({delivery: event, deliveryId: event.deliveryId});
    if (event.giftId) {
      await referrals.handleGiftCompletedReferral({
        giftId: event.giftId,
        senderId: event.senderId,
        senderEmail: event.senderEmail,
        paymentStatus: event.paymentStatus,
      });
    }
    if (event.healthOrderId) {
      await referrals.handleHealthPlusCompletedReferral({
        pickupId: event.healthOrderId,
        userId: event.senderId,
        email: event.senderEmail,
      });
    }
  },
};

exports.EVENT_TYPE = EVENT_TYPE;
exports.EVENT_VERSION = EVENT_VERSION;
exports.buildDeliveryCompletedEvent = buildDeliveryCompletedEvent;
exports.publishDeliveryCompleted = ({transaction, db, event}) => {
  transaction.create(eventRef(db, event.eventId), event);
};
exports.onDeliveryCompletedEvent = functions.firestore.document("platformEvents/{eventId}").onCreate(async (snapshot) => {
  const event = snapshot.data() || {};
  if (event.eventType !== EVENT_TYPE || event.version !== EVENT_VERSION) return null;
  await Promise.all(Object.entries(subscribers).map(([name, handler]) => runSubscriber(getFirestore(), event, name, handler)));
  return null;
});
exports._private = {subscribers, claimSubscriber, eventRef, subscriberRef, runSubscriber};
