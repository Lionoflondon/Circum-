/* eslint-disable max-len */
const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {getMessaging} = require("firebase-admin/messaging");
const {isDispatchable, riderCanViewDispatch, riderMatchesIris} = require("./iris-core");
const {riderVehicleMatchesRequest} = require("./vehicle-dispatch");

const cleanText = (value, fallback = "") => {
  if (value === undefined || value === null) return fallback;
  const text = `${value}`.trim();
  return text.length > 0 ? text : fallback;
};

const riderPayload = (riderId, rider) => {
  const vehicle = rider.vehicle || rider.vehicleDetails || {};
  return {
    courierName: cleanText(rider.fullName || rider.name || rider.displayName || rider.email, "Circum rider"),
    phoneNumber: cleanText(rider.phone || rider.phoneNumber || rider.mobile),
    locality: cleanText(rider.locality || rider.city),
    typeOfVehicle: cleanText(rider.vehicleType || vehicle.type, "Vehicle"),
    plateNumber: cleanText(rider.plateNumber || rider.vehicleRegistration || vehicle.registration),
    estimatedDeliveryTime: cleanText(rider.estimatedDeliveryTime, "On the way"),
    code: cleanText(rider.code || rider.fcmToken),
    rating: cleanText(rider.rating || rider.averageRating, "New"),
    riderId,
    photoURL: cleanText(rider.photoURL || rider.profilePhotoUrl || rider.avatarUrl, "null"),
  };
};

const findDeliveryRequest = async (db, transaction, requestId) => {
  const directRef = db.collection("deliveryRequests").doc(requestId);
  const directDoc = await transaction.get(directRef);
  if (directDoc.exists) {
    return {ref: directDoc.ref, id: directDoc.id, data: directDoc.data()};
  }

  const snapshot = await transaction.get(db.collection("deliveryRequests")
      .where("requestId", "==", requestId)
      .limit(1));

  if (snapshot.empty) return null;
  const doc = snapshot.docs[0];
  return {ref: doc.ref, id: doc.id, data: doc.data()};
};

const getRiderProfile = async (db, riderId) => {
  const profileDoc = await db.collection("riderProfiles").doc(riderId).get();
  const riderDoc = await db.collection("riders").doc(riderId).get();
  if (riderDoc.exists) {
    return {
      ...(profileDoc.exists ? profileDoc.data() : {}),
      ...riderDoc.data(),
    };
  }

  return null;
};

const canOverrideVehicleMismatch = (context, data) => {
  if (!data || data.adminVehicleOverride !== true) return false;
  const token = context.auth && context.auth.token || {};
  const role = cleanText(token.role || token.adminRole || token.claims && token.claims.role).toLowerCase();
  const roles = Array.isArray(token.roles) ? token.roles.map((item) => cleanText(item).toLowerCase()) : [];
  return token.super_admin === true || token.admin === true ||
    [role, ...roles].some((item) => ["super_admin", "operations_admin", "ops_admin"].includes(item));
};

const notifySender = async (deliveryRequest, payload) => {
  const token = cleanText(deliveryRequest.code || deliveryRequest.fcmToken || deliveryRequest.pushToken);
  if (!token) return false;

  await getMessaging().send({
    apns: {
      payload: {
        aps: {
          "content-available": 1,
        },
      },
    },
    data: {
      "type": "connection",
      "status": "accepted",
      "data": JSON.stringify(payload),
    },
    token,
  });
  return true;
};

const acceptRideRequests = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "User must be authenticated to accept a delivery.");
  }

  const requestId = cleanText(data && data.requestId);
  if (!requestId) {
    throw new functions.https.HttpsError("invalid-argument", "requestId is required.");
  }

  const riderId = context.auth.uid;
  const db = getFirestore();
  const rider = await getRiderProfile(db, riderId);

  if (!rider) {
    throw new functions.https.HttpsError("not-found", "Rider profile not found.");
  }

  const accepted = await db.runTransaction(async (transaction) => {
    const found = await findDeliveryRequest(db, transaction, requestId);
    if (!found) {
      throw new functions.https.HttpsError("not-found", "Delivery request not found.");
    }

    const deliveryRequest = found.data;
    const privateDoc = await transaction.get(db.collection("irisPrivate").doc(deliveryRequest.requestId || found.id));
    if (privateDoc.exists) {
      deliveryRequest.irisPrivate = privateDoc.data();
    }
    if (!isDispatchable(deliveryRequest)) {
      throw new functions.https.HttpsError("failed-precondition", "Delivery request is not dispatchable by Iris.");
    }

    if (!riderCanViewDispatch(rider, deliveryRequest)) {
      throw new functions.https.HttpsError("permission-denied", "This delivery is not available to the rider's current rank.");
    }

    if (!riderVehicleMatchesRequest(rider, deliveryRequest) &&
        !canOverrideVehicleMismatch(context, data)) {
      throw new functions.https.HttpsError("failed-precondition", "Your registered vehicle is not suitable for this delivery.");
    }

    if (!riderMatchesIris(rider, deliveryRequest)) {
      throw new functions.https.HttpsError("failed-precondition", "Rider does not match this delivery requirement.");
    }

    const currentStatus = cleanText(deliveryRequest.status).toLowerCase();
    const assignedRider = cleanText(deliveryRequest.riderId || deliveryRequest.driverId || deliveryRequest.assignedDriverId);
    if (assignedRider && assignedRider !== riderId) {
      throw new functions.https.HttpsError("already-exists", "Delivery request has already been accepted.");
    }
    if (currentStatus && !["requested", "pending", "broadcast", "broadcasted"].includes(currentStatus) && assignedRider !== riderId) {
      throw new functions.https.HttpsError("failed-precondition", `Delivery request is not open for acceptance: ${currentStatus}.`);
    }

    const payload = riderPayload(riderId, rider);
    transaction.set(found.ref, {
      status: "accepted",
      dispatchStatus: "accepted",
      matchingStatus: "accepted",
      riderId,
      driverId: riderId,
      assignedDriverId: riderId,
      assignedRiderId: riderId,
      riderName: payload.courierName,
      driverName: payload.courierName,
      courierName: payload.courierName,
      driverVehicle: payload.typeOfVehicle,
      driverPlateNumber: payload.plateNumber,
      acceptedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});

    const chatRef = db.collection("chats").doc(found.data.requestId || found.id);
    transaction.set(chatRef, {
      threadId: found.data.requestId || found.id,
      bookingId: found.data.requestId || found.id,
      requestId: found.data.requestId || found.id,
      participants: FieldValue.arrayUnion(riderId, "circum-support"),
      participantRoles: {
        [riderId]: "rider",
        "circum-support": "admin",
      },
      assignedRiderId: riderId,
      updatedAt: FieldValue.serverTimestamp(),
      source: "acceptRideRequests",
    }, {merge: true});

    return {
      id: found.id,
      requestId: found.data.requestId || requestId,
      deliveryRequest,
      payload,
    };
  });

  let senderNotified = false;
  try {
    senderNotified = await notifySender(accepted.deliveryRequest, accepted.payload);
  } catch (error) {
    console.error("Sender acceptance notification failed:", error);
  }

  return {
    status: "accepted",
    requestId: accepted.requestId,
    riderId,
    senderNotified,
    rider: accepted.payload,
  };
});

module.exports = acceptRideRequests;
