/* eslint-disable max-len, require-jsdoc, quote-props */
const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {
  IRIS_ENGINE_VERSION,
  classifyIris,
  createLearningSnapshot,
  customerSafeIris,
  privateIris,
} = require("./iris-core");
const {requireAdmin} = require("./admin-auth");
const {enforceIrisRequestLimit} = require("./iris-request-guard");
const {healthProjection, knowledgeQualityCandidates, latencyBucketKey, requestFingerprint} = require("./iris-maturity-core");

const IRIS_KNOWLEDGE_VERSION = "iris-knowledge-v1";
let canonicalKnowledgeCache = {expiresAt: 0, records: [], knowledgeVersion: IRIS_KNOWLEDGE_VERSION, lookupKey: null};
const inferenceResultCache = new Map();
const INFERENCE_CACHE_TTL_MS = 2 * 60 * 1000;

function clean(value) {
  return `${value || ""}`.trim().toLowerCase();
}

function canonicalVisualHandling(value) {
  const normalized = clean(value);
  const aliases = {
    possible_battery_or_electronics: "battery",
    possible_liquid_container: "liquid",
    possible_fragile_item: "fragile",
    possible_perishable_item: "perishable",
    possible_oversized_item: "oversized",
  };
  return aliases[normalized] || normalized;
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

async function loadCanonicalKnowledge(description) {
  const now = Date.now();
  const lookupKey = clean(description);
  if (canonicalKnowledgeCache.expiresAt > now && (!canonicalKnowledgeCache.lookupKey || canonicalKnowledgeCache.lookupKey === lookupKey)) return canonicalKnowledgeCache;
  const db = getFirestore();
  const [exact, state] = await Promise.all([
    lookupKey ? db.collection("irisCanonicalObjects").where("lookupKeys", "array-contains", lookupKey).limit(10).get() : Promise.resolve(null),
    db.collection("irisKnowledgeState").doc("current").get(),
  ]);
  const exactPromoted = exact && exact.docs.some((doc) => doc.data().status === "active" && doc.data().repositoryReviewStatus === "promoted");
  const snapshot = exactPromoted ? exact : await db.collection("irisCanonicalObjects").where("status", "==", "active").where("repositoryReviewStatus", "==", "promoted").limit(200).get();
  const records = snapshot.docs.map((doc) => ({id: doc.id, ...doc.data()}));
  const knowledgeVersion = state.exists && state.data().knowledgeVersion || IRIS_KNOWLEDGE_VERSION;
  canonicalKnowledgeCache = {records, knowledgeVersion, lookupKey: exactPromoted ? lookupKey : null, expiresAt: now + 60 * 1000};
  return canonicalKnowledgeCache;
}

function metricDate(now = new Date()) {
 return now.toISOString().slice(0, 10);
}

async function recordIrisRequestMetric({result, durationMs, failed = false, timeout = false, reused = false}) {
  const confidence = Number(result && result.recommendation && result.recommendation.confidencePercent || 0);
  const path = result && result.internal && result.internal.inferencePath;
  const bucket = latencyBucketKey(durationMs);
  await getFirestore().collection("irisMetricsDaily").doc(metricDate()).set({
    metricDate: metricDate(),
    requestCount: FieldValue.increment(1),
    latencyBuckets: {[bucket]: FieldValue.increment(1)},
    failureCount: FieldValue.increment(failed ? 1 : 0),
    timeoutCount: FieldValue.increment(timeout ? 1 : 0),
    unsupportedCount: FieldValue.increment(result && ["unsupported", "prohibited"].includes(result.status) ? 1 : 0),
    lowConfidenceCount: FieldValue.increment(confidence < 50 ? 1 : 0),
    fastPathCount: FieldValue.increment(path === "canonical_fast_path" ? 1 : 0),
    reusedRequestCount: FieldValue.increment(reused ? 1 : 0),
    engineVersion: result && result.engineVersion || IRIS_ENGINE_VERSION,
    knowledgeVersion: result && result.knowledgeVersion || IRIS_KNOWLEDGE_VERSION,
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
}

async function safelyRecordIrisRequestMetric(metric) {
  try {
    await recordIrisRequestMetric(metric);
  } catch (error) {
    functions.logger.warn("iris_metric_write_failed", {message: error && error.message});
  }
}

const analyseIris = functions.runWith({enforceAppCheck: true}).https.onCall(async (data, context) => {
  const startedAt = Date.now();
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated",
        "User must be authenticated to call Iris.");
  }
  let knowledge;
  try {
    await enforceIrisRequestLimit({db: getFirestore(), uid: context.auth.uid, action: "analyse_iris"});
    const guardCompletedAt = Date.now();
    knowledge = await loadCanonicalKnowledge(data && (data.description || data.packageDescription));
    const knowledgeCompletedAt = Date.now();
    const fingerprint = requestFingerprint({uid: context.auth.uid, input: data || {}, engineVersion: IRIS_ENGINE_VERSION, knowledgeVersion: knowledge.knowledgeVersion});
    const cached = inferenceResultCache.get(fingerprint);
    if (cached && cached.expiresAt > Date.now()) {
      await safelyRecordIrisRequestMetric({result: cached.classified, durationMs: Date.now() - startedAt, reused: true});
      return cached.result;
    }
    const classified = classifyIris({
      ...data,
      canonicalKnowledge: knowledge.records,
      engineVersion: IRIS_ENGINE_VERSION,
      knowledgeVersion: knowledge.knowledgeVersion,
    });
    const result = customerSafeIris(classified);
    inferenceResultCache.set(fingerprint, {classified, result, expiresAt: Date.now() + INFERENCE_CACHE_TTL_MS});
    if (inferenceResultCache.size > 100) inferenceResultCache.delete(inferenceResultCache.keys().next().value);
    const totalMs = Date.now() - startedAt;
    await safelyRecordIrisRequestMetric({result: classified, durationMs: totalMs});
    functions.logger.info("iris_classification_timing", {
      endpoint: "analyseIris",
      engineVersion: IRIS_ENGINE_VERSION,
      knowledgeVersion: knowledge.knowledgeVersion,
      guardMs: guardCompletedAt - startedAt,
      knowledgeMs: knowledgeCompletedAt - guardCompletedAt,
      inferenceMs: Date.now() - knowledgeCompletedAt,
      totalMs,
      status: result.status,
    });
    return result;
  } catch (error) {
    const message = clean(error && error.message);
    await safelyRecordIrisRequestMetric({
      result: {engineVersion: IRIS_ENGINE_VERSION, knowledgeVersion: knowledge && knowledge.knowledgeVersion},
      durationMs: Date.now() - startedAt,
      failed: true,
      timeout: message.includes("timeout") || message.includes("deadline"),
    });
    throw error;
  }
});

const getIrisHealthMetrics = functions.runWith({enforceAppCheck: true}).https.onCall(async (data, context) => {
  requireAdmin(context, "IRIS administrator access is required.");
  requireIrisAdmin(context);
  const days = Math.max(1, Math.min(30, Number(data && data.days) || 7));
  const snapshot = await getFirestore().collection("irisMetricsDaily").orderBy("metricDate", "desc").limit(days).get();
  const daily = snapshot.docs.map((doc) => ({date: doc.id, ...healthProjection(doc.data()), engineVersion: doc.data().engineVersion || null, knowledgeVersion: doc.data().knowledgeVersion || null}));
  const [learning, promoted, visualStateSnapshot] = await Promise.all([
    getFirestore().collection("irisLearningCases").where("reviewStatus", "in", ["pending_review", "approved"]).count().get(),
    getFirestore().collection("irisCanonicalObjects").where("status", "==", "active").where("repositoryReviewStatus", "==", "promoted").count().get(),
    getFirestore().collection("irisVisualModelState").doc("current").get(),
  ]);
  const knowledge = await getFirestore().collection("irisCanonicalObjects").where("status", "==", "active").limit(200).get();
  const qualityCandidates = knowledgeQualityCandidates(knowledge.docs.map((doc) => ({id: doc.id, ...doc.data()})));
  const visualState = visualStateSnapshot.exists ? visualStateSnapshot.data() || {} : {};
  return {days, daily, learningQueueSize: learning.data().count, promotedKnowledgeCount: promoted.data().count, engineVersion: IRIS_ENGINE_VERSION, currentKnowledgeVersion: daily[0] && daily[0].knowledgeVersion || IRIS_KNOWLEDGE_VERSION, visualModelVersion: visualState.visualModelVersion || daily[0] && daily[0].visualModelVersion || null, visualSystemStatus: visualState.systemStatus || "PRODUCTION", visualEvaluationMode: visualState.evaluationMode || visualState.mode || "SHADOW", visualAuthorityMode: visualState.authorityMode || "EVIDENCE_ONLY", promotionReviewState: "POLICY_THRESHOLDS_REQUIRED", automaticPromotionAllowed: false, dataQuality: {boundedRecordsInspected: knowledge.size, reviewCandidateCount: qualityCandidates.length, candidates: qualityCandidates.slice(0, 50)}};
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
  const current = doc.data() || {};
  const priorIris = current.iris || {};
  const priorRecommendation = priorIris.recommendation || {};
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
  const categoryAdjudicated = Boolean(finalCategory);
  const weightBandAdjudicated = Boolean(finalWeightBand);
  const categoryCorrect = categoryAdjudicated && clean(priorRecommendation.category) === clean(finalCategory);
  const weightBandCorrect = weightBandAdjudicated && clean(priorRecommendation.weightBand && priorRecommendation.weightBand.label) === clean(finalWeightBand);
  const adminOverride = decision === "corrected" || (categoryAdjudicated && !categoryCorrect) || (weightBandAdjudicated && !weightBandCorrect);
  const visualAnalysisId = current.irisPhotoAnalysisId || current.irisPhotoAnalysis && current.irisPhotoAnalysis.analysisId || priorIris.photoAnalysis && priorIris.photoAnalysis.analysisId || null;
  let visualTruthMetrics = {};
  if (visualAnalysisId) {
    const visualSnapshot = await db.collection("irisVisualShadowResults").doc(visualAnalysisId).get();
    if (visualSnapshot.exists) {
      const visual = visualSnapshot.data() || {};
      const visualCategoryAdjudicated = Boolean(finalCategory);
      const visualWeightAdjudicated = Boolean(finalWeightBand && visual.weightBandCue);
      const visualCategoryCorrect = visualCategoryAdjudicated && clean(visual.candidateCategory) === clean(finalCategory);
      const visualWeightCorrect = visualWeightAdjudicated && clean(visual.weightBandCue) === clean(finalWeightBand);
      const truthHandling = new Set((finalHandlingFlags || []).map(clean));
      const visualHandling = new Set((visual.handlingClues || []).map(canonicalVisualHandling));
      const handlingAdjudicated = truthHandling.size > 0;
      const handlingCorrect = handlingAdjudicated && [...truthHandling].every((value) => visualHandling.has(value));
      // Handling adjudication is not a dedicated hazardous-goods truth label.
      // Risk accuracy remains unreported until that stronger truth exists.
      const riskAdjudicated = false;
      visualTruthMetrics = {
        visualAdjudicatedTruthCount: FieldValue.increment(1),
        visualClassificationAdjudicatedCount: FieldValue.increment(visualCategoryAdjudicated ? 1 : 0),
        visualClassificationCorrectCount: FieldValue.increment(visualCategoryCorrect ? 1 : 0),
        visualWeightBandAdjudicatedCount: FieldValue.increment(visualWeightAdjudicated ? 1 : 0),
        visualWeightBandCorrectCount: FieldValue.increment(visualWeightCorrect ? 1 : 0),
        visualHandlingAdjudicatedCount: FieldValue.increment(handlingAdjudicated ? 1 : 0),
        visualHandlingCorrectCount: FieldValue.increment(handlingCorrect ? 1 : 0),
        visualRiskAdjudicatedCount: FieldValue.increment(riskAdjudicated ? 1 : 0),
        visualRiskCorrectCount: FieldValue.increment(0),
        visualRiskFalsePositiveCount: FieldValue.increment(0),
        visualRiskFalseNegativeCount: FieldValue.increment(0),
        visualCorrectionCount: FieldValue.increment((visualCategoryAdjudicated && !visualCategoryCorrect) || (visualWeightAdjudicated && !visualWeightCorrect) ? 1 : 0),
      };
      await visualSnapshot.ref.set({
        trustedOutcome: {
          source: "ADMIN_ADJUDICATION",
          category: finalCategory || null,
          weightBand: finalWeightBand || null,
          handlingFlags: finalHandlingFlags || [],
          visualCategoryCorrect: visualCategoryAdjudicated ? visualCategoryCorrect : null,
          visualWeightBandCorrect: visualWeightAdjudicated ? visualWeightCorrect : null,
        },
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
      await db.collection("irisLearningCases").doc(`visual_${visualAnalysisId}`).set({
        reviewStatus: "adjudicated",
        learningStatus: "adjudicated",
        trustedOutcomeSource: "ADMIN_ADJUDICATION",
        trustedCategory: finalCategory || null,
        trustedWeightBand: finalWeightBand || null,
        reviewedBy: adminUid,
        reviewedAt: FieldValue.serverTimestamp(),
        productionTruthAffected: false,
      }, {merge: true});
    }
  }
  await db.collection("irisMetricsDaily").doc(metricDate()).set({
    metricDate: metricDate(),
    adjudicatedTruthCount: FieldValue.increment(1),
    classificationAdjudicatedCount: FieldValue.increment(categoryAdjudicated ? 1 : 0),
    classificationCorrectCount: FieldValue.increment(categoryCorrect ? 1 : 0),
    weightBandAdjudicatedCount: FieldValue.increment(weightBandAdjudicated ? 1 : 0),
    weightBandCorrectCount: FieldValue.increment(weightBandCorrect ? 1 : 0),
    adminOverrideCount: FieldValue.increment(adminOverride ? 1 : 0),
    ...visualTruthMetrics,
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
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
  getIrisHealthMetrics,
  writeLearningSnapshotForRequest,
  customerSafeIris,
  privateIris,
};
