"use strict";

const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {createHash} = require("node:crypto");
const {riderCallable} = require("./rider-app-check");
const {ASSIGNMENT_FIELDS, assignedRiderId} = require("./delivery-assignment");
const {emitNotification} = require("./communication-engine");

const PRE_CUSTODY_STATES = new Set([
  "accepted", "assigned", "rider_assigned", "navigating_to_pickup", "en_route_to_pickup",
  "arrived_at_pickup", "waiting", "waiting_for_collection",
]);
const REASONS = new Set(["vehicle_breakdown", "unsafe_pickup", "sender_unavailable", "item_mismatch", "prohibited_item", "emergency", "cannot_complete", "other"]);
const text = (v) => `${v || ""}`.trim();
const fail = (code, message) => {
 throw new functions.https.HttpsError(code, message);
};

async function requestRiderCancellationHandler(data = {}, context = {}) {
  const uid = context.auth && context.auth.uid;
  if (!uid) fail("unauthenticated", "Sign in to release this delivery.");
  const deliveryId = text(data.deliveryId);
  const key = text(data.idempotencyKey);
  const reason = text(data.reason);
  if (!deliveryId || deliveryId.includes("/") || !key || key.length > 200 || !REASONS.has(reason)) {
    fail("invalid-argument", "Choose a release reason and retry from your delivery.");
  }
  const db = getFirestore();
  const eventId = createHash("sha256").update(JSON.stringify([deliveryId, uid, key])).digest("hex");
  const eventRef = db.collection("deliveryPolicyEvents").doc(`rider_release_${eventId}`);
  const ref = db.collection("deliveryRequests").doc(deliveryId);
  const result = await db.runTransaction(async (tx) => {
    const [event, snap] = await tx.getAll(eventRef, ref);
    if (event.exists) return {...event.data().result, duplicate: true};
    if (!snap.exists) fail("not-found", "Delivery not found.");
    const delivery = snap.data();
    if (assignedRiderId(delivery) !== uid) fail("permission-denied", "You are no longer assigned to this delivery.");
    const states = [delivery.status, delivery.state, delivery.deliveryStatus, delivery.deliveryStage].filter(Boolean);
    if (!states.length || states.some((s) => !PRE_CUSTODY_STATES.has(text(s).toLowerCase())) ||
        delivery.collectedAt || delivery.pickupVerifiedAt || delivery.completedAt || delivery.cancellationSettlementStatus) {
      fail("failed-precondition", "This delivery cannot be released. Contact Support if you have taken custody or cancellation is pending.");
    }
    const riderRefs = ["riders", "riderProfiles", "riderPresence"].map((c) => db.collection(c).doc(uid));
    const riderDocs = await tx.getAll(...riderRefs);
    const chatIds = [...new Set([deliveryId, text(delivery.requestId), text(delivery.chatId)].filter(Boolean))];
    const chats = await tx.getAll(...chatIds.map((id) => db.collection("chats").doc(id)));
    const activeRef = db.collection("activeDeliveries").doc(deliveryId);
    const active = await tx.get(activeRef);
    const result = {success: true, deliveryId, riderId: uid, redispatch: true, eventId, senderId: text(delivery.senderId || delivery.userId || delivery.customerId)};
    const patch = {
      status: "requested", state: FieldValue.delete(), deliveryStatus: "requested", deliveryStage: "requested",
      dispatchStatus: "requested", matchingStatus: "available", dispatchBlocked: false, broadcastBlocked: false,
      removedFromActiveQueues: false, updatedAt: FieldValue.serverTimestamp(),
      riderCancellation: {riderId: uid, reason, detail: text(data.detail).slice(0, 500), eventId},
      rematchEventId: eventId,
    };
    for (const field of [...ASSIGNMENT_FIELDS, "acceptedAt", "assignedAt", "riderName", "driverName", "courierName", "driverVehicle", "driverPlateNumber", "arrivedAt", "pickupArrivedAt", "waitingStartedAt", "offerExpiresAt", "dispatchExpiresAt", "matchingExpiresAt", "expiresAt"]) patch[field] = FieldValue.delete();
    tx.update(ref, patch);
    for (const doc of riderDocs) {
      if (!doc.exists) continue;
      const value = doc.data();
      const locks = [value.activeDeliveryId, value.currentDeliveryId].filter(Boolean);
      if (locks.some((id) => ![deliveryId, delivery.requestId].includes(id))) continue;
      tx.update(doc.ref, {
        activeDeliveryId: FieldValue.delete(), currentDeliveryId: FieldValue.delete(), busy: false,
        // Require a new presence acknowledgement before dispatch resumes.
        availabilityStatus: "offline", isOnline: false, dispatchEligible: false,
        status: "offline", presenceState: "offline",
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
    for (const chat of chats) {
      if (!chat.exists) continue;
      const value = chat.data();
      tx.update(chat.ref, {
        participants: (value.participants || []).filter((id) => id !== uid),
        participantRoles: Object.fromEntries(Object.entries(value.participantRoles || {}).filter(([id]) => id !== uid)),
        assignedRiderId: FieldValue.delete(), updatedAt: FieldValue.serverTimestamp(),
      });
    }
    if (active.exists && (!assignedRiderId(active.data()) || assignedRiderId(active.data()) === uid)) tx.delete(activeRef);
    tx.delete(db.doc(`riderOfferProjections/${uid}/offers/${deliveryId}`));
    tx.delete(db.doc(`riderOfferAuthorizations/${uid}/jobs/${deliveryId}`));
    // An immutable reliability event records the impact without inventing a TP/rank penalty.
    tx.create(db.collection("riderOperationalAudit").doc(`release_${eventId}`), {
      action: "rider_cancellation", riderId: uid, deliveryId, reason, eventId,
      reliabilityImpact: "released_before_pickup", createdAt: FieldValue.serverTimestamp(),
    });
    tx.create(eventRef, {type: "rider_cancellation", result, createdAt: FieldValue.serverTimestamp()});
    return result;
  });
  // Replays also repair interrupted notification persistence; the existing engine deduplicates records.
  for (const [recipientId, role] of [[uid, "rider"], [result.senderId, "sender"]]) {
    if (!recipientId) continue;
    await emitNotification({recipientId, recipientRole: role, type: "rider_unavailable",
      title: role === "rider" ? "Delivery released" : "Finding another Rider",
      body: role === "rider" ? "Your job was released. Go online when you are ready." : "Your delivery is being offered to another Rider.",
      data: {deliveryId}, dedupeKey: `rider_release:${eventId}:${recipientId}`});
  }
  return result;
}

exports.requestRiderCancellation = riderCallable(requestRiderCancellationHandler);
exports.requestRiderCancellationHandler = requestRiderCancellationHandler;
exports.PRE_CUSTODY_STATES = PRE_CUSTODY_STATES;
