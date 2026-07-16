/* eslint-disable max-len, require-jsdoc, quote-props */
const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {
  classifyIris,
  createLearningSnapshot,
  customerSafeIris,
  privateIris,
} = require("./iris-core");
const {requireAdmin} = require("./admin-auth");

async function loadLearningExamples(description) {
  const text = `${description || ""}`.trim();
  if (!text) return [];
  const snapshot = await getFirestore().collection("history")
      .where("iris.learningSnapshot.version", "==", "v1")
      .limit(40)
      .get();
  return snapshot.docs.map((doc) => ({id: doc.id, ...doc.data()}));
}

const analyseIris = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated",
        "User must be authenticated to call Iris.");
  }
  const completedExamples = await loadLearningExamples(data.description || data.packageDescription);
  return customerSafeIris(classifyIris({...data, completedExamples}));
});

const adjudicateIris = functions.https.onCall(async (data, context) => {
  const adminUid = requireAdmin(context, "IRIS administrator access is required.");
  const {requestId, decision, finalCategory, finalWeightBand, finalHandlingFlags, reason, referralType, serviceabilityStatus} = data;
  if (!requestId || !decision || !reason) {
    throw new functions.https.HttpsError("invalid-argument",
        "requestId, decision, and reason are required.");
  }
  const db = getFirestore();
  const snapshot = await db.collection("deliveryRequests").where("requestId", "==", requestId).limit(1).get();
  if (snapshot.empty) {
    throw new functions.https.HttpsError("not-found", "Delivery request not found.");
  }
  const doc = snapshot.docs[0];
  const adjudication = {
    adminUserId: adminUid,
    createdBy: adminUid,
    updatedBy: adminUid,
    decision,
    finalCategory: finalCategory || null,
    finalWeightBand: finalWeightBand || null,
    finalHandlingFlags: finalHandlingFlags || [],
    reason,
    referralType: referralType || null,
    createdAt: FieldValue.serverTimestamp(),
  };
  const update = {
    updatedAt: FieldValue.serverTimestamp(),
  };
  if (decision === "unsupported" || decision === "prohibited" || decision === "referral_required") {
    update.status = decision;
    update.matchingStatus = "blocked";
  }
  await doc.ref.set(update, {merge: true});
  await db.collection("irisPrivate").doc(requestId).set({
    requestId,
    "verification.adjudication": adjudication,
    ...(serviceabilityStatus ? {serviceabilityOverride: {
      status: serviceabilityStatus,
      reasonCodes: ["admin_override"],
    }} : {}),
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  await db.collection("adminAuditLogs").add({
    adminUserId: adminUid,
    actorUid: adminUid,
    actionType: "iris_adjudication",
    recordType: "deliveryRequests",
    recordId: requestId,
    newValue: {decision, finalCategory, finalWeightBand, finalHandlingFlags, referralType, serviceabilityStatus},
    reason,
    createdAt: FieldValue.serverTimestamp(),
  });
  if (referralType) {
    await db.collection("irisReferrals").doc(requestId).set({
      requestId,
      referralType,
      status: "open",
      reason,
      source: "admin_adjudication",
      createdBy: adminUid,
      updatedBy: adminUid,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  }
  return {ok: true, requestId, adjudication};
});

async function writeLearningSnapshotForRequest(requestId, completedAt) {
  const db = getFirestore();
  const snapshot = await db.collection("deliveryRequests").where("requestId", "==", requestId).limit(1).get();
  if (snapshot.empty) return null;
  const doc = snapshot.docs[0];
  const data = doc.data();
  const iris = data.iris || classifyIris({
    description: data.packageDescription,
    declaredWeightText: data.weight,
    distanceMiles: 0,
    speed: data.speed,
  });
  const privateSnapshot = await db.collection("irisPrivate").doc(requestId).get();
  const privateData = privateSnapshot.exists ? privateSnapshot.data() : {};
  const learningSnapshot = createLearningSnapshot({
    ...iris,
    verification: privateData.verification || {},
  }, {...data, completedAt});
  await doc.ref.set({updatedAt: FieldValue.serverTimestamp()}, {merge: true});
  await db.collection("irisPrivate").doc(requestId).set({
    requestId,
    learningSnapshot,
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  return learningSnapshot;
}

module.exports = {
  analyseIris,
  adjudicateIris,
  writeLearningSnapshotForRequest,
  customerSafeIris,
  privateIris,
};
