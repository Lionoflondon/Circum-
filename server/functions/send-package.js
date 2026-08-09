/* eslint-disable max-len, require-jsdoc */
const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {dispatchComplianceDecision} = require("./iris-core");
const {hasAdminClaim} = require("./admin-auth");
const {dispatchEligibilityDecision} = require("./rider-dispatch-authority");
const communicationEngine = require("./communication-engine");

function senderOwnsRequest(delivery, uid) {
  return delivery.senderId === uid || delivery.userId === uid;
}

async function dispatchDeliveryRequest({
  db = getFirestore(),
  emitNotification = communicationEngine.emitNotification,
  requestId,
  uid,
  authToken = {},
  source = "sendPackage",
}) {
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
    source !== "finalizeSenderCheckoutSession" &&
    source !== "escalateUnclaimedDeliveries") {
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
      matchedRiderCount: 0,
      pushSentCount: 0,
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

  const presenceSnapshot = await db.collection("riderPresence")
      .where("isOnline", "==", true)
      .where("availabilityStatus", "==", "available")
      .limit(250)
      .get();
  const candidateDecisions = await Promise.all(presenceSnapshot.docs.map(async (presenceDoc) => {
    const [profileDoc, riderDoc] = await Promise.all([
      db.collection("riderProfiles").doc(presenceDoc.id).get(),
      db.collection("riders").doc(presenceDoc.id).get(),
    ]);
    const profile = {
      ...(riderDoc.exists ? riderDoc.data() : {}),
      ...(profileDoc.exists ? profileDoc.data() : {}),
    };
    const decision = dispatchEligibilityDecision({
      riderId: presenceDoc.id,
      profile,
      presence: presenceDoc.data(),
      delivery: deliveryRequest[0],
    });
    return {
      ...decision,
      id: presenceDoc.id,
    };
  }));

  const closestRiders = candidateDecisions
      .filter((rider) => rider.eligible)
      .sort((a, b) => a.distanceKm - b.distanceKm)
      .slice(0, 5);

  const sendResults = await Promise.all(closestRiders.map(async (rider) => {
    try {
      const notificationId = await emitNotification({
        recipientId: rider.id,
        recipientRole: "rider",
        type: "new_delivery",
        title: "New delivery available",
        body: "A delivery matching your vehicle is ready to review.",
        data: {
          bookingId: requestId,
          deliveryId: deliveryRequest[0].id,
          route: "jobs",
          category: "jobs",
          correlationId: `delivery_offer:${deliveryRequest[0].id}:${rider.id}`,
        },
      });
      return {riderId: rider.id, sent: true, notificationId};
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
    riderIdsConsidered: presenceSnapshot.docs.map((doc) => doc.id),
    riderIdsMatched: closestRiders.map((rider) => rider.id),
    excluded: candidateDecisions
        .filter((decision) => !decision.eligible)
        .slice(0, 100)
        .map((decision) => ({riderId: decision.id, reason: decision.reason})),
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
    message: "Dispatch evaluated.",
    requestId: requestId,
    deliveryId: deliveryRequest[0].id,
    matchedRiderCount: closestRiders.length,
    pushSentCount: sendResults.filter((result) => result.sent).length,
  };
}

const sendPackage = functions.runWith({enforceAppCheck: true}).https.onCall(async (data, context) => {
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
    console.error("Delivery dispatch failed", {
      code: e && e.code || null,
      message: e && e.message || "unknown_dispatch_error",
    });
    throw new functions.https.HttpsError("internal", "Delivery dispatch could not be completed.");
  }
});


module.exports = sendPackage;
module.exports.dispatchDeliveryRequest = dispatchDeliveryRequest;
