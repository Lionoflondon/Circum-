/* eslint-disable require-jsdoc */
"use strict";

const crypto = require("crypto");

const LATENCY_BUCKETS_MS = Object.freeze([250, 500, 1000, 2000, 5000, 10000]);
const RISK_RESOLUTIONS = Object.freeze(["CLEAR", "NEEDS_INFO", "REVIEW", "UNSUPPORTED", "PROHIBITED"]);

function clean(value) {
 return `${value || ""}`.trim().toLowerCase();
}
function bounded(value, min = 0, max = 100) {
 return Math.max(min, Math.min(max, Math.round(Number(value) || 0)));
}

function confidenceProfile({description, canonicalMatch, shipmentItems = [], declaredWeightText, photoEstimatedWeightKg, complianceStatus, weightAuthority}) {
  const tokens = clean(description).split(/\s+/).filter((token) => token.length > 2);
  const signals = [];
  let score = 38;
  if (canonicalMatch) {
 score += 46; signals.push("approved_canonical_match");
} else if (shipmentItems.length) {
 score += Math.min(46, 38 + shipmentItems.length * 4); signals.push("known_item_match");
}
  if (tokens.length >= 3) {
 score += 8; signals.push("specific_description");
} else if (tokens.length < 2 && !shipmentItems.length) {
 score -= 15; signals.push("low_information_description");
}
  if (clean(declaredWeightText)) {
 score += 5; signals.push("declared_weight");
}
  if (Number.isFinite(Number(photoEstimatedWeightKg)) && Number(photoEstimatedWeightKg) > 0) {
 score += 5; signals.push("verified_image_weight_signal");
}
  const candidates = weightAuthority && Array.isArray(weightAuthority.candidates) ? weightAuthority.candidates : [];
  const values = candidates.map((item) => Number(item.value)).filter(Number.isFinite);
  if (values.length >= 2 && Math.max(...values) > Math.max(1, Math.min(...values)) * 1.5) {
 score -= 18; signals.push("conflicting_weight_signals");
}
  if (complianceStatus !== "allowed") {
 score = Math.min(score, 58); signals.push("policy_resolution_required");
}
  score = bounded(score, 20, 97);
  return Object.freeze({score, band: score >= 80 ? "HIGH" : score >= 50 ? "MEDIUM" : "LOW", signals, calibrated: true});
}

function riskResolution({compliance = {}, serviceability = {}, handlingFlags = [], workflow}) {
  const status = clean(compliance.status);
  const reasons = Array.isArray(compliance.reasonCodes) ? compliance.reasonCodes : [];
  const flags = new Set(handlingFlags.map(clean));
  if (status === "prohibited") return {resolution: "PROHIBITED", reasonCodes: reasons, targetedQuestions: []};
  if (status === "unsupported") {
    if (reasons.includes("insufficient_item_description")) return {resolution: "NEEDS_INFO", reasonCodes: reasons, targetedQuestions: ["What is the item?", "What does it weigh?", "What are its dimensions?"]};
    return {resolution: "UNSUPPORTED", reasonCodes: reasons, targetedQuestions: []};
  }
  const specialist = clean(serviceability.status).includes("review") || clean(serviceability.serviceability).includes("review");
  const reviewFlags = ["hazardous", "battery", "liquid", "perishable", "temperature sensitive", "two person lift", "van required"];
  if (specialist || (reviewFlags.some((flag) => flags.has(flag)) && clean(workflow) !== "health+")) return {resolution: "REVIEW", reasonCodes: [...reasons, "special_handling_review"], targetedQuestions: []};
  return {resolution: "CLEAR", reasonCodes: reasons, targetedQuestions: []};
}

function latencyBucketKey(durationMs) {
  const duration = Math.max(0, Number(durationMs) || 0);
  const upper = LATENCY_BUCKETS_MS.find((value) => duration <= value);
  return upper ? `lte_${upper}` : "gt_10000";
}

function percentileFromBuckets(buckets = {}, percentile) {
  const ordered = [...LATENCY_BUCKETS_MS.map((upper) => [`lte_${upper}`, upper]), ["gt_10000", 10000]];
  const total = ordered.reduce((sum, [key]) => sum + (Number(buckets[key]) || 0), 0);
  if (!total) return null;
  const target = Math.ceil(total * percentile);
  let seen = 0;
  for (const [key, upper] of ordered) {
 seen += Number(buckets[key]) || 0; if (seen >= target) return upper;
}
  return 10000;
}

function healthProjection(metric = {}) {
  const requests = Number(metric.requestCount) || 0;
  const ratio = (value) => requests ? Math.round(((Number(value) || 0) / requests) * 10000) / 100 : 0;
  const adjudicatedRatio = (correct, total) => Number(total) ? Math.round(((Number(correct) || 0) / Number(total)) * 10000) / 100 : null;
  const visualRequests = Number(metric.visualShadowRequestCount) || 0;
  const visualRatio = (value) => visualRequests ? Math.round(((Number(value) || 0) / visualRequests) * 10000) / 100 : 0;
  return {requestVolume: requests, latencyMs: {p50: percentileFromBuckets(metric.latencyBuckets, 0.5), p95: percentileFromBuckets(metric.latencyBuckets, 0.95), p99: percentileFromBuckets(metric.latencyBuckets, 0.99)}, failureRatePercent: ratio(metric.failureCount), timeoutRatePercent: ratio(metric.timeoutCount), unsupportedRatePercent: ratio(metric.unsupportedCount), lowConfidenceRatePercent: ratio(metric.lowConfidenceCount), fastPathRatePercent: ratio(metric.fastPathCount), reusedRequestRatePercent: ratio(metric.reusedRequestCount), riderDisagreementRatePercent: ratio(metric.riderDisagreementCount), adminOverrideRatePercent: ratio(metric.adminOverrideCount), adjudicatedTruthCount: Number(metric.adjudicatedTruthCount) || 0, classificationCorrectCount: Number(metric.classificationCorrectCount) || 0, weightBandCorrectCount: Number(metric.weightBandCorrectCount) || 0, classificationAccuracyPercent: adjudicatedRatio(metric.classificationCorrectCount, metric.classificationAdjudicatedCount), weightBandAccuracyPercent: adjudicatedRatio(metric.weightBandCorrectCount, metric.weightBandAdjudicatedCount), visualShadowRequestCount: visualRequests, visualShadowSuccessRatePercent: visualRatio(metric.visualShadowSuccessCount), visualShadowFailureRatePercent: visualRatio(metric.visualShadowFailureCount), visualObjectAgreementRatePercent: visualRatio(metric.visualObjectAgreementCount), visualCategoryAgreementRatePercent: visualRatio(metric.visualCategoryAgreementCount), visualReviewSignalRatePercent: visualRatio(metric.visualReviewSignalCount), visualAdjudicatedTruthCount: Number(metric.visualAdjudicatedTruthCount) || 0, visualClassificationAccuracyPercent: adjudicatedRatio(metric.visualClassificationCorrectCount, metric.visualClassificationAdjudicatedCount), visualWeightBandAgreementPercent: adjudicatedRatio(metric.visualWeightBandCorrectCount, metric.visualWeightBandAdjudicatedCount)};
}

function requestFingerprint({uid, input = {}, engineVersion, knowledgeVersion}) {
  const stable = {
    uid,
    engineVersion,
    knowledgeVersion,
    description: clean(input.description || input.packageDescription),
    declaredWeightText: clean(input.declaredWeightText || input.weight),
    workflow: clean(input.workflow || input.serviceType || input.productType),
    speed: clean(input.speed || input.selectedSpeed),
    vehicleType: clean(input.vehicleType),
    photoAnalysisId: clean(input.photoAnalysisId || input.irisPhotoAnalysisId),
  };
  return crypto.createHash("sha256").update(JSON.stringify(stable)).digest("hex");
}

function knowledgeQualityCandidates(records = [], now = new Date()) {
  const candidates = [];
  const byName = new Map();
  for (const record of records.slice(0, 500)) {
    const id = `${record.id || record.canonicalId || "unknown"}`;
    const name = clean(record.canonicalName || record.objectName);
    if (!name) candidates.push({type: "missing_identity", recordIds: [id]});
    if (!record.category || !Number.isFinite(Number(record.knownWeight))) {
      candidates.push({type: "missing_coverage", recordIds: [id]});
    }
    if (name) {
      const previous = byName.get(name);
      if (previous && (clean(previous.category) !== clean(record.category) || Number(previous.knownWeight) !== Number(record.knownWeight))) {
        candidates.push({type: "conflicting_label", recordIds: [`${previous.id || previous.canonicalId}`, id]});
      } else if (previous) {
        candidates.push({type: "duplicate_item", recordIds: [`${previous.id || previous.canonicalId}`, id]});
      } else {
        byName.set(name, record);
      }
    }
    const reviewedAt = new Date(record.reviewedAt || record.promotedAt || record.updatedAt || 0);
    if (Number.isFinite(reviewedAt.getTime()) && reviewedAt.getTime() > 0 && now.getTime() - reviewedAt.getTime() > 365 * 24 * 60 * 60 * 1000) {
      candidates.push({type: "stale_entry", recordIds: [id]});
    }
  }
  return candidates;
}

module.exports = {LATENCY_BUCKETS_MS, RISK_RESOLUTIONS, confidenceProfile, healthProjection, knowledgeQualityCandidates, latencyBucketKey, percentileFromBuckets, requestFingerprint, riskResolution};
