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

function liveLocationPatch(location) {
  if (!location || typeof location !== "object") return {};
  const lat = Number(location.latitude ?? location.lat);
  const lng = Number(location.longitude ?? location.lng);
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return {};
  const heading = Number(location.heading ?? location.bearing);
  const speed = Number(location.speed);
  return {
    riderLiveLocation: {
      geopoint: new GeoPoint(lat, lng),
      latitude: lat,
      longitude: lng,
      ...(Number.isFinite(heading) ? {heading} : {}),
      ...(Number.isFinite(speed) ? {speed} : {}),
      updatedAt: FieldValue.serverTimestamp(),
    },
  };
}

function timestampMs(value) {
  if (!value) return 0;
  if (typeof value.toMillis === "function") return value.toMillis();
  if (value instanceof Date) return value.getTime();
  if (typeof value === "number") return value;
  return 0;
}

function distanceMeters(a, b) {
  if (!a || !b) return Number.POSITIVE_INFINITY;
  const lat1 = Number(a.latitude ?? a.lat);
  const lon1 = Number(a.longitude ?? a.lng);
  const lat2 = Number(b.latitude ?? b.lat);
  const lon2 = Number(b.longitude ?? b.lng);
  if (![lat1, lon1, lat2, lon2].every(Number.isFinite)) return Number.POSITIVE_INFINITY;
  const radians = (deg) => deg * Math.PI / 180;
  const dLat = radians(lat2 - lat1);
  const dLon = radians(lon2 - lon1);
  const rLat1 = radians(lat1);
  const rLat2 = radians(lat2);
  const h = Math.sin(dLat / 2) ** 2 +
    Math.cos(rLat1) * Math.cos(rLat2) * Math.sin(dLon / 2) ** 2;
  return 6371000 * 2 * Math.atan2(Math.sqrt(h), Math.sqrt(1 - h));
}

function headingDelta(a, b) {
  const h1 = Number(a);
  const h2 = Number(b);
  if (!Number.isFinite(h1) || !Number.isFinite(h2)) return 0;
  const delta = Math.abs(((h2 - h1 + 540) % 360) - 180);
  return delta;
}

function shouldWriteLiveLocation(previous, next, nowMs = Date.now()) {
  if (!next || !next.riderLiveLocation) return false;
  const previousLocation = previous && previous.riderLiveLocation;
  if (!previousLocation) return true;
  const ageMs = nowMs - timestampMs(previousLocation.updatedAt);
  if (ageMs < 10000) return false;
  const moved = distanceMeters(previousLocation, next.riderLiveLocation);
  const turned = headingDelta(previousLocation.heading, next.riderLiveLocation.heading);
  if (moved >= 25 || turned >= 15) return true;
  return ageMs >= 30000;
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

function assertRiderOperational(rider = {}) {
  const state = normalized(
      rider.accountState || rider.accountStatus || rider.status || rider.approvalStatus,
  );
  if (["suspended", "frozen", "closed", "rejected"].includes(state)) {
    throw new functions.https.HttpsError(
        "failed-precondition",
        "This rider account cannot perform delivery actions.",
    );
  }
}

function expectedPin(delivery, action) {
  const protection = delivery.vanguardProtection || {};
  if (action === "verify_collection_pin") {
    return text(delivery.collectionPin || delivery.pickupPin || protection.collectionPin);
  }
  if (action === "verify_receiver_pin") {
    return text(delivery.deliveryPin || delivery.receiverPin || delivery.dropoffPin || protection.deliveryPin);
  }
  return "";
}

function pinAttemptField(action) {
  return action === "verify_receiver_pin" ?
    "deliveryPinAttemptCount" : "collectionPinAttemptCount";
}

function patchForTransition({action, nextStatus, riderId}) {
  const now = FieldValue.serverTimestamp();
  const patch = {
    status: nextStatus,
    deliveryStatus: nextStatus,
    deliveryStage: nextStatus,
    updatedAt: now,
    lastRiderAction: action,
    lastRiderActionAt: now,
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

    const riderRef = db.collection("riders").doc(riderId);
    const riderSnapshot = await transaction.get(riderRef);
    assertRiderOperational(riderSnapshot.data());

    const currentStatus = normalized(delivery.status || delivery.deliveryStatus || "requested");
    if (currentStatus === nextStatus ||
        (nextStatus === "delivered" && currentStatus === "completed")) {
      return {
        deliveryId: found.id,
        requestId: delivery.requestId || found.id,
        status: currentStatus,
        senderTrackingState: tracking.senderTrackingStateForBackendStatus(currentStatus),
        idempotent: true,
      };
    }
    if (!tracking.canTransitionDeliveryStatus(currentStatus, nextStatus)) {
      throw new functions.https.HttpsError("failed-precondition", `Cannot move delivery from ${currentStatus} to ${nextStatus}.`);
    }


    const requiredPin = expectedPin(delivery, action);
    if (requiredPin) {
      const suppliedPin = text(data && data.pin);
      const attemptField = pinAttemptField(action);
      const attempts = Number(delivery[attemptField] || 0);
      if (attempts >= 5) {
        throw new functions.https.HttpsError(
            "resource-exhausted",
            "Too many incorrect PIN attempts. Contact Circum Support.",
        );
      }
      if (!/^\d{6}$/.test(suppliedPin) || suppliedPin !== requiredPin) {
        transaction.set(found.ref, {
          [attemptField]: attempts + 1,
          lastPinAttemptAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
        return {verificationFailed: true, attemptsRemaining: 4 - attempts};
      }
    }

    const patch = patchForTransition({
      action,
      nextStatus,
      riderId,
    });
    const liveLocation = liveLocationPatch(data && data.location);
    let activeRef = null;
    let shouldWriteLocation = false;
    if (Object.keys(liveLocation).length > 0) {
      activeRef = db.collection("activeDeliveries").doc(found.id);
      const activeSnapshot = await transaction.get(activeRef);
      shouldWriteLocation = shouldWriteLiveLocation(activeSnapshot.data(), liveLocation);
    }
    transaction.set(found.ref, patch, {merge: true});
    if (activeRef && shouldWriteLocation) {
      transaction.set(
          activeRef,
          {
            deliveryId: found.id,
            requestId: delivery.requestId || found.id,
            riderId,
            status: nextStatus,
            ...liveLocation,
            updatedAt: FieldValue.serverTimestamp(),
          },
          {merge: true},
      );
    }
    return {
      deliveryId: found.id,
      requestId: delivery.requestId || found.id,
      status: nextStatus,
      senderTrackingState: tracking.senderTrackingStateForBackendStatus(nextStatus),
    };
  });
  if (result.verificationFailed) {
    throw new functions.https.HttpsError(
        "failed-precondition",
        `Incorrect PIN. ${Math.max(0, result.attemptsRemaining)} attempts remaining.`,
    );
  }
  return result;
});

exports._private = {
  liveLocationPatch,
  shouldWriteLiveLocation,
  distanceMeters,
  patchForTransition,
  expectedPin,
  assertRiderOperational,
};
