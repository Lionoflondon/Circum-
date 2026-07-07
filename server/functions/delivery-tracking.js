/* eslint-disable max-len */
"use strict";

const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue, GeoPoint} = require("firebase-admin/firestore");
const tracking = require("./sender-tracking-state-core");

function text(value) {
  return `${value || ""}`.trim();
}

function normalized(value) {
  return tracking.normalizeStatus(value);
}

function locationPatch(location) {
  if (!location || typeof location !== "object") return {};
  const lat = Number(location.latitude ?? location.lat);
  const lng = Number(location.longitude ?? location.lng);
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return {};
  return {
    riderLocation: {
      geopoint: new GeoPoint(lat, lng),
      latitude: lat,
      longitude: lng,
      updatedAt: FieldValue.serverTimestamp(),
    },
  };
}

async function findDelivery(db, transaction, deliveryId) {
  const directRef = db.collection("deliveryRequests").doc(deliveryId);
  const direct = await transaction.get(directRef);
  if (direct.exists) return {ref: directRef, id: direct.id, data: direct.data()};

  const query = await transaction.get(
      db.collection("deliveryRequests")
          .where("requestId", "==", deliveryId)
          .limit(1),
  );
  if (query.empty) return null;
  const doc = query.docs[0];
  return {ref: doc.ref, id: doc.id, data: doc.data()};
}

function assertRiderOwnsDelivery(delivery, riderId) {
  const assigned = text(
      delivery.riderId ||
      delivery.driverId ||
      delivery.assignedRiderId ||
      delivery.assignedDriverId,
  );
  if (!assigned || assigned !== riderId) {
    throw new functions.https.HttpsError("permission-denied", "Only the assigned rider can update this delivery.");
  }
}

function patchForTransition({action, nextStatus, riderId, location}) {
  const now = FieldValue.serverTimestamp();
  const patch = {
    status: nextStatus,
    updatedAt: now,
    lastRiderAction: action,
    lastRiderActionAt: now,
    ...locationPatch(location),
  };

  if (nextStatus === "navigating_to_pickup") patch.headingToPickupAt = now;
  if (nextStatus === "arrived_at_pickup") patch.arrivedAtPickupAt = now;
  if (nextStatus === "pickup_verified") {
    patch.collectionPinVerified = true;
    patch.collectionPinVerifiedAt = now;
    patch.collectionPinVerifiedBy = riderId;
  }
  if (nextStatus === "navigating_to_dropoff") {
    patch.collectedAt = now;
    patch.inTransitAt = now;
  }
  if (nextStatus === "arrived_at_dropoff") patch.arrivedAtDropoffAt = now;
  if (nextStatus === "delivered") {
    patch.deliveryPinVerified = true;
    patch.deliveryPinVerifiedAt = now;
    patch.deliveryPinVerifiedBy = riderId;
    patch.deliveredAt = now;
    patch.completedAt = now;
  }
  if (nextStatus === "issue_reported") {
    patch.issueReportedAt = now;
    patch.issueReportedBy = riderId;
  }
  if (nextStatus === "cancelled") {
    patch.cancelledAt = now;
    patch.cancelledBy = riderId;
  }
  return patch;
}

exports.updateDeliveryTrackingStatus = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Rider must be signed in.");
  }
  const deliveryId = text(data && (data.deliveryId || data.requestId));
  const action = normalized(data && data.action);
  const nextStatus = tracking.statusForRiderAction(action);
  if (!deliveryId) {
    throw new functions.https.HttpsError("invalid-argument", "deliveryId is required.");
  }
  if (!nextStatus) {
    throw new functions.https.HttpsError("invalid-argument", "Unsupported rider tracking action.");
  }

  const db = getFirestore();
  const riderId = context.auth.uid;
  const result = await db.runTransaction(async (transaction) => {
    const found = await findDelivery(db, transaction, deliveryId);
    if (!found) {
      throw new functions.https.HttpsError("not-found", "Delivery not found.");
    }
    const delivery = found.data || {};
    assertRiderOwnsDelivery(delivery, riderId);

    const currentStatus = normalized(delivery.status || delivery.deliveryStatus || "requested");
    if (!tracking.canTransitionDeliveryStatus(currentStatus, nextStatus)) {
      throw new functions.https.HttpsError("failed-precondition", `Cannot move delivery from ${currentStatus} to ${nextStatus}.`);
    }

    const patch = patchForTransition({
      action,
      nextStatus,
      riderId,
      location: data && data.location,
    });
    transaction.set(found.ref, patch, {merge: true});
    return {
      deliveryId: found.id,
      requestId: delivery.requestId || found.id,
      status: nextStatus,
      senderTrackingState: tracking.senderTrackingStateForBackendStatus(nextStatus),
    };
  });
  return result;
});

exports._private = {
  locationPatch,
  patchForTransition,
};
