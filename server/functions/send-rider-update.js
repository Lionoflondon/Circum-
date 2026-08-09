/* eslint-disable max-len, require-jsdoc */
const functions = require("firebase-functions/v1");
const {getFirestore} = require("firebase-admin/firestore");
const {hasAdminClaim} = require("./admin-auth");
const communicationEngine = require("./communication-engine");

const text = (value) => `${value || ""}`.trim();
const activeStatuses = new Set([
  "accepted", "assigned", "navigating_to_pickup", "arrived_at_pickup", "collected",
  "picked_up", "navigating_to_dropoff", "in_transit", "arrived_at_dropoff",
]);

function assignedRiderId(delivery = {}) {
  return text(delivery.riderId || delivery.driverId || delivery.assignedRiderId || delivery.assignedDriverId || delivery.courierId);
}

function senderId(delivery = {}) {
  return text(delivery.senderId || delivery.userId || delivery.customerId);
}

async function findDelivery(db, deliveryId) {
  if (deliveryId) {
    const direct = await db.collection("deliveryRequests").doc(deliveryId).get();
    if (direct.exists) return {id: direct.id, data: direct.data()};
    const byRequest = await db.collection("deliveryRequests").where("requestId", "==", deliveryId).limit(1).get();
    if (!byRequest.empty) return {id: byRequest.docs[0].id, data: byRequest.docs[0].data()};
  }
  return null;
}

async function findAssignedDelivery(db, riderId) {
  const snapshot = await db.collection("deliveryRequests").where("riderId", "==", riderId).limit(20).get();
  const matches = snapshot.docs.filter((doc) => activeStatuses.has(text(doc.data().status || doc.data().deliveryStatus).toLowerCase()));
  return matches.length === 1 ? {id: matches[0].id, data: matches[0].data()} : null;
}

async function profileToken(db, uid, role) {
  const collections = role === "rider" ? ["riderProfiles", "riders"] : ["users", "senders"];
  for (const collection of collections) {
    const snapshot = await db.collection(collection).doc(uid).get();
    if (!snapshot.exists) continue;
    const token = text(snapshot.data().fcmToken || snapshot.data().pushToken);
    if (token) return token;
  }
  return "";
}

function notificationCopy(status, recipientRole) {
  const copies = {
    accepted: ["Rider accepted", "A rider has accepted the delivery."],
    navigating_to_pickup: ["Rider en route", "The rider is on the way to pickup."],
    arrived_at_pickup: ["Rider arrived", "The rider has arrived at pickup."],
    collected: ["Delivery in progress", "The parcel has been collected."],
    navigating_to_dropoff: ["Delivery in progress", "The parcel is on the way to drop-off."],
    arrived_at_dropoff: ["Rider at drop-off", "The rider has arrived at drop-off."],
    delivered: ["Delivered", "The delivery is complete."],
    completed: ["Delivered", "The delivery is complete."],
  };
  return copies[status] || [recipientRole === "rider" ? "Delivery updated" : "Rider update", "The delivery status has been updated."];
}

async function handler(data, context, dependencies = {}) {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "User must be authenticated to send delivery updates.");
  }
  const db = dependencies.db || getFirestore();
  const messageData = data && data.data && typeof data.data === "object" ? data.data : {};
  const requestedDeliveryId = text(data && (data.deliveryId || data.requestId) || messageData.deliveryId || messageData.requestId);
  let delivery = await findDelivery(db, requestedDeliveryId);
  if (!delivery) delivery = await findAssignedDelivery(db, context.auth.uid);
  if (!delivery) throw new functions.https.HttpsError("not-found", "An active assigned delivery is required.");

  const actorId = context.auth.uid;
  const assigned = assignedRiderId(delivery.data);
  const owner = senderId(delivery.data);
  const admin = hasAdminClaim(context.auth.token || {});
  let recipientId = "";
  let recipientRole = "";
  if (actorId === assigned) {
    recipientId = owner;
    recipientRole = "sender";
  } else if (actorId === owner) {
    recipientId = assigned;
    recipientRole = "rider";
  } else if (admin) {
    recipientRole = text(data && data.recipientRole).toLowerCase() === "rider" ? "rider" : "sender";
    recipientId = recipientRole === "rider" ? assigned : owner;
  } else {
    throw new functions.https.HttpsError("permission-denied", "Only delivery participants may send this update.");
  }
  if (!recipientId) throw new functions.https.HttpsError("failed-precondition", "The delivery recipient is unavailable.");
  const requestedRecipient = text(data && (data.recipientId || data.targetUserId));
  if (requestedRecipient && requestedRecipient !== recipientId) {
    throw new functions.https.HttpsError("permission-denied", "Notification recipient does not match the delivery.");
  }

  const authoritativeToken = await profileToken(db, recipientId, recipientRole);
  const legacyToken = text(data && data.token);
  if (legacyToken && legacyToken !== authoritativeToken) {
    throw new functions.https.HttpsError("permission-denied", "Caller-supplied notification token is not authorized.");
  }

  const status = text(delivery.data.status || delivery.data.deliveryStatus).toLowerCase();
  const [title, body] = notificationCopy(status, recipientRole);
  const notificationId = await (dependencies.emitNotification || communicationEngine.emitNotification)({
    recipientId,
    recipientRole,
    type: "delivery_update",
    title,
    body,
    data: {
      bookingId: text(delivery.data.requestId || delivery.data.bookingId || delivery.id),
      deliveryId: delivery.id,
      status,
      category: "deliveries",
      correlationId: `delivery_update:${delivery.id}:${status}:${actorId}:${recipientId}`,
    },
  });
  return {success: true, notificationId, deliveryId: delivery.id};
}

const sendRiderUpdate = functions.runWith({enforceAppCheck: true}).https.onCall(handler);

module.exports = sendRiderUpdate;
module.exports._private = {assignedRiderId, findAssignedDelivery, findDelivery, handler, notificationCopy, profileToken, senderId};
