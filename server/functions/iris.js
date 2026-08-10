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
const {enforceIrisRequestLimit} = require("./iris-request-guard");

const IRIS_ENGINE_VERSION = "iris-engine-v1";
const IRIS_KNOWLEDGE_VERSION = "iris-knowledge-v1";
let canonicalKnowledgeCache = {expiresAt: 0, records: []};

function clean(value) {
  return `${value || ""}`.trim().toLowerCase();
}

function requireIrisAdmin(context) {
  const token = context.auth && context.auth.token ? context.auth.token : {};
  const roles = Array.isArray(token.roles) ? token.roles.map(clean) : [];
  const allowed = token.admin === true || token.superAdmin === true ||
    token.super_admin === true ||
    [clean(token.adminRole), clean(token.role), ...roles]
        .some((role) => ["admin", "super_admin", "operations_admin"].includes(role));
  if (!allowed) {
    throw new functions.https.HttpsError("permission-denied", "IRIS administrator access is required.");
  }
}

async function loadCanonicalKnowledge() {
  const now = Date.now();
  if (canonicalKnowledgeCache.expiresAt > now) return canonicalKnowledgeCache.records;
  const snapshot = await getFirestore().collection("irisCanonicalObjects")
      .where("status", "==", "active").limit(200).get();
  const records = snapshot.docs.map((doc) => ({id: doc.id, ...doc.data()}));
  canonicalKnowledgeCache = {records, expiresAt: now + 5 * 60 * 1000};
  return records;
}

const analyseIris = functions.runWith({enforceAppCheck: true}).https.onCall(async (data, context) => {
  const startedAt = Date.now();
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated",
        "User must be authenticated to call Iris.");
  }
  await enforceIrisRequestLimit({db: getFirestore(), uid: context.auth.uid, action: "analyse_iris"});
  const guardCompletedAt = Date.now();
  const canonicalKnowledge = await loadCanonicalKnowledge();
  const knowledgeCompletedAt = Date.now();
  const result = customerSafeIris(classifyIris({
    ...data,
    canonicalKnowledge,
    engineVersion: IRIS_ENGINE_VERSION,
    knowledgeVersion: IRIS_KNOWLEDGE_VERSION,
  }));
  functions.logger.info("iris_classification_timing", {
    endpoint: "analyseIris",
    engineVersion: IRIS_ENGINE_VERSION,
    knowledgeVersion: IRIS_KNOWLEDGE_VERSION,
    guardMs: guardCompletedAt - startedAt,
    knowledgeMs: knowledgeCompletedAt - guardCompletedAt,
    inferenceMs: Date.now() - knowledgeCompletedAt,
    totalMs: Date.now() - startedAt,
    status: result.status,
  });
  return result;
});

const adjudicateIris = functions.runWith({enforceAppCheck: true}).https.onCall(async (data, context) => {
  const adminUid = requireAdmin(context, "IRIS administrator access is required.");
  requireIrisAdmin(context);
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
