/* eslint-disable max-len, require-jsdoc */
const functions = require("firebase-functions/v1");
const {FieldValue, getFirestore} = require("firebase-admin/firestore");
const core = require("./rider-iris-acknowledgement-core");

function text(value) {
  return `${value || ""}`.trim();
}

function requireRider(context) {
  const riderId = context.auth && text(context.auth.uid);
  if (!riderId) {
    throw new functions.https.HttpsError("unauthenticated", "Sign in first.");
  }
  return riderId;
}

function assignedRider(delivery) {
  return text(delivery.riderId || delivery.assignedRiderId || delivery.driverId || delivery.assignedDriverId);
}

exports.confirmRiderIrisAssessment = functions.https.onCall(async (data, context) => {
  const riderId = requireRider(context);
  const deliveryId = text(data && data.deliveryId);
  if (!deliveryId) {
    throw new functions.https.HttpsError("invalid-argument", "deliveryId is required.");
  }

  const db = getFirestore();
  const deliveryRef = db.collection("deliveryRequests").doc(deliveryId);
  const acknowledgementRef = db.collection("riderIrisAcknowledgements").doc(deliveryId);
  const adminAuditRef = db.collection("adminAuditLogs").doc(`rider_iris_confirmation_${deliveryId}`);

  return db.runTransaction(async (transaction) => {
    const [deliverySnapshot, existingSnapshot] = await Promise.all([
      transaction.get(deliveryRef),
      transaction.get(acknowledgementRef),
    ]);
    if (!deliverySnapshot.exists) {
      throw new functions.https.HttpsError("not-found", "Delivery not found.");
    }
    const delivery = deliverySnapshot.data();
    if (assignedRider(delivery) !== riderId) {
      throw new functions.https.HttpsError("permission-denied", "Only the assigned rider can confirm this assessment.");
    }
    if (existingSnapshot.exists) {
      return {success: true, duplicate: true, acknowledgement: existingSnapshot.data()};
    }
    if (delivery.loadDiscrepancy || delivery.adjustmentId) {
      throw new functions.https.HttpsError("failed-precondition", "A parcel difference has already been reported.");
    }
    if (!core.canConfirmAtPickup(delivery)) {
      throw new functions.https.HttpsError("failed-precondition", "Confirm the IRIS assessment when you are at pickup.");
    }

    const now = Date.now();
    const acknowledgement = core.buildAcknowledgement({deliveryId, riderId, delivery});
    const storedAcknowledgement = {
      ...acknowledgement,
      confirmedAt: FieldValue.serverTimestamp(),
      createdAt: FieldValue.serverTimestamp(),
    };
    const auditEvent = {
      type: "rider_iris_assessment_confirmed",
      actionType: "rider_iris_assessment_confirmed",
      deliveryId,
      actorId: riderId,
      actorRole: "rider",
      acknowledgementStatus: "confirmed",
      createdAt: now,
    };

    transaction.create(acknowledgementRef, storedAcknowledgement);
    transaction.set(adminAuditRef, {
      adminUserId: riderId,
      actionType: "rider_iris_assessment_confirmed",
      recordType: "deliveryRequests",
      recordId: deliveryId,
      actorId: riderId,
      actorRole: "rider",
      newValue: acknowledgement,
      createdAt: FieldValue.serverTimestamp(),
    });
    transaction.update(deliveryRef, {
      riderIrisAcknowledgement: storedAcknowledgement,
      irisAcknowledgementUpdatedAt: FieldValue.serverTimestamp(),
      auditHistory: FieldValue.arrayUnion(auditEvent),
    });

    return {
      success: true,
      duplicate: false,
      acknowledgement: {...acknowledgement, confirmedAt: now},
    };
  });
});
