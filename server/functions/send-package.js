/* eslint-disable max-len, require-jsdoc */
const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {getMessaging} = require("firebase-admin/messaging");
const {dispatchComplianceDecision, dispatchPriority, riderMatchesIris} = require("./iris-core");
const {hasAdminClaim} = require("./admin-auth");

function senderOwnsRequest(delivery, uid) {
  return delivery.senderId === uid || delivery.userId === uid;
}

async function dispatchDeliveryRequest({
  db = getFirestore(),
  messaging = getMessaging(),
  requestId,
  uid,
  authToken = {},
  source = "sendPackage",
}) {
  const toRadians = (degrees) => {
    return degrees * (Math.PI / 180);
  };
  const snapshot = await db.collection("deliveryRequests").where("requestId", "==", requestId).limit(1).get();
  const deliveryRequest = snapshot.docs.map((doc) => ({
    id: doc.id,
    ...doc.data(),
  }));

  if (deliveryRequest.length === 0) {
    return {message: "Delivery request not found", requestId};
  }
  if (!senderOwnsRequest(deliveryRequest[0], uid) &&
    !hasAdminClaim(authToken || {}) &&
    source !== "createSenderPaidDelivery" &&
    source !== "finalizeSenderCheckoutSession") {
    throw new functions.https.HttpsError(
        "permission-denied",
        "Only the Sender or an administrator can dispatch this delivery.",
    );
  }

  const currentDispatchStatus = `${deliveryRequest[0].dispatchStatus || ""}`.toLowerCase();
  const currentMatchingStatus = `${deliveryRequest[0].matchingStatus || ""}`.toLowerCase();
  if (
    currentDispatchStatus === "broadcasted" ||
    currentDispatchStatus === "accepted" ||
    currentMatchingStatus === "broadcasted" ||
    currentMatchingStatus === "accepted"
  ) {
    await db.collection("dispatchInspections").doc(deliveryRequest[0].id).set({
      deliveryId: deliveryRequest[0].id,
      requestId,
      status: "already_dispatched",
      source,
      dispatchStatus: currentDispatchStatus,
      matchingStatus: currentMatchingStatus,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    return {
      message: "Delivery request has already been dispatched.",
      requestId,
      deliveryId: deliveryRequest[0].id,
      idempotent: true,
      closestRiders: [],
      pushResults: [],
    };
  }

  const dispatchDecision = dispatchComplianceDecision(deliveryRequest[0]);
  if (!dispatchDecision.dispatchable) {
    await db.collection("adminAuditLogs").add({
      actionType: "iris_dispatch_blocked",
      recordType: "deliveryRequests",
      recordId: deliveryRequest[0].id,
      requestId: requestId,
      performedBy: uid,
      source,
      reason: dispatchDecision.reason || "server_iris_blocked",
      compliance: dispatchDecision.compliance || null,
      serviceability: dispatchDecision.serviceability || null,
      storedIrisMismatch: dispatchDecision.storedIrisMismatch === true,
      createdAt: FieldValue.serverTimestamp(),
    });
    await db.collection("dispatchInspections").doc(deliveryRequest[0].id).set({
      deliveryId: deliveryRequest[0].id,
      requestId,
      status: "blocked",
      reason: dispatchDecision.reason || "server_iris_blocked",
      source,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    return {
      message: "Delivery request is not dispatchable by Iris.",
      requestId: requestId,
      irisStatus: dispatchDecision.compliance || deliveryRequest[0].iris && deliveryRequest[0].iris.status,
    };
  }
  const privateDoc = await db
      .collection("irisPrivate")
      .doc(deliveryRequest[0].requestId || deliveryRequest[0].id)
      .get();
  if (privateDoc.exists) {
    deliveryRequest[0].irisPrivate = privateDoc.data();
  }
  const rawPickupPosition = deliveryRequest[0].pickupPosition;
  const rawPickupGeo = rawPickupPosition && rawPickupPosition.geopoint;
  const hasValidPickupGeo = Boolean(
      rawPickupGeo &&
      Number.isFinite(Number(rawPickupGeo.latitude)) &&
      Number.isFinite(Number(rawPickupGeo.longitude)),
  );
  if (!hasValidPickupGeo) {
    await db.collection("dispatchInspections").doc(deliveryRequest[0].id).set({
      deliveryId: deliveryRequest[0].id,
      requestId,
      status: "blocked",
      reason: "missing_pickup_geo",
      source,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    return {
      message: "Delivery request is missing a valid pickup location.",
      requestId,
      deliveryId: deliveryRequest[0].id,
      closestRiders: [],
      pushResults: [],
    };
  }

  const pickupPoint = {
    latitude: Number(rawPickupGeo.latitude),
    longitude: Number(rawPickupGeo.longitude),
  };

  const ridersSnapshot = await db.collection("riders")
      .where("status", "==", "online")
      .get();

  const ridersWithDistances = await Promise.all(
      ridersSnapshot.docs
          .filter((doc) => {
            const riderData = doc.data();
            if (!riderMatchesIris(riderData, deliveryRequest[0])) return false;
            return riderData.position &&
               riderData.position.geopoint &&
               riderData.position.geopoint.latitude &&
               riderData.position.geopoint.longitude;
          })
          .map(async (doc) => {
            try {
              const riderData = doc.data();
              const riderLocation = riderData.position.geopoint;

              if (!riderLocation.latitude || !riderLocation.longitude) {
                return null;
              }

              const R = 6371;
              const dLat = toRadians(riderLocation.latitude - pickupPoint.latitude);
              const dLon = toRadians(riderLocation.longitude - pickupPoint.longitude);

              const a =
            Math.sin(dLat/2) * Math.sin(dLat/2) +
            Math.cos(toRadians(pickupPoint.latitude)) *
            Math.cos(toRadians(riderLocation.latitude)) *
            Math.sin(dLon/2) * Math.sin(dLon/2);

              const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
              const distance = R * c;

              return {
                id: doc.id,
                ...riderData,
                distanceFromPickup: distance,
              };
            } catch (error) {
              console.error("Error processing rider:", error);
              return null;
            }
          }),
  );

  const RIDER_RANK_WEIGHT = {
    veteran: 4,
    knight: 3,
    warden: 2,
    sentinel: 1,
    agent: 0,
  };
  const riderRankWeight = (rider) =>
    RIDER_RANK_WEIGHT[`${rider.riderRank || rider.rank || "agent"}`.toLowerCase()] || 0;
  const isExpressDispatch = dispatchPriority(deliveryRequest[0]) === 1;
  const closestRiders = ridersWithDistances
      .filter((rider) => rider !== null)
      .sort((a, b) => {
        if (isExpressDispatch) {
          const rankDelta = riderRankWeight(b) - riderRankWeight(a);
          if (rankDelta !== 0) return rankDelta;
        }
        return a.distanceFromPickup - b.distanceFromPickup;
      })
      .slice(0, 5);

  const sendResults = await Promise.all(closestRiders.map(async (rider) => {
    if (!rider.fcmToken) {
      return {riderId: rider.id, sent: false, reason: "missing_fcm_token"};
    }
    const message = {
      apns: {
        payload: {
          aps: {
            "content-available": 1,
          },
        },
      },
      data: {
        "type": "broadcast-request",
        "requestId": requestId,
        "deliveryId": deliveryRequest[0].id,
        "data": JSON.stringify({
          deliveryId: deliveryRequest[0].id,
          requestId,
          riderId: rider.id,
          distanceFromPickup: rider.distanceFromPickup,
        }),
      },
      token: rider.fcmToken,

    };

    try {
      const response = await messaging.send(message);
      return {riderId: rider.id, sent: true, response};
    } catch (err) {
      console.warn("rider_broadcast_push_failed", {
        requestId,
        deliveryId: deliveryRequest[0].id,
        riderId: rider.id,
        code: err && err.code || null,
        message: err && err.message || null,
      });
      return {riderId: rider.id, sent: false, reason: err && err.code || "push_failed"};
    }
  }));

  await db.collection("dispatchInspections").doc(deliveryRequest[0].id).set({
    deliveryId: deliveryRequest[0].id,
    requestId,
    status: closestRiders.length ? "broadcast" : "no_riders_matched",
    source,
    riderIdsConsidered: ridersSnapshot.docs.map((doc) => doc.id),
    riderIdsMatched: closestRiders.map((rider) => rider.id),
    pushResults: sendResults,
    updatedAt: FieldValue.serverTimestamp(),
    createdAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  await db.collection("deliveryRequests").doc(deliveryRequest[0].id).set({
    dispatchStatus: closestRiders.length ? "broadcasted" : "requested",
    matchingStatus: closestRiders.length ? "broadcasted" : "available",
    dispatchAttemptedAt: FieldValue.serverTimestamp(),
    dispatchLastSource: source,
    dispatchMatchedRiderIds: closestRiders.map((rider) => rider.id),
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});

  return {
    message: `Endpoint accessed by user ${uid}`,
    requestId: requestId,
    request: deliveryRequest,
    coordinates: `${deliveryRequest[0].pickupPosition[0]}, ${deliveryRequest[0].pickupPosition[1]}`,
    closestRiders: closestRiders,
    pushResults: sendResults,
  };
}

const sendPackage = functions.https.onCall(async (data, context) => {
  try {
    const {requestId} = data;
    // Check if the user is authenticated
    if (!context.auth) {
      // Throw an error if no authentication is present
      throw new functions.https.HttpsError("unauthenticated",
          "User must be authenticated to call this function.");
    }

    // Get the authenticated user's UID
    const uid = context.auth.uid;
    return await dispatchDeliveryRequest({
      requestId,
      uid,
      authToken: context.auth.token || {},
      source: "sendPackage",
    });
  } catch (e) {
    if (e instanceof functions.https.HttpsError) {
      throw e;
    }
    return {
      error: e,
    };
  }
});


module.exports = sendPackage;
module.exports.dispatchDeliveryRequest = dispatchDeliveryRequest;
