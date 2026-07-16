/* eslint-disable max-len, require-jsdoc */
const crypto = require("crypto");

const IRIS_PRODUCTION_VERSION = "ipil-v1";

function numberValue(value, fallback = 0) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function text(value) {
  return `${value || ""}`.trim();
}

function arrayValue(value) {
  return Array.isArray(value) ? value.filter((item) => text(item)) : [];
}

function clampConfidence(value) {
  return Math.max(0, Math.min(100, Math.round(numberValue(value, 50))));
}

function customerConfidenceBand(value) {
  const score = clampConfidence(value);
  if (score >= 80) return "High";
  if (score >= 50) return "Medium";
  return "Low";
}

function reasonFromSignal(signal) {
  const normalized = text(signal).toLowerCase();
  if (!normalized) return null;
  if (normalized.includes("learning") || normalized.includes("verified") || normalized.includes("repository") || normalized.includes("match")) {
    return "Similar verified deliveries";
  }
  if (normalized.includes("photo") || normalized.includes("image")) {
    return "Parcel photos";
  }
  if (normalized.includes("dimension") || normalized.includes("size")) {
    return "Parcel dimensions";
  }
  if (normalized.includes("weight")) {
    return "Declared parcel weight";
  }
  if (normalized.includes("vehicle") || normalized.includes("van") || normalized.includes("bike") || normalized.includes("car")) {
    return "Handling requirements";
  }
  if (normalized.includes("fragile") || normalized.includes("high value") || normalized.includes("medical") || normalized.includes("vanguard")) {
    return "Special handling";
  }
  return "Parcel details";
}

function customerReasons(signals = []) {
  const reasons = [];
  for (const signal of signals) {
    const reason = reasonFromSignal(signal);
    if (reason && !reasons.includes(reason)) reasons.push(reason);
    if (reasons.length === 3) break;
  }
  return reasons.length ? reasons : ["Parcel details"];
}

function lowConfidenceSuggestions(confidence) {
  if (customerConfidenceBand(confidence) !== "Low") return [];
  return [
    "Take another photo",
    "Add dimensions",
    "Describe parcel",
    "Rider will verify at pickup",
  ];
}

function repositoryMatchFromIris(iris = {}) {
  const recommendation = iris.recommendation || {};
  const learningCount = numberValue(iris.internal && iris.internal.learningMatchedExamples, 0);
  if (learningCount > 0) {
    return {
      source: "verified_history",
      matchCount: learningCount,
      matchedItem: recommendation.detectedItem || recommendation.category || null,
    };
  }
  if (recommendation.detectedItem || recommendation.category) {
    return {
      source: "repository",
      matchCount: 1,
      matchedItem: recommendation.detectedItem || recommendation.category,
    };
  }
  return null;
}

function vehicleFromIris(iris = {}) {
  const matching = iris.internal && iris.internal.riderMatching || {};
  const flags = arrayValue(iris.recommendation && iris.recommendation.handlingFlags);
  if (matching.vehicleRequired === "van" || flags.includes("Van Required")) return "van";
  if (flags.includes("High Value") || flags.includes("Fragile") || flags.includes("Temperature Sensitive")) return "car";
  return "bike";
}

function productionReasonSignals(iris = {}, input = {}) {
  const signals = [];
  const repositoryMatch = repositoryMatchFromIris(iris);
  if (repositoryMatch) signals.push(repositoryMatch.source);
  if (input.photoUrl || input.imageUrl || input.photoPath) signals.push("photo");
  if (input.dimensions || input.userDimensions || input.lengthCm || input.widthCm || input.heightCm) signals.push("dimensions");
  if (input.weight || input.declaredWeightText || input.userWeight) signals.push("weight");
  arrayValue(iris.recommendation && iris.recommendation.handlingFlags).forEach((flag) => signals.push(flag));
  return signals;
}

function buildProductionDecision({decisionId, deliveryId, userId, input = {}, iris = {}, createdAt = null} = {}) {
  const recommendation = iris.recommendation || {};
  const internalConfidence = clampConfidence(recommendation.confidencePercent);
  const reasons = customerReasons(productionReasonSignals(iris, input));
  const recommendedVehicle = vehicleFromIris(iris);
  return {
    decisionId: text(decisionId),
    deliveryId: text(deliveryId) || null,
    createdAt: createdAt || new Date().toISOString(),
    itemDescription: text(input.description || input.packageDescription || recommendation.detectedItem),
    userId: text(userId) || null,
    userWeight: input.userWeight || input.weight || input.declaredWeightText || null,
    userDimensions: input.userDimensions || input.dimensions || null,
    repositoryMatch: repositoryMatchFromIris(iris),
    estimatedWeight: numberValue(recommendation.estimatedWeightKg, 0),
    recommendedVehicle,
    internalConfidence,
    customerConfidence: customerConfidenceBand(internalConfidence),
    reasons,
    finalVerifiedWeight: null,
    riderVerified: false,
    adminAdjusted: false,
    finalOutcome: null,
    learningApplied: false,
    lowConfidenceSuggestions: lowConfidenceSuggestions(internalConfidence),
    version: IRIS_PRODUCTION_VERSION,
  };
}

function buildLearningRecord({decisionId, deliveryId, itemDescription, repositoryMatch, finalVerifiedWeight, riderVerified = false, adminAdjusted = false, finalOutcome = null, learningApplied = false, createdAt = null} = {}) {
  const verifiedWeight = numberValue(finalVerifiedWeight, 0);
  if (verifiedWeight <= 0 && !finalOutcome) return null;
  return {
    decisionId: text(decisionId) || null,
    deliveryId: text(deliveryId) || null,
    itemDescription: text(itemDescription),
    repositoryMatch: repositoryMatch || null,
    finalVerifiedWeight: verifiedWeight > 0 ? verifiedWeight : null,
    riderVerified: riderVerified === true,
    adminAdjusted: adminAdjusted === true,
    finalOutcome: finalOutcome || null,
    learningApplied: learningApplied === true,
    createdAt: createdAt || new Date().toISOString(),
    version: IRIS_PRODUCTION_VERSION,
  };
}

function learningRecordId(record = {}) {
  const stable = [
    record.decisionId,
    record.deliveryId,
    text(record.itemDescription).toLowerCase(),
    record.finalVerifiedWeight,
    record.finalOutcome && JSON.stringify(record.finalOutcome),
    record.version,
  ].join("|");
  return crypto.createHash("sha256").update(stable).digest("hex");
}

module.exports = {
  IRIS_PRODUCTION_VERSION,
  buildLearningRecord,
  buildProductionDecision,
  customerConfidenceBand,
  customerReasons,
  learningRecordId,
  lowConfidenceSuggestions,
  repositoryMatchFromIris,
  vehicleFromIris,
};
