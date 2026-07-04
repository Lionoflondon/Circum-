/* eslint-disable max-len, require-jsdoc, quote-props */
const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {
  classifyIris,
  createLearningSnapshot,
  customerSafeIris,
  privateIris,
} = require("./iris-core");
const {
  buildLearningRecord,
  buildProductionDecision,
  learningRecordId,
} = require("./iris-production-core");

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
  const iris = classifyIris({...data, completedExamples});
  const response = customerSafeIris(iris);
  const db = getFirestore();
  const decisionRef = db.collection("irisProductionDecisions").doc();
  const decision = buildProductionDecision({
    decisionId: decisionRef.id,
    deliveryId: data.deliveryId || data.bookingId || data.requestId,
    userId: context.auth.uid,
    input: data,
    iris,
    createdAt: FieldValue.serverTimestamp(),
  });
  await decisionRef.create(decision);
  return {
    ...response,
    productionDecisionId: decisionRef.id,
    confidence: decision.customerConfidence,
    reasons: decision.reasons,
    lowConfidenceSuggestions: decision.lowConfidenceSuggestions,
  };
});

const adjudicateIris = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated",
        "User must be authenticated to adjudicate Iris.");
  }
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
    adminUserId: context.auth.uid,
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
    adminUserId: context.auth.uid,
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
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  }
  const itemDescription = data.itemDescription || data.description || data.packageDescription || "";
  const learning = buildLearningRecord({
    decisionId: data.productionDecisionId || data.decisionId || null,
    deliveryId: requestId,
    itemDescription,
    finalVerifiedWeight: data.finalVerifiedWeight || data.finalWeightKg || null,
    riderVerified: data.riderVerified === true,
    adminAdjusted: true,
    finalOutcome: {decision, finalCategory: finalCategory || null, finalWeightBand: finalWeightBand || null, finalHandlingFlags: finalHandlingFlags || []},
    learningApplied: false,
    createdAt: FieldValue.serverTimestamp(),
  });
  if (learning) {
    const recordId = learningRecordId({...learning, createdAt: null});
    const learningRef = db.collection("irisProductionLearningRecords").doc(recordId);
    try {
      await learningRef.create({
        ...learning,
        learningRecordId: recordId,
      });
    } catch (error) {
      if (error && error.code !== 6 && error.code !== "already-exists") {
        throw error;
      }
    }
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
