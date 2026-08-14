/* eslint-disable max-len, require-jsdoc */
"use strict";

const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue, Timestamp} = require("firebase-admin/firestore");
const {requireAdmin} = require("./admin-auth");
const {canGoOnline} = require("./rider-presence-core");
const {giftReady} = require("./movement-ledger");
const scheduled = require("./scheduled-delivery-core");
const {dispatchDeliveryRequest} = require("./send-package");

function text(value) {
  return `${value || ""}`.trim();
}

function requireAuth(context) {
  if (!context.auth || !context.auth.uid) {
    throw new functions.https.HttpsError("unauthenticated", "Sign in first.");
  }
  return context.auth.uid;
}

async function assertNoActiveDelivery(db, riderId, transaction) {
  const presenceRef = db.collection("riderPresence").doc(riderId);
  const presenceSnap = await transaction.get(presenceRef);
  const presence = presenceSnap.exists ? presenceSnap.data() || {} : {};
  if (presence.busy === true || text(presence.activeDeliveryId || presence.currentDeliveryId)) {
    throw new functions.https.HttpsError("failed-precondition", "Rider already has an active delivery.");
  }
  return {presenceRef, presence};
}

async function adminScheduleGiftDeliveryCore({db, giftId, riderId = "", scheduledAt, scheduledWindow, adminId}) {
  const scheduleMs = scheduled.millis(scheduledAt);
  if (!scheduleMs || scheduleMs <= Date.now()) {
    throw new functions.https.HttpsError("invalid-argument", "Choose a future delivery time.");
  }
  const deliveryId = `gift_${giftId}`;
  const giftRef = db.collection("giftRequests").doc(giftId);
  const deliveryRef = db.collection("deliveryRequests").doc(deliveryId);
  await db.runTransaction(async (transaction) => {
    const reads = [transaction.get(giftRef), transaction.get(deliveryRef)];
    const profileRef = riderId ? db.collection("riderProfiles").doc(riderId) : null;
    const presenceRef = riderId ? db.collection("riderPresence").doc(riderId) : null;
    if (profileRef) reads.push(transaction.get(profileRef));
    if (presenceRef) reads.push(transaction.get(presenceRef));
    const [giftSnap, deliverySnap, profileSnap, presenceSnap] = await Promise.all(reads);
    if (!giftSnap.exists) {
      throw new functions.https.HttpsError("not-found", "Gift request not found.");
    }
    const gift = giftSnap.data() || {};
    if (!giftReady(gift)) {
      throw new functions.https.HttpsError("failed-precondition", "Gift is not ready for delivery.");
    }
    if (riderId) {
      if (!profileSnap || !profileSnap.exists || !canGoOnline(profileSnap.data() || {})) {
        throw new functions.https.HttpsError("failed-precondition", "Reserved Rider is not work-ready.");
      }
      const presence = presenceSnap && presenceSnap.exists ? presenceSnap.data() || {} : {};
      if (presence.busy === true || text(presence.activeDeliveryId || presence.currentDeliveryId)) {
        throw new functions.https.HttpsError("failed-precondition", "Reserved Rider already has an active delivery.");
      }
    }
    const current = deliverySnap.exists ? deliverySnap.data() || {} : {};
    const currentState = scheduled.activationState(current);
    if (deliverySnap.exists && !["scheduled", "invalid_schedule", "open"].includes(currentState)) {
      throw new functions.https.HttpsError("failed-precondition", "Gift delivery can no longer be scheduled.");
    }
    const previousRiderId = scheduled.assignedRiderId(current);
    const schedule = Timestamp.fromMillis(scheduleMs);
    const patch = {
      ...current,
      deliveryId,
      requestId: deliveryId,
      giftRequestId: giftId,
      giftOrderId: giftId,
      productType: "gift",
      sourceModule: "gifts",
      serviceType: "GIFTS",
      fulfilmentMode: "scheduled",
      fulfilmentStrategy: scheduled.STRATEGIES.SCHEDULED_DELIVERY,
      status: "scheduled",
      deliveryStatus: "scheduled",
      deliveryStage: "scheduled",
      dispatchStatus: "held",
      matchingStatus: "held",
      assignedRiderId: riderId || null,
      riderId: riderId || null,
      riderReservationMode: riderId ? "admin_reserved" : "competitive_at_activation",
      scheduledAt: schedule,
      scheduledWindow: text(scheduledWindow) || null,
      trustPoints: 5,
      scheduleCreatedBy: adminId,
      scheduleCreatedAt: current.scheduleCreatedAt || FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    };
    transaction.set(deliveryRef, patch, {merge: true});
    transaction.set(giftRef, {
      deliveryId,
      assignedRiderId: riderId || null,
      riderId: riderId || null,
      fulfilmentMode: "scheduled",
      fulfilmentStrategy: scheduled.STRATEGIES.SCHEDULED_DELIVERY,
      riderReservationMode: patch.riderReservationMode,
      status: "scheduled",
      deliveryStatus: "scheduled",
      scheduledAt: schedule,
      scheduledWindow: text(scheduledWindow) || null,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    transaction.set(db.collection("adminAuditLogs").doc(), {
      actionType: riderId ? "gift_delivery_scheduled_with_rider_reservation" : "gift_delivery_scheduled_competitive",
      deliveryId,
      giftId,
      previousRiderId: previousRiderId || null,
      riderId: riderId || null,
      scheduledAt: schedule,
      performedBy: adminId,
      createdAt: FieldValue.serverTimestamp(),
    });
  });
  return {
    deliveryId,
    giftId,
    riderId: riderId || null,
    offerMode: riderId ? "admin_reserved" : "competitive_at_activation",
    status: "scheduled",
    scheduledAt: new Date(scheduleMs).toISOString(),
  };
}

const adminScheduleGiftDelivery = functions.runWith({enforceAppCheck: true}).https.onCall(async (data, context) => {
  const adminId = requireAdmin(context, "Only an administrator can schedule a Gift delivery.");
  const giftId = text(data && data.giftId);
  if (!giftId) {
    throw new functions.https.HttpsError("invalid-argument", "giftId is required.");
  }
  return adminScheduleGiftDeliveryCore({
    db: getFirestore(),
    giftId,
    riderId: text(data && data.riderId),
    scheduledAt: data && data.scheduledAt,
    scheduledWindow: data && (data.scheduledWindow || data.window),
    adminId,
  });
});

const adminScheduleHealthPlusDelivery = functions.runWith({enforceAppCheck: true}).https.onCall(async (data, context) => {
  const adminId = requireAdmin(context, "Only an administrator can schedule Health+ dispatch timing.");
  const pickupId = text(data && data.pickupId);
  const scheduleMs = scheduled.millis(data && data.scheduledAt);
  if (!pickupId || !scheduleMs || scheduleMs <= Date.now()) {
    throw new functions.https.HttpsError("invalid-argument", "pickupId and a future scheduledAt are required.");
  }
  const db = getFirestore();
  const pickupRef = db.collection("prescriptionPickups").doc(pickupId);
  const deliveryRef = db.collection("deliveryRequests").doc(`health_${pickupId}`);
  const schedule = Timestamp.fromMillis(scheduleMs);
  await db.runTransaction(async (transaction) => {
    const [pickupSnap, deliverySnap] = await Promise.all([
      transaction.get(pickupRef),
      transaction.get(deliveryRef),
    ]);
    if (!pickupSnap.exists) {
      throw new functions.https.HttpsError("not-found", "Health+ pickup not found.");
    }
    const delivery = deliverySnap.exists ? deliverySnap.data() || {} : {};
    if (scheduled.assignedRiderId(delivery)) {
      throw new functions.https.HttpsError("failed-precondition", "Health+ delivery is already assigned.");
    }
    transaction.set(pickupRef, {
      useScheduledDeliveryEngine: true,
      scheduledAt: schedule,
      scheduledWindow: text(data.scheduledWindow || data.window) || null,
      status: "scheduled",
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    transaction.set(deliveryRef, {
      deliveryId: `health_${pickupId}`,
      requestId: `health_${pickupId}`,
      healthPlusPickupId: pickupId,
      productType: "health_plus",
      sourceModule: "health_plus",
      serviceType: "HEALTH_PLUS",
      useScheduledDeliveryEngine: true,
      fulfilmentMode: "scheduled",
      fulfilmentStrategy: scheduled.STRATEGIES.SCHEDULED_DELIVERY,
      status: "scheduled",
      deliveryStatus: "scheduled",
      deliveryStage: "scheduled",
      matchingStatus: "held",
      dispatchStatus: "held",
      scheduledAt: schedule,
      scheduledWindow: text(data.scheduledWindow || data.window) || null,
      trustPoints: 6,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    transaction.set(db.collection("adminAuditLogs").doc(), {
      actionType: "health_plus_competitive_dispatch_scheduled",
      pickupId,
      deliveryId: `health_${pickupId}`,
      scheduledAt: schedule,
      performedBy: adminId,
      createdAt: FieldValue.serverTimestamp(),
    });
  });
  return {
    pickupId,
    deliveryId: `health_${pickupId}`,
    offerMode: "competitive_at_activation",
    scheduledAt: new Date(scheduleMs).toISOString(),
  };
});

const getRiderScheduledJobs = functions.runWith({enforceAppCheck: true}).https.onCall(async (_, context) => {
  const riderId = requireAuth(context);
  const snapshot = await getFirestore().collection("deliveryRequests")
      .where("assignedRiderId", "==", riderId)
      .limit(50)
      .get();
  const jobs = snapshot.docs
      .map((doc) => scheduled.scheduledJobProjection(doc.id, doc.data() || {}))
      .filter((job) => job.assignedRiderId === riderId &&
        ["scheduled", "ready"].includes(job.status))
      .sort((a, b) => scheduled.millis(a.scheduledAt) - scheduled.millis(b.scheduledAt));
  return {jobs};
});

async function activateScheduledDelivery({db, deliveryId, now = Date.now()}) {
  const deliveryRef = db.collection("deliveryRequests").doc(deliveryId);
  return db.runTransaction(async (transaction) => {
    const deliverySnap = await transaction.get(deliveryRef);
    if (!deliverySnap.exists) return {activated: false, reason: "missing"};
    const delivery = deliverySnap.data() || {};
    const currentStatus = text(delivery.status || delivery.deliveryStatus)
        .toLowerCase()
        .replace(/[\s-]+/g, "_");
    if (currentStatus !== "scheduled") {
      return {activated: false, reason: "already_activated"};
    }
    const plan = scheduled.activationPlan(delivery, now);
    if (!plan.activate) {
      return {activated: false, reason: scheduled.activationState(delivery, now)};
    }
    const riderId = scheduled.assignedRiderId(delivery);
    if (plan.mode === "open_dispatch") {
      transaction.set(deliveryRef, {
        status: "requested",
        deliveryStatus: "requested",
        deliveryStage: "requested",
        dispatchStatus: "requested",
        matchingStatus: "available",
        scheduleActivatedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
      return {
        activated: true,
        deliveryId,
        mode: "open_dispatch",
        ownerId: text(delivery.senderId || delivery.userId || delivery.customerId),
      };
    }
    const {presenceRef, presence} = await assertNoActiveDelivery(db, riderId, transaction);
    transaction.set(deliveryRef, {
      status: "ready",
      deliveryStatus: "ready",
      deliveryStage: "ready",
      dispatchStatus: "assigned",
      matchingStatus: "assigned",
      scheduleActivatedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    const online = presence.isOnline === true;
    transaction.set(presenceRef, {
      riderId,
      busy: true,
      availabilityStatus: "busy",
      dispatchEligible: false,
      activeDeliveryId: deliveryId,
      currentDeliveryId: deliveryId,
      updatedAt: FieldValue.serverTimestamp(),
      source: "scheduledDeliveryActivation",
    }, {merge: true});
    for (const collection of ["riders", "riderProfiles"]) {
      transaction.set(db.collection(collection).doc(riderId), {
        activeDelivery: deliveryId,
        activeDeliveryId: deliveryId,
        currentDeliveryId: deliveryId,
        availabilityStatus: "busy",
        isOnline: online,
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    }
    return {activated: true, deliveryId, riderId, mode: "assigned"};
  });
}

async function activateDueScheduledDeliveriesCore({db, now = Date.now()}) {
  const snapshot = await db.collection("deliveryRequests")
      .where("status", "==", "scheduled")
      .limit(200)
      .get();
  const due = snapshot.docs.filter((doc) => {
    const delivery = doc.data() || {};
    return scheduled.fulfilmentStrategy(delivery) !== scheduled.STRATEGIES.OPEN_DISPATCH &&
      scheduled.scheduledAtMillis(delivery) > 0 &&
      scheduled.scheduledAtMillis(delivery) <= now;
  });
  const results = [];
  for (const doc of due) {
    try {
      const result = await activateScheduledDelivery({db, deliveryId: doc.id, now});
      if (result.activated && result.mode === "open_dispatch") {
        await dispatchDeliveryRequest({
          db,
          requestId: doc.id,
          uid: result.ownerId,
          source: "activateDueScheduledDeliveries",
        });
      }
      results.push(result);
    } catch (error) {
      console.error("scheduled_delivery_activation_failed", {deliveryId: doc.id, code: error.code || "unknown"});
      results.push({activated: false, deliveryId: doc.id, reason: error.code || "activation_failed"});
    }
  }
  return results;
}

const activateDueScheduledDeliveries = functions.pubsub
    .schedule("every 1 minutes")
    .timeZone("Europe/London")
    .onRun(() => activateDueScheduledDeliveriesCore({db: getFirestore()}));

module.exports = {
  activateDueScheduledDeliveries,
  activateDueScheduledDeliveriesCore,
  activateScheduledDelivery,
  adminScheduleGiftDelivery,
  adminScheduleGiftDeliveryCore,
  adminScheduleHealthPlusDelivery,
  getRiderScheduledJobs,
};
