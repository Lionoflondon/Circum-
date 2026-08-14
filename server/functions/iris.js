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

const IRIS_DECISIONS = new Set(["accepted", "corrected", "unsupported", "prohibited", "referral_required"]);
const IRIS_CATEGORIES = new Set([
  "Documents", "Electronics", "Clothing & Fashion", "Personal Items & Luggage",
  "Food & Consumables", "Furniture & Home", "Tools & Machinery", "Medical & Pharmacy",
  "Business & Commercial", "Fragile & Valuable", "Other",
]);
const IRIS_WEIGHT_BANDS = new Set([
  "Small Parcel", "Medium Parcel", "Large Parcel", "Heavy Goods", "Heavy Duty Freight",
]);
const IRIS_HANDLING_FLAGS = new Set([
  "Fragile", "Perishable", "Keep Upright", "High Value", "Temperature Sensitive",
  "Bulky", "Awkward Shape", "Van Required", "Two Person Lift",
]);
const IRIS_REFERRALS = new Set(["vehicle_transport", "pet_transport", "funeral_transport", "specialist_freight", "specialist"]);
const IRIS_SERVICEABILITY = new Set(["serviceable", "manual_review", "blocked"]);

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

async function loadLearningExamples(description) {
  const text = `${description || ""}`.trim();
  if (!text) return [];
  const snapshot = await getFirestore().collection("history")
      .where("iris.learningSnapshot.version", "==", "v1")
      .limit(40)
      .get();
  // Only promoted learning fields enter inference. Never pass full history
  // documents, which may contain addresses, contacts, payment, Health+, Gift,
  // or Business-private data.
  return snapshot.docs.map((doc) => {
    const source = doc.data().iris && doc.data().iris.learningSnapshot || {};
    const original = source.originalRecommendation || {};
    const declaration = source.customerDeclaration || {};
    const outcome = source.finalOutcome || {};
    return {
      id: doc.id,
      learningSnapshot: {
        originalRecommendation: {
          detectedItem: `${original.detectedItem || ""}`.slice(0, 160),
          category: `${original.category || ""}`.slice(0, 80),
          weightBand: `${original.weightBand || ""}`.slice(0, 80),
        },
        customerDeclaration: {
          description: `${declaration.description || ""}`.slice(0, 240),
        },
        finalOutcome: {
          finalCategory: `${outcome.finalCategory || ""}`.slice(0, 80),
          finalWeightBand: `${outcome.finalWeightBand || ""}`.slice(0, 80),
        },
      },
    };
  });
}

const analyseIris = functions.runWith({enforceAppCheck: true}).https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated",
        "User must be authenticated to call Iris.");
  }
  const completedExamples = await loadLearningExamples(data.description || data.packageDescription);
  return customerSafeIris(classifyIris({...data, completedExamples}));
});

const adjudicateIris = functions.runWith({enforceAppCheck: true}).https.onCall(async (data, context) => {
  const adminUid = requireAdmin(context, "IRIS administrator access is required.");
  requireIrisAdmin(context);
  const {requestId, decision, finalCategory, finalWeightBand, finalHandlingFlags, reason, referralType, serviceabilityStatus} = data;
  if (!requestId || !decision || !reason) {
    throw new functions.https.HttpsError("invalid-argument",
        "requestId, decision, and reason are required.");
  }
  if (!IRIS_DECISIONS.has(decision)) {
    throw new functions.https.HttpsError("invalid-argument", "Unsupported IRIS decision.");
  }
  if (finalCategory != null && !IRIS_CATEGORIES.has(finalCategory)) {
    throw new functions.https.HttpsError("invalid-argument", "Unsupported IRIS category.");
  }
  if (finalWeightBand != null && !IRIS_WEIGHT_BANDS.has(finalWeightBand)) {
    throw new functions.https.HttpsError("invalid-argument", "Unsupported IRIS weight band.");
  }
  if (finalHandlingFlags != null && (!Array.isArray(finalHandlingFlags) ||
      finalHandlingFlags.some((flag) => !IRIS_HANDLING_FLAGS.has(flag)))) {
    throw new functions.https.HttpsError("invalid-argument", "Unsupported IRIS handling flag.");
  }
  if (referralType != null && !IRIS_REFERRALS.has(referralType)) {
    throw new functions.https.HttpsError("invalid-argument", "Unsupported IRIS referral type.");
  }
  if (serviceabilityStatus != null && !IRIS_SERVICEABILITY.has(serviceabilityStatus)) {
    throw new functions.https.HttpsError("invalid-argument", "Unsupported IRIS serviceability status.");
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
