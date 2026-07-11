/* eslint-disable max-len, require-jsdoc */
const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {
  RECOGNITION_CONFIG,
  LEGEND_LIMIT,
  isEligibleLegendDelivery,
  legendAwardDecision,
  recognitionConfig,
  recognitionAwardDecision,
  buildRecognitionPatch,
  buildRecognitionRevokePatch,
} = require("./legends-core");

function recognitionCounterRef(db, type) {
  return db.collection("recognitionCounters").doc(type);
}

function recognitionAwardRef(db, type, subjectId) {
  return db.collection("recognitionAwards").doc(`${type}_${subjectId}`);
}

function recognitionNumberRef(db, type, number) {
  return db.collection("recognitionNumbers").doc(`${type}_${number}`);
}

function auditRecognition(transaction, db, payload) {
  transaction.set(db.collection("recognitionAuditLogs").doc(), {
    ...payload,
    createdAt: FieldValue.serverTimestamp(),
  });
  transaction.set(db.collection("adminAuditLogs").doc(), {
    action: payload.action,
    actionType: payload.action,
    recognitionType: payload.type,
    subjectId: payload.subjectId,
    subjectCollection: payload.subjectCollection,
    number: payload.number || null,
    reason: payload.reason || null,
    createdAt: FieldValue.serverTimestamp(),
  });
}

async function awardRecognition({
  db = getFirestore(),
  type,
  subjectRef,
  subjectId,
  subjectCollection,
  awardedBy = "system",
  source = "system",
  reason = null,
  metadata = {},
}) {
  const config = recognitionConfig(type);
  return db.runTransaction(async (transaction) => {
    const [subjectSnapshot, counterSnapshot, existingAwardSnapshot] = await Promise.all([
      transaction.get(subjectRef),
      transaction.get(recognitionCounterRef(db, type)),
      transaction.get(recognitionAwardRef(db, type, subjectId)),
    ]);
    if (!subjectSnapshot.exists) return {awarded: false, reason: "subject_not_found"};
    if (existingAwardSnapshot.exists && existingAwardSnapshot.data().awarded === true) {
      return {awarded: false, reason: "already_awarded", number: existingAwardSnapshot.data().number || null};
    }
    const counter = counterSnapshot.exists ? counterSnapshot.data() : {};
    const number = recognitionAwardDecision({
      type,
      subject: subjectSnapshot.data() || {},
      counter: {...counter, limit: config.limit},
    });
    if (number === null) return {awarded: false, reason: "not_eligible_or_limit_reached"};
    const numberSnapshot = await transaction.get(recognitionNumberRef(db, type, number));
    if (numberSnapshot.exists) return {awarded: false, reason: "number_already_used"};
    const timestamp = FieldValue.serverTimestamp();
    const patch = buildRecognitionPatch({type, number, awardedBy, source, reason, timestampValue: timestamp});
    transaction.set(subjectRef, {
      ...patch,
      updatedAt: timestamp,
    }, {merge: true});
    transaction.set(recognitionCounterRef(db, type), {
      totalAwarded: number,
      limit: config.limit,
      updatedAt: timestamp,
    }, {merge: true});
    transaction.set(recognitionAwardRef(db, type, subjectId), {
      type,
      subjectId,
      subjectCollection,
      awarded: true,
      number,
      awardedAt: timestamp,
      awardedBy,
      source,
      reason,
      metadata,
    }, {merge: true});
    transaction.set(recognitionNumberRef(db, type, number), {
      type,
      number,
      subjectId,
      subjectCollection,
      awardedAt: timestamp,
      awardedBy,
    });
    auditRecognition(transaction, db, {
      action: "recognition_awarded",
      type,
      subjectId,
      subjectCollection,
      number,
      awardedBy,
      reason,
      source,
      metadata,
    });
    return {awarded: true, number};
  });
}

async function revokeRecognition({
  db = getFirestore(),
  type,
  subjectRef,
  subjectId,
  subjectCollection,
  revokedBy,
  reason,
}) {
  recognitionConfig(type);
  return db.runTransaction(async (transaction) => {
    const awardRef = recognitionAwardRef(db, type, subjectId);
    const [subjectSnapshot, awardSnapshot] = await Promise.all([
      transaction.get(subjectRef),
      transaction.get(awardRef),
    ]);
    if (!subjectSnapshot.exists) return {revoked: false, reason: "subject_not_found"};
    const number = awardSnapshot.exists ? awardSnapshot.data().number || null : null;
    const timestamp = FieldValue.serverTimestamp();
    transaction.set(subjectRef, {
      ...buildRecognitionRevokePatch({type, revokedBy, reason, timestampValue: timestamp}),
      updatedAt: timestamp,
    }, {merge: true});
    transaction.set(awardRef, {
      awarded: false,
      revokedAt: timestamp,
      revokedBy,
      revokeReason: reason || null,
    }, {merge: true});
    auditRecognition(transaction, db, {
      action: "recognition_revoked",
      type,
      subjectId,
      subjectCollection,
      number,
      revokedBy,
      reason,
    });
    return {revoked: true, number};
  });
}

exports.awardLegendOnCompletion = functions.firestore.document("deliveryRequests/{deliveryId}").onUpdate(async (change, context) => {
  if (isEligibleLegendDelivery(change.before.data()) || !isEligibleLegendDelivery(change.after.data())) return null;
  const db = getFirestore();
  const deliveryRef = change.after.ref;
  const counterRef = recognitionCounterRef(db, "legend");
  const legacyCounterRef = db.collection("platformStats").doc("legends");

  return db.runTransaction(async (transaction) => {
    const deliverySnapshot = await transaction.get(deliveryRef);
    if (!deliverySnapshot.exists || !isEligibleLegendDelivery(deliverySnapshot.data())) return;
    const delivery = deliverySnapshot.data();
    const userId = `${delivery.senderId || delivery.userId || delivery.customerId || ""}`.trim();
    if (!userId) return;
    const userRef = db.collection("users").doc(userId);
    const [userSnapshot, counterSnapshot, legacyCounterSnapshot] = await Promise.all([
      transaction.get(userRef),
      transaction.get(counterRef),
      transaction.get(legacyCounterRef),
    ]);
    if (!userSnapshot.exists || userSnapshot.data().isLegend === true) return;
    const counter = counterSnapshot.exists ? counterSnapshot.data() : {};
    const legacyCounter = legacyCounterSnapshot.exists ? legacyCounterSnapshot.data() : {};
    const limit = Number(counter.limit || LEGEND_LIMIT);
    const totalAwarded = Math.max(
        Number(counter.totalAwarded || 0),
        Number(legacyCounter.totalAwarded || 0),
    );
    const legendNumber = legendAwardDecision({
      delivery,
      user: userSnapshot.data(),
      counter: {...counter, totalAwarded, limit},
    });
    if (legendNumber === null) return;
    const numberSnapshot = await transaction.get(recognitionNumberRef(db, "legend", legendNumber));
    if (numberSnapshot.exists) return;

    const timestamp = FieldValue.serverTimestamp();
    transaction.set(userRef, {
      ...buildRecognitionPatch({
        type: "legend",
        number: legendNumber,
        awardedBy: "system",
        source: "first_completed_delivery",
        reason: "First successful Circum service completed.",
        timestampValue: timestamp,
      }),
      legendSource: "first_completed_delivery",
      legendDeliveryId: context.params.deliveryId,
      legendCelebrationSeenAt: null,
    }, {merge: true});
    transaction.set(counterRef, {
      totalAwarded: legendNumber,
      limit,
      updatedAt: timestamp,
    }, {merge: true});
    transaction.set(recognitionAwardRef(db, "legend", userId), {
      type: "legend",
      subjectId: userId,
      subjectCollection: "users",
      awarded: true,
      number: legendNumber,
      awardedAt: timestamp,
      awardedBy: "system",
      source: "first_completed_delivery",
      reason: "First successful Circum service completed.",
      metadata: {deliveryId: context.params.deliveryId},
    }, {merge: true});
    transaction.set(recognitionNumberRef(db, "legend", legendNumber), {
      type: "legend",
      number: legendNumber,
      subjectId: userId,
      subjectCollection: "users",
      awardedAt: timestamp,
      awardedBy: "system",
    });
    transaction.set(deliveryRef, {
      legendAwarded: true,
      legendNumber,
      legendAwardedTo: userId,
    }, {merge: true});
    auditRecognition(transaction, db, {
      action: "recognition_awarded",
      type: "legend",
      subjectId: userId,
      subjectCollection: "users",
      number: legendNumber,
      awardedBy: "system",
      reason: "First successful Circum service completed.",
      source: "first_completed_delivery",
      metadata: {deliveryId: context.params.deliveryId},
    });
  });
});

function statusApproved(value) {
  return ["approved", "verified", "active"].includes(`${value || ""}`.trim().toLowerCase());
}

exports.awardFoundingRiderOnApproval = functions.firestore.document("riderProfiles/{riderId}").onWrite(async (change, context) => {
  const before = change.before.exists ? change.before.data() || {} : {};
  const after = change.after.exists ? change.after.data() || {} : {};
  const wasApproved = statusApproved(before.accountStatus || before.approvalStatus || before.onboardingStatus || before.verificationStatus);
  const isApproved = statusApproved(after.accountStatus || after.approvalStatus || after.onboardingStatus || after.verificationStatus);
  if (wasApproved || !isApproved) return null;
  return awardRecognition({
    type: "foundingRider",
    subjectRef: change.after.ref,
    subjectId: context.params.riderId,
    subjectCollection: "riderProfiles",
    awardedBy: "system",
    source: "rider_application_accepted",
    reason: "Rider accepted onto Circum.",
  });
});

exports.awardFoundingRiderOnRiderApproval = functions.firestore.document("riders/{riderId}").onWrite(async (change, context) => {
  const before = change.before.exists ? change.before.data() || {} : {};
  const after = change.after.exists ? change.after.data() || {} : {};
  const wasApproved = statusApproved(before.accountStatus || before.approvalStatus || before.onboardingStatus || before.verificationStatus);
  const isApproved = statusApproved(after.accountStatus || after.approvalStatus || after.onboardingStatus || after.verificationStatus);
  if (wasApproved || !isApproved) return null;
  return awardRecognition({
    type: "foundingRider",
    subjectRef: change.after.ref,
    subjectId: context.params.riderId,
    subjectCollection: "riders",
    awardedBy: "system",
    source: "rider_application_accepted",
    reason: "Rider accepted onto Circum.",
  });
});

exports.awardPatronOnBusinessInvoicePaid = functions.firestore.document("businessInvoices/{invoiceId}").onWrite(async (change, context) => {
  const before = change.before.exists ? change.before.data() || {} : {};
  const after = change.after.exists ? change.after.data() || {} : {};
  const wasPaid = ["paid", "paid_manually"].includes(`${before.status || ""}`.trim().toLowerCase());
  const isPaid = ["paid", "paid_manually"].includes(`${after.status || ""}`.trim().toLowerCase());
  if (wasPaid || !isPaid) return null;
  const businessId = `${after.businessId || after.accountId || ""}`.trim();
  if (!businessId) return null;
  return awardRecognition({
    type: "patron",
    subjectRef: getFirestore().collection("businessAccounts").doc(businessId),
    subjectId: businessId,
    subjectCollection: "businessAccounts",
    awardedBy: "system",
    source: "first_successful_business_transaction",
    reason: "First successful paid Circum Business transaction.",
    metadata: {invoiceId: context.params.invoiceId},
  });
});

function requireAdmin(context) {
  const token = context.auth && context.auth.token || {};
  if (token.admin === true || token.role === "admin" || Array.isArray(token.roles) && token.roles.includes("admin")) return;
  throw new functions.https.HttpsError("permission-denied", "Admin access is required.");
}

const SUBJECT_COLLECTIONS = new Set(["users", "riderProfiles", "riders", "businessAccounts"]);

exports.grantRecognition = functions.https.onCall(async (data, context) => {
  requireAdmin(context);
  const type = `${data.type || ""}`.trim();
  const subjectCollection = `${data.subjectCollection || ""}`.trim();
  const subjectId = `${data.subjectId || ""}`.trim();
  const reason = `${data.reason || ""}`.trim();
  if (!RECOGNITION_CONFIG[type] || !SUBJECT_COLLECTIONS.has(subjectCollection) || !subjectId || !reason) {
    throw new functions.https.HttpsError("invalid-argument", "Recognition type, subject and reason are required.");
  }
  return awardRecognition({
    type,
    subjectRef: getFirestore().collection(subjectCollection).doc(subjectId),
    subjectId,
    subjectCollection,
    awardedBy: context.auth.uid,
    source: "admin_manual_grant",
    reason,
  });
});

exports.revokeRecognition = functions.https.onCall(async (data, context) => {
  requireAdmin(context);
  const type = `${data.type || ""}`.trim();
  const subjectCollection = `${data.subjectCollection || ""}`.trim();
  const subjectId = `${data.subjectId || ""}`.trim();
  const reason = `${data.reason || ""}`.trim();
  if (!RECOGNITION_CONFIG[type] || !SUBJECT_COLLECTIONS.has(subjectCollection) || !subjectId || !reason) {
    throw new functions.https.HttpsError("invalid-argument", "Recognition type, subject and reason are required.");
  }
  return revokeRecognition({
    type,
    subjectRef: getFirestore().collection(subjectCollection).doc(subjectId),
    subjectId,
    subjectCollection,
    revokedBy: context.auth.uid,
    reason,
  });
});

exports._private = {awardRecognition, revokeRecognition, statusApproved};
