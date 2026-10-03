/* eslint-disable max-len, require-jsdoc */
"use strict";

const functions = require("firebase-functions/v1");
const {randomUUID} = require("node:crypto");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const legends = require("./legends");
const referrals = require("./referrals");
const {
  createDeliveryCore,
  DELIVERY_DOMAIN_VERSION,
} = require("./delivery-domain-core");

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

function buildDeliveryCompletedEvent({
  deliveryId,
  delivery = {},
  riderId,
  trustPoints,
  completedAt,
  verification,
  evidence,
}) {
  const eventId = `delivery_completed_${deliveryId}`;
  const core = createDeliveryCore({
    id: deliveryId,
    status: "delivered",
    senderId: delivery.senderId || delivery.userId || delivery.customerId,
    recipientId:
      delivery.recipientId || delivery.receiverId || delivery.recipientUserId,
    riderId:
      riderId ||
      delivery.riderId ||
      delivery.assignedRiderId ||
      delivery.driverId,
    createdAt: delivery.createdAt,
    completedAt: completedAt || delivery.completedAt || delivery.deliveredAt,
    dispatchId: delivery.dispatchId,
    trackingId: delivery.trackingId,
    pricingId: delivery.pricingId,
    paymentId: delivery.paymentId || delivery.stripePaymentIntentId,
    evidenceId: idFrom(evidence, "evidenceId") || delivery.evidenceId,
  });
  const verified = verification || {
    pickupPinVerified:
      delivery.collectionPinVerified === true ||
      delivery.pickupPinVerified === true,
    deliveryPinVerified:
      delivery.deliveryPinVerified === true ||
      delivery.receiverPinVerified === true,
    evidenceVerified:
      delivery.evidenceVerified === true ||
      Number(delivery.evidenceSummary?.verifiedPhotoCount || 0) > 0,
  };
  return {
    eventId,
    eventType: EVENT_TYPE,
    version: EVENT_VERSION,
    deliveryDomainVersion: DELIVERY_DOMAIN_VERSION,
    core,
    deliveryId,
    senderId: idFrom(delivery, "senderId", "userId", "customerId"),
    recipientId: idFrom(
      delivery,
      "recipientId",
      "receiverId",
      "recipientUserId",
    ),
    riderId:
      riderId ||
      idFrom(
        delivery,
        "riderId",
        "driverId",
        "assignedRiderId",
        "assignedDriverId",
      ),
    completedAt: completedAt || FieldValue.serverTimestamp(),
    publishedAt: FieldValue.serverTimestamp(),
    deliveryType: text(
      delivery.deliveryType ||
        delivery.type ||
        delivery.serviceType ||
        "standard",
    ),
    bookingId: idFrom(delivery, "bookingId", "requestId") || deliveryId,
    paymentStatus: text(delivery.paymentStatus || delivery.paymentState),
    senderEmail: text(delivery.senderEmail),
    riderEmail: text(delivery.riderEmail),
    giftId: idFrom(delivery, "giftId", "giftRequestId"),
    storyId: idFrom(delivery, "storyId", "giftStoryId"),
    healthOrderId: idFrom(
      delivery,
      "healthOrderId",
      "healthPickupId",
      "prescriptionPickupId",
    ),
    businessOrderId: idFrom(
      delivery,
      "businessOrderId",
      "businessDeliveryId",
      "orderId",
    ),
    walletTransactionId: idFrom(
      delivery,
      "walletTransactionId",
      "settlementId",
    ),
    rothRewardId: idFrom(delivery, "rothRewardId", "trustLedgerId"),
    vanguardEnabled:
      delivery.vanguardEnabled === true ||
      delivery.vanguardProtocolEnabled === true ||
      delivery.vanguardRequired === true,
    proofOfDeliveryPath:
      text(
        evidence?.photoUrl ||
          delivery.evidenceSummary?.latestPhotoPath ||
          delivery.proofOfDeliveryPath,
      ) || null,
    evidenceId:
      idFrom(evidence, "evidenceId") ||
      text(evidence?.photoUrl) ||
      idFrom(delivery, "evidenceId"),
    trustPoints: Number.isFinite(Number(trustPoints)) ? Number(trustPoints) : 0,
    vehicleType:
      text(
        delivery.vehicleType ||
          delivery.selectedVehicle ||
          delivery.requiredVehicle,
      ) || null,
    region:
      text(
        delivery.region || delivery.dispatchRegion || delivery.pickupRegion,
      ) || null,
    verification: verified,
    proofOfDelivery:
      evidence || delivery.evidenceSummary || delivery.proofOfDelivery || null,
  };
}

function eventRef(db, eventId) {
  return db.collection("platformEvents").doc(eventId);
}

function subscriberRef(db, eventId, subscriber) {
  return db
    .collection("platformEventSubscribers")
    .doc(`${eventId}_${subscriber}`);
}

async function claimSubscriber(db, eventId, subscriber) {
  const ref = subscriberRef(db, eventId, subscriber);
  const now = Date.now();
  const claimId = randomUUID();
  let claimed = false;
  let busy = false;
  await db.runTransaction(async (transaction) => {
    claimed = false;
    busy = false;
    const snapshot = await transaction.get(ref);
    const current = snapshot.exists ? snapshot.data() || {} : {};
    const startedAt = Number(current.startedAt || 0);
    if (
      current.status === "done"
    ) {
      return;
    }
    if (current.status === "processing" && now - startedAt < PROCESSING_LEASE_MS) {
      busy = true;
      return;
    }
    transaction.set(
      ref,
      {
        eventId,
        subscriber,
        status: "processing",
        claimId,
        startedAt: now,
        updatedAt: FieldValue.serverTimestamp(),
      },
      {merge: true},
    );
    claimed = true;
  });
  return {claimed, busy, ref, claimId};
}

async function settleSubscriber(db, claim, patch) {
  await db.runTransaction(async (tx) => {
    const current = await tx.get(claim.ref);
    if (current.data()?.claimId !== claim.claimId) throw Object.assign(new Error("completion_subscriber_lease_lost"), {code: "aborted"});
    tx.set(claim.ref, patch, {merge: true});
  });
}

async function runSubscriber(db, event, subscriber, handler) {
  const claim = await claimSubscriber(db, event.eventId, subscriber);
  if (claim.busy) throw Object.assign(new Error("completion_subscriber_busy"), {code: "aborted"});
  if (!claim.claimed) return {subscriber, skipped: true};
  try {
    const result = await handler(db, event);
    if (completionNeedsRetry(result)) throw Object.assign(new Error("completion_subscriber_requires_retry"), {code: "aborted"});
    await settleSubscriber(db, claim, {status: "done", completedAt: FieldValue.serverTimestamp()});
    return {subscriber, skipped: false};
  } catch (error) {
    await settleSubscriber(db, claim,
      {
        status: "failed",
        error: `${error && error.message ? error.message : error}`.slice(
          0,
          1000,
        ),
        failedAt: FieldValue.serverTimestamp(),
      },
    );
    throw error;
  }
}

function completionNeedsRetry(result) {
  if (!result || typeof result !== "object") return false;
  return String(result.status || "").toLowerCase() === "review" || result.needsReview === true || Object.values(result).some((value) => value && typeof value === "object" && completionNeedsRetry(value));
}

async function createCompletionRecord(db, ref, payload) {
  return db.runTransaction(async (tx) => {
    const existing = await tx.get(ref);
    if (!existing.exists) tx.create(ref, payload);
  });
}

async function projectLinkedCompletion(db, event, collection, id) {
  if (!id) return {status: "ignored"};
  return db.runTransaction(async (tx) => {
    const sourceRef = db.collection("deliveryRequests").doc(event.deliveryId);
    const targetRef = db.collection(collection).doc(id);
    const noticeRef = collection === "prescriptionPickups" ? db.collection("healthPlusNotifications").doc(event.eventId) : null;
    const [source, target, notice] = await Promise.all([tx.get(sourceRef), tx.get(targetRef), noticeRef ? tx.get(noticeRef) : null]);
    const current = source.data() || {}; const linked = target.data() || {};
    if (!source.exists || !target.exists || !["completed", "delivered"].includes(String(current.status || current.deliveryStatus).toLowerCase())) return {status: "ignored", reason: "current_completion_required"};
    const binding = collection === "prescriptionPickups" ? current.healthPlusPickupId || current.healthOrderId || current.healthPickupId || current.prescriptionPickupId : current.businessOrderId || current.businessDeliveryId || current.orderId;
    if (String(binding || "") !== String(id) || (linked.deliveryId && linked.deliveryId !== event.deliveryId) || (linked.riderId && linked.riderId !== current.riderId) || (event.riderId && event.riderId !== current.riderId) || ["cancelled", "canceled", "refunded", "archived", "archived_expired", "under_review", "disputed", "dispute"].includes(String(linked.status || "").toLowerCase()) || linked.underReview === true || linked.disputeOpen === true || linked.paymentInvestigation === true) return {status: "ignored", reason: "current_binding_required"};
    if (linked.deliveryCompletedEventId === event.eventId) return {status: "already_projected"};
    tx.set(targetRef, {deliveryCompletedEventId: event.eventId, status: String(linked.status || "").toLowerCase() === "completed" ? "completed" : "delivered", completedAt: event.completedAt, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
    if (noticeRef && !notice.exists) tx.create(noticeRef, {eventId: event.eventId, pickupId: id, type: "delivered", read: false, createdAt: FieldValue.serverTimestamp()});
    return {status: "projected"};
  });
}

const subscribers = {
  sender: async (db, event) => {
    await createCompletionRecord(db, db.collection("deliveryActivity").doc(event.eventId),
      {
        eventId: event.eventId,
        eventType: EVENT_TYPE,
        deliveryId: event.deliveryId,
        senderId: event.senderId,
        status: "delivered",
        completedAt: event.completedAt,
        createdAt: FieldValue.serverTimestamp(),
      },
    );
  },
  rider: async (db, event) => {
    if (!event.riderId) return;
    await createCompletionRecord(db, db.collection("riderCompletionEvents").doc(event.eventId),
      {
        ...event,
        status: "completed",
        createdAt: FieldValue.serverTimestamp(),
      },
    );
  },
  recipient: async (db, event) => {
    if (!event.recipientId) return;
    await createCompletionRecord(db, db.collection("recipientNotifications").doc(event.eventId),
      {
        eventId: event.eventId,
        eventType: EVENT_TYPE,
        recipientId: event.recipientId,
        deliveryId: event.deliveryId,
        type: "delivery_completed",
        read: false,
        createdAt: FieldValue.serverTimestamp(),
      },
    );
  },
  // Gifts remain owned by the deliveryRequests Firestore completion path.
  // The platform event bus must not become a second Story consumer.
  gifts: async () => ({
    status: "ignored",
    reason: "platform_event_not_canonical",
  }),
  healthPlus: async (db, event) => projectLinkedCompletion(db, event, "prescriptionPickups", event.healthOrderId),
  business: async (db, event) => projectLinkedCompletion(db, event, "businessOrders", event.businessOrderId),
  notifications: async (db, event) => {
    // Existing deliveryRequests Eventarc notifications own customer delivery messages.
    // This bus records completion metadata; it must not create a second sender.
    await createCompletionRecord(db, db.collection("platformNotifications").doc(event.eventId),
      {
        eventId: event.eventId,
        eventType: EVENT_TYPE,
        deliveryId: event.deliveryId,
        senderId: event.senderId,
        riderId: event.riderId,
        recipientId: event.recipientId,
        template: "delivery_completed",
        canonicalNotificationOwner: "circum-sender-notification-events",
        createdAt: FieldValue.serverTimestamp(),
      },
    );
    return {status: "ignored", reason: "platform_event_not_canonical_notification_owner"};
  },
  analytics: async (db, event) => {
    await createCompletionRecord(db, db.collection("deliveryAnalytics").doc(event.eventId),
      {
        eventId: event.eventId,
        deliveryId: event.deliveryId,
        eventType: EVENT_TYPE,
        completedAt: event.completedAt,
        deliveryType: event.deliveryType,
        vehicleType: event.vehicleType,
        createdAt: FieldValue.serverTimestamp(),
      },
    );
  },
  admin: async (db, event) => {
    await createCompletionRecord(db, db.collection("deliveryAuditEvents").doc(event.eventId),
      {
        ...event,
        auditType: EVENT_TYPE,
        immutable: true,
        createdAt: FieldValue.serverTimestamp(),
      },
    );
  },
  iris: async (db, event) => {
    await createCompletionRecord(db, db.collection("irisCompletionRecords").doc(event.eventId),
      {
        eventId: event.eventId,
        deliveryId: event.deliveryId,
        status: "finalized",
        createdAt: FieldValue.serverTimestamp(),
      },
    );
  },
  vanguard: async (db, event) => {
    if (!event.vanguardEnabled) return;
    await createCompletionRecord(db, db.collection("vanguardCompletionEvents").doc(event.eventId),
      {
        eventId: event.eventId,
        deliveryId: event.deliveryId,
        status: "completed",
        createdAt: FieldValue.serverTimestamp(),
      },
    );
  },
  legends: async (db, event) => {
    await legends.handleDeliveryCompleted({db, deliveryId: event.deliveryId});
  },
  referrals: async (db, event) => {
    const deliveryResult = await referrals.handleDeliveryCompletedReferral({
      db,
      delivery: event,
      deliveryId: event.deliveryId,
    });
    if (completionNeedsRetry(deliveryResult)) return deliveryResult;
    if (event.giftId) {
      const giftResult = await referrals.handleGiftCompletedReferral({
        db,
        giftId: event.giftId,
        senderId: event.senderId,
        senderEmail: event.senderEmail,
        paymentStatus: event.paymentStatus,
      });
      if (completionNeedsRetry(giftResult)) return giftResult;
    }
    if (event.healthOrderId) {
      return referrals.handleHealthPlusCompletedReferral({
        db,
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
exports.onDeliveryCompletedEvent = functions
  .runWith({failurePolicy: true})
  .firestore.document("platformEvents/{eventId}")
  .onCreate(async (snapshot) => {
    const event = snapshot.data() || {};
    if (event.eventType !== EVENT_TYPE || event.version !== EVENT_VERSION) {
      return null;
    }
    await Promise.all(
      Object.entries(subscribers).map(([name, handler]) =>
        runSubscriber(getFirestore(), event, name, handler),
      ),
    );
    return null;
  });
exports._private = {
  subscribers,
  projectLinkedCompletion,
  settleSubscriber,
  claimSubscriber,
  eventRef,
  subscriberRef,
  runSubscriber,
  completionNeedsRetry,
};
