/* eslint-disable max-len */
const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {isDispatchable} = require("./iris-core");
const {buildRiderVehicleSnapshot} = require("./rider-vehicle-snapshot");
const {dispatchEligibilityDecision} = require("./rider-dispatch-authority");
const communicationEngine = require("./communication-engine");

const cleanText = (value, fallback = "") => {
  if (value === undefined || value === null) return fallback;
  const text = `${value}`.trim();
  return text.length > 0 ? text : fallback;
};

const terminalStatuses = new Set(["accepted", "assigned", "collected", "in_transit", "delivered", "completed", "cancelled", "canceled", "expired", "failed", "blocked"]);
const openStatuses = new Set(["requested", "pending", "broadcast", "broadcasted", "awaiting_rider", "finding_rider"]);
const openMatchingStatuses = new Set(["available", "requested", "broadcast", "broadcasted"]);
const openDispatchStatuses = new Set(["requested", "available", "broadcast", "broadcasted", "queued", "waiting"]);
const paidStatuses = new Set(["", "paid", "succeeded", "payment_confirmed", "confirmed", "roth_paid", "stripe_paid"]);

const millis = (value) => {
  if (!value) return 0;
  if (typeof value.toMillis === "function") return value.toMillis();
  if (Number.isFinite(Number(value))) return Number(value);
  if (value.seconds !== undefined) return Number(value.seconds) * 1000;
  const parsed = Date.parse(`${value}`);
  return Number.isFinite(parsed) ? parsed : 0;
};

const offerExpiryMillis = (delivery = {}) =>
  millis(delivery.offerExpiresAt || delivery.dispatchExpiresAt || delivery.expiresAt || delivery.matchingExpiresAt);

const offerCreatedMillis = (delivery = {}) =>
  millis(delivery.createdAt || delivery.created_at || delivery.bookingCreatedAt || delivery.updatedAt);

const assignedRiderId = (delivery = {}) =>
  cleanText(delivery.riderId || delivery.driverId || delivery.assignedRider || delivery.assignedRiderId || delivery.assignedDriverId || delivery.courierId);

const offerExclusionReason = (delivery = {}, riderId = "", now = Date.now()) => {
  const status = cleanText(delivery.status).toLowerCase();
  const deliveryStatus = cleanText(delivery.deliveryStatus || delivery.deliveryStage).toLowerCase();
  const matchingStatus = cleanText(delivery.matchingStatus).toLowerCase();
  const dispatchStatus = cleanText(delivery.dispatchStatus).toLowerCase();
  const paymentStatus = cleanText(delivery.paymentStatus || delivery.paymentState).toLowerCase();
  const assigned = assignedRiderId(delivery);
  const expiry = offerExpiryMillis(delivery);

  if ([status, deliveryStatus, matchingStatus, dispatchStatus].some((value) => terminalStatuses.has(value))) {
    return assigned === riderId && ["accepted", "assigned"].includes(status) ? "" : "terminal_status";
  }
  if (assigned && assigned !== riderId) return "already_assigned";
  if (expiry && expiry <= now) return "expired_offer";
  if (!paidStatuses.has(paymentStatus)) return "payment_not_confirmed";
  if (matchingStatus && !openMatchingStatuses.has(matchingStatus)) return "matching_not_open";
  if (dispatchStatus && !openDispatchStatuses.has(dispatchStatus)) return "dispatch_not_open";
  if (status && !openStatuses.has(status) && matchingStatus !== "available" && dispatchStatus !== "requested") return "status_not_open";
  return "";
};

const riderPayload = (riderId, rider) => {
  const vehicle = rider.vehicle || rider.vehicleDetails || {};
  return {
    courierName: cleanText(rider.fullName || rider.name || rider.displayName || rider.email, "Circum rider"),
    phoneNumber: "",
    contactMethod: "circum_relay",
    maskedCommunicationOnly: true,
    locality: cleanText(rider.locality || rider.city),
    typeOfVehicle: cleanText(rider.vehicleType || vehicle.type, "Vehicle"),
    plateNumber: cleanText(rider.plateNumber || rider.vehicleRegistration || vehicle.registration),
    estimatedDeliveryTime: cleanText(rider.estimatedDeliveryTime, "On the way"),
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

const getRiderProfile = async (db, transaction, riderId) => {
  const profileDoc = await transaction.get(db.collection("riderProfiles").doc(riderId));
  const riderDoc = await transaction.get(db.collection("riders").doc(riderId));
  if (riderDoc.exists) {
    return {
      ...riderDoc.data(),
      ...(profileDoc.exists ? profileDoc.data() : {}),
    };
  }

  return null;
};

const senderIdFor = (delivery = {}) =>
  cleanText(delivery.senderId || delivery.userId || delivery.customerId);

const notifySender = async (deliveryId, deliveryRequest) => {
  const senderId = senderIdFor(deliveryRequest);
  if (!senderId) return false;
  await communicationEngine.emitNotification({
    recipientId: senderId,
    recipientRole: "sender",
    type: "delivery_accepted",
    title: "Rider accepted",
    body: "A rider has accepted your delivery.",
    data: {
      bookingId: cleanText(deliveryRequest.requestId || deliveryRequest.bookingId || deliveryId),
      deliveryId,
      correlationId: `delivery_accepted:${deliveryId}`,
      category: "deliveries",
    },
  });
  return true;
};

const acceptRideRequestHandler = async (data, context, dependencies = {}) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "User must be authenticated to accept a delivery.");
  }

  const requestId = cleanText(data && data.requestId);
  if (!requestId) {
    throw new functions.https.HttpsError("invalid-argument", "requestId is required.");
  }

  const riderId = context.auth.uid;
  const db = dependencies.db || getFirestore();
  const accepted = await db.runTransaction(async (transaction) => {
    const found = await findDeliveryRequest(db, transaction, requestId);
    if (!found) {
      throw new functions.https.HttpsError("not-found", "Delivery request not found.");
    }

    const deliveryRequest = found.data;
    const rider = await getRiderProfile(db, transaction, riderId);
    if (!rider) {
      throw new functions.https.HttpsError("not-found", "Rider profile not found.");
    }
    const presenceRef = db.collection("riderPresence").doc(riderId);
    const presenceDoc = await transaction.get(presenceRef);
    const presence = presenceDoc.exists ? presenceDoc.data() : {};
    console.info("rider_offer_accept_attempt", {
      bookingId: cleanText(deliveryRequest.bookingId || deliveryRequest.requestId || found.id),
      deliveryId: found.id,
      senderId: cleanText(deliveryRequest.senderId || deliveryRequest.userId || deliveryRequest.customerId),
      riderId,
      dispatchId: cleanText(deliveryRequest.dispatchId || deliveryRequest.dispatchRunId),
      offerCreatedAt: offerCreatedMillis(deliveryRequest),
      offerExpiresAt: offerExpiryMillis(deliveryRequest),
      status: cleanText(deliveryRequest.status),
      matchingStatus: cleanText(deliveryRequest.matchingStatus),
      dispatchStatus: cleanText(deliveryRequest.dispatchStatus),
    });
    const privateDoc = await transaction.get(db.collection("irisPrivate").doc(deliveryRequest.requestId || found.id));
    if (privateDoc.exists) {
      deliveryRequest.irisPrivate = privateDoc.data();
    }
    if (!isDispatchable(deliveryRequest)) {
      throw new functions.https.HttpsError("failed-precondition", "Delivery request is not dispatchable by Iris.");
    }

    const eligibility = dispatchEligibilityDecision({
      riderId,
      profile: rider,
      presence,
      delivery: deliveryRequest,
    });
    if (!eligibility.eligible) {
      console.info("rider_accept_ineligible", {
        riderId,
        deliveryId: found.id,
        reason: eligibility.reason,
      });
      throw new functions.https.HttpsError("permission-denied", "This delivery is not currently available because your rider account is not yet eligible for dispatch.");
    }

    const currentStatus = cleanText(deliveryRequest.status).toLowerCase();
    const assignedRider = assignedRiderId(deliveryRequest);
    if (assignedRider && assignedRider !== riderId) {
      throw new functions.https.HttpsError("already-exists", "Delivery request has already been accepted.");
    }
    const exclusion = offerExclusionReason(deliveryRequest, riderId);
    if (exclusion) {
      console.warn("rider_offer_accept_rejected", {
        bookingId: cleanText(deliveryRequest.bookingId || deliveryRequest.requestId || found.id),
        deliveryId: found.id,
        senderId: cleanText(deliveryRequest.senderId || deliveryRequest.userId || deliveryRequest.customerId),
        riderId,
        dispatchId: cleanText(deliveryRequest.dispatchId || deliveryRequest.dispatchRunId),
        reason: exclusion,
      });
      throw new functions.https.HttpsError("failed-precondition", `Delivery offer is no longer available: ${exclusion}.`);
    }
    if (currentStatus && !["requested", "pending", "broadcast", "broadcasted", "awaiting_rider", "finding_rider"].includes(currentStatus) && assignedRider !== riderId) {
      throw new functions.https.HttpsError("failed-precondition", `Delivery request is not open for acceptance: ${currentStatus}.`);
    }

    const payload = riderPayload(riderId, rider);
    const senderId = senderIdFor(found.data);
    if (!senderId) {
      throw new functions.https.HttpsError("failed-precondition", "Delivery owner is unavailable.");
    }
    const assignedVehicle = buildRiderVehicleSnapshot(rider);
    const assignedVehicleClass = assignedVehicle.type || payload.typeOfVehicle;
    const assignedVehicleId = assignedVehicle.registration || null;
    transaction.set(found.ref, {
      status: "accepted",
      deliveryStatus: "accepted",
      deliveryStage: "accepted",
      dispatchStatus: "accepted",
      matchingStatus: "accepted",
      riderId,
      driverId: riderId,
      assignedRider: riderId,
      assignedDriverId: riderId,
      assignedRiderId: riderId,
      riderName: payload.courierName,
      driverName: payload.courierName,
      courierName: payload.courierName,
      driverVehicle: payload.typeOfVehicle,
      driverPlateNumber: payload.plateNumber,
      assignedVehicleId,
      assignedVehicleClass,
      assignedVehicleSnapshot: assignedVehicle,
      acceptedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    transaction.set(presenceRef, {
      isOnline: true,
      availabilityStatus: "busy",
      busy: true,
      dispatchEligible: false,
      activeDeliveryId: found.id,
      currentDeliveryId: found.id,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});

    const chatRef = db.collection("chats").doc(found.data.requestId || found.id);
    transaction.set(chatRef, {
      threadId: found.data.requestId || found.id,
      bookingId: found.data.requestId || found.id,
      requestId: found.data.requestId || found.id,
      conversationType: "sender_rider",
      participants: [senderId, riderId, "circum-support"],
      participantRoles: {
        [senderId]: "sender",
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
  console.info("rider_offer_accept_success", {
    bookingId: accepted.requestId,
    deliveryId: accepted.id,
    riderId,
    assignmentTimestamp: Date.now(),
  });

  let senderNotified = false;
  try {
    senderNotified = await (dependencies.notifySender || notifySender)(accepted.id, accepted.deliveryRequest);
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
};

const acceptRideRequests = functions.runWith({enforceAppCheck: true}).https.onCall(acceptRideRequestHandler);

module.exports = acceptRideRequests;
module.exports._private = {
  assignedRiderId,
  acceptRideRequestHandler,
  offerExclusionReason,
  riderPayload,
  senderIdFor,
};
