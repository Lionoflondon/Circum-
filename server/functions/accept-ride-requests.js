/* eslint-disable max-len */
const functions = require("firebase-functions/v1");
const {riderCallable} = require("./rider-app-check");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {getMessaging} = require("firebase-admin/messaging");
const {isDispatchable, riderCanViewDispatch, riderMatchesIris} = require("./iris-core");
const {riderVehicleMatchesRequest} = require("./vehicle-dispatch");
const {start: startLatency} = require("./latency-observability");
const {requireDispatchablePresence, dispatchablePresenceDecision} = require("./rider-presence");

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
  if (delivery.cancellationSettlementStatus) return "cancellation_in_progress";
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

const acceptRideRequests = riderCallable(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "User must be authenticated to accept a delivery.");
  }

  const requestId = cleanText(data && data.requestId);
  if (!requestId) {
    throw new functions.https.HttpsError("invalid-argument", "requestId is required.");
  }

  const riderId = context.auth.uid;
  const completeAccept = startLatency("ACCEPT", {correlationId: requestId});
  const db = getFirestore();
  const rider = await getRiderProfile(db, riderId);

  if (!rider) {
    throw new functions.https.HttpsError("not-found", "Rider profile not found.");
  }
  const directExisting = await db.collection("deliveryRequests").doc(requestId).get();
  const matchingExisting = directExisting.exists ? directExisting :
    (await db.collection("deliveryRequests").where("requestId", "==", requestId).limit(1).get()).docs[0];
  if (matchingExisting && matchingExisting.exists && !matchingExisting.data().cancellationSettlementStatus && assignedRiderId(matchingExisting.data()) === riderId) {
    const status = cleanText(matchingExisting.data().status).toLowerCase();
    if (["accepted", "assigned", "navigating_to_pickup", "arrived_at_pickup", "pickup_verified", "collected", "picked_up", "navigating_to_dropoff", "arrived_at_dropoff"].includes(status)) {
      completeAccept({success: true, deliveryId: matchingExisting.id, idempotent: true});
      return {status: "accepted", requestId, riderId, senderNotified: false, idempotent: true};
    }
  }
  await requireDispatchablePresence(riderId, rider);

  const accepted = await db.runTransaction(async (transaction) => {
    const [presenceDoc, profileDoc, operationalRiderDoc] = await Promise.all([
      transaction.get(db.collection("riderPresence").doc(riderId)),
      transaction.get(db.collection("riderProfiles").doc(riderId)),
      transaction.get(db.collection("riders").doc(riderId)),
    ]);
    const transactionalRider = {
      ...(profileDoc.exists ? profileDoc.data() : {}),
      ...(operationalRiderDoc.exists ? operationalRiderDoc.data() : {}),
    };
    const presenceDecision = dispatchablePresenceDecision(
        transactionalRider,
        presenceDoc.exists ? presenceDoc.data() : {},
    );
    if (!presenceDecision.allowed) {
      throw new functions.https.HttpsError(
          "failed-precondition",
          "Go online and remain available before accepting deliveries.",
          {presenceState: presenceDecision.presenceState, reason: presenceDecision.reason},
      );
    }
    const found = await findDeliveryRequest(db, transaction, requestId);
    if (!found) {
      throw new functions.https.HttpsError("not-found", "Delivery request not found.");
    }

    const deliveryRequest = found.data;
    const activeDeliveryId = cleanText(
        transactionalRider.activeDeliveryId ||
        transactionalRider.currentDeliveryId ||
        (presenceDoc.exists && presenceDoc.data().activeDeliveryId),
    );
    if (activeDeliveryId && activeDeliveryId !== found.id && activeDeliveryId !== deliveryRequest.requestId) {
      throw new functions.https.HttpsError(
          "failed-precondition",
          "Complete your active delivery before accepting another.",
      );
    }
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

    if (!riderCanViewDispatch(rider, deliveryRequest)) {
      throw new functions.https.HttpsError("permission-denied", "This delivery is not available to this rider.");
    }

    if (!riderVehicleMatchesRequest(rider, deliveryRequest) &&
        !canOverrideVehicleMismatch(context, data)) {
      throw new functions.https.HttpsError("failed-precondition", "Your registered vehicle is not suitable for this delivery.");
    }

    if (!riderMatchesIris(rider, deliveryRequest)) {
      throw new functions.https.HttpsError("failed-precondition", "Rider does not match this delivery requirement.");
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

    for (const collection of ["riders", "riderProfiles", "riderPresence"]) {
      transaction.set(db.collection(collection).doc(riderId), {activeDeliveryId: found.id, availabilityStatus: "busy", updatedAt: FieldValue.serverTimestamp()}, {merge: true});
    }
    transaction.delete(db.doc(`riderOfferProjections/${riderId}/offers/${found.id}`));
    transaction.delete(db.doc(`riderOfferAuthorizations/${riderId}/jobs/${found.id}`));
    const payload = riderPayload(riderId, rider);
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
      acceptedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});

    const chatSenderId = cleanText(deliveryRequest.senderId || deliveryRequest.userId || deliveryRequest.customerId);
    const chatRef = db.collection("chats").doc(found.data.requestId || found.id);
    transaction.set(chatRef, {
      threadId: found.data.requestId || found.id,
      bookingId: found.data.requestId || found.id,
      requestId: found.data.requestId || found.id,
      participants: chatSenderId ?
        FieldValue.arrayUnion(riderId, chatSenderId, "circum-support") :
        FieldValue.arrayUnion(riderId, "circum-support"),
      participantRoles: {
        [riderId]: "rider",
        ...(chatSenderId ? {[chatSenderId]: "sender"} : {}),
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
  completeAccept({success: true, deliveryId: accepted.id});

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
