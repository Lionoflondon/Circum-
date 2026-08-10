/* eslint-disable max-len, require-jsdoc */
"use strict";

const crypto = require("crypto");

const VISUAL_MODEL_VERSION = "google-cloud-vision-v1-builtin-stable-2026-08-shadow-1";
const VISUAL_MODEL_PROVIDER = "google_cloud_vision";
const VISUAL_INFERENCE_MODE = "SHADOW";
const VISUAL_SYSTEM_STATUS = "PRODUCTION";
const VISUAL_AUTHORITY_MODE = "EVIDENCE_ONLY";
const VISUAL_EVALUATION_MODE = "SHADOW";
const MAX_VISUAL_RESULTS = 10;
const VISUAL_STATE_CACHE_MS = 60 * 1000;
const VISUAL_RESULT_CACHE_MS = 10 * 60 * 1000;
const MAX_CACHED_VISUAL_RESULTS = 100;
let visualStateCache = null;
let visualStateLoadPromise = null;
let imageAnnotatorClient = null;
const visualResultCache = new Map();

const CATEGORY_CLUES = Object.freeze([
  {category: "Electronics", terms: ["electronics", "electronic device", "computer", "laptop", "mobile phone", "television", "camera"]},
  {category: "Food & Perishables", terms: ["food", "fruit", "vegetable", "cake", "meal", "grocery"]},
  {category: "Clothing & Fashion", terms: ["clothing", "shoe", "footwear", "dress", "jacket", "bag"]},
  {category: "Personal Items & Luggage", terms: ["suitcase", "luggage", "backpack", "handbag"]},
  {category: "Furniture & Large Items", terms: ["furniture", "sofa", "mattress", "appliance", "refrigerator", "washing machine"]},
]);

const RISK_CLUES = Object.freeze([
  {code: "possible_battery_or_electronics", terms: ["battery", "electronics", "electronic device", "laptop", "mobile phone"]},
  {code: "possible_liquid_container", terms: ["bottle", "liquid", "beverage", "fluid"]},
  {code: "possible_fragile_item", terms: ["glass", "ceramic", "vase", "screen", "television"]},
  {code: "possible_perishable_item", terms: ["food", "fruit", "vegetable", "meal", "cake"]},
  {code: "possible_oversized_item", terms: ["furniture", "sofa", "mattress", "large appliance", "refrigerator"]},
  {code: "possible_hazard_marking", terms: ["hazard", "flammable", "corrosive", "toxic"]},
]);

function clean(value, max = 120) {
  return `${value || ""}`.trim().toLowerCase().slice(0, max);
}

function normalizeVisualModelState(value = {}) {
  const enabled = value.enabled !== false && value.mode !== "DISABLED";
  const requestedVersion = clean(value.visualModelVersion, 100);
  const requestedAuthority = `${value.authorityMode || VISUAL_AUTHORITY_MODE}`.trim().toUpperCase();
  const requestedEvaluation = `${value.evaluationMode || value.mode || VISUAL_EVALUATION_MODE}`.trim().toUpperCase();
  const safeAuthority = requestedAuthority === VISUAL_AUTHORITY_MODE;
  const safeEvaluation = requestedEvaluation === VISUAL_EVALUATION_MODE;
  const active = enabled && safeAuthority && safeEvaluation && (!requestedVersion || requestedVersion === VISUAL_MODEL_VERSION);
  return Object.freeze({
    enabled: active,
    mode: active ? VISUAL_INFERENCE_MODE : "DISABLED",
    systemStatus: VISUAL_SYSTEM_STATUS,
    evaluationMode: active ? VISUAL_EVALUATION_MODE : "DISABLED",
    authorityMode: VISUAL_AUTHORITY_MODE,
    visualModelVersion: active ? VISUAL_MODEL_VERSION : null,
    rejectedUnknownVersion: Boolean(requestedVersion && requestedVersion !== VISUAL_MODEL_VERSION) || !safeAuthority || !safeEvaluation,
  });
}

async function currentVisualModelState(db, now = Date.now()) {
  if (visualStateCache && visualStateCache.expiresAt > now) return visualStateCache.value;
  if (visualStateLoadPromise) return visualStateLoadPromise;
  visualStateLoadPromise = (async () => {
    const snapshot = await db.collection("irisVisualModelState").doc("current").get();
    const value = normalizeVisualModelState(snapshot.exists ? snapshot.data() : {});
    visualStateCache = {value, expiresAt: Date.now() + VISUAL_STATE_CACHE_MS};
    return value;
  })();
  try {
    return await visualStateLoadPromise;
  } finally {
    visualStateLoadPromise = null;
  }
}

function clearVisualModelStateCache() {
  visualStateCache = null;
}

function clearVisualRuntimeCaches() {
  visualStateCache = null;
  visualStateLoadPromise = null;
  imageAnnotatorClient = null;
  visualResultCache.clear();
}

function cachedVisualResult(key, now = Date.now()) {
  const cached = visualResultCache.get(key);
  if (!cached || cached.expiresAt <= now) {
    visualResultCache.delete(key);
    return null;
  }
  return {...cached.value, providerResultReused: true};
}

function cacheVisualResult(key, value, now = Date.now()) {
  if (visualResultCache.size >= MAX_CACHED_VISUAL_RESULTS) {
    const oldest = visualResultCache.keys().next().value;
    visualResultCache.delete(oldest);
  }
  visualResultCache.set(key, {value, expiresAt: now + VISUAL_RESULT_CACHE_MS});
}

function visualClient() {
  if (imageAnnotatorClient) return imageAnnotatorClient;
  const vision = require("@google-cloud/vision");
  imageAnnotatorClient = new vision.ImageAnnotatorClient();
  return imageAnnotatorClient;
}

async function warmVisualRuntime(db) {
  const client = visualClient();
  const tasks = [];
  if (typeof client.initialize === "function") tasks.push(client.initialize());
  if (db) tasks.push(currentVisualModelState(db));
  await Promise.all(tasks);
}

function boundedScore(value) {
  const score = Number(value);
  return Number.isFinite(score) ? Math.max(0, Math.min(1, Math.round(score * 1000) / 1000)) : 0;
}

function confidenceBand(value) {
  const score = boundedScore(value);
  return score >= 0.8 ? "HIGH" : score >= 0.5 ? "MEDIUM" : "LOW";
}

function calibratedVisualConfidence({providerConfidence, verifiedSamples = 0, verifiedCorrect = 0} = {}) {
  const providerScore = boundedScore(providerConfidence);
  const sampleSize = Math.max(0, Math.floor(Number(verifiedSamples) || 0));
  const correct = Math.max(0, Math.min(sampleSize, Math.floor(Number(verifiedCorrect) || 0)));
  if (sampleSize < 30) {
    return Object.freeze({
      band: confidenceBand(providerScore),
      calibrated: false,
      sampleSize,
      basis: "INSUFFICIENT_VERIFIED_OUTCOMES",
    });
  }
  const observedAccuracy = correct / sampleSize;
  const conservativeScore = Math.min(providerScore, observedAccuracy);
  return Object.freeze({
    band: confidenceBand(conservativeScore),
    calibrated: true,
    sampleSize,
    observedAccuracy: Math.round(observedAccuracy * 1000) / 1000,
    basis: "VERIFIED_OUTCOMES",
  });
}

function sanitizedAnnotations(response = {}) {
  const objects = (response.localizedObjectAnnotations || []).slice(0, MAX_VISUAL_RESULTS).map((item) => ({
    name: clean(item.name),
    confidence: boundedScore(item.score),
  })).filter((item) => item.name && item.confidence > 0);
  const labels = (response.labelAnnotations || []).slice(0, MAX_VISUAL_RESULTS).map((item) => ({
    name: clean(item.description),
    confidence: boundedScore(item.score),
  })).filter((item) => item.name && item.confidence > 0);
  return {objects, labels};
}

function strongestCategory(annotations) {
  const candidates = [...annotations.objects, ...annotations.labels];
  let best = null;
  for (const candidate of candidates) {
    const match = CATEGORY_CLUES.find((entry) => entry.terms.includes(candidate.name));
    if (match && (!best || candidate.confidence > best.confidence)) {
      best = {category: match.category, confidence: candidate.confidence};
    }
  }
  return best;
}

function riskClues(annotations) {
  const candidates = [...annotations.objects, ...annotations.labels];
  return RISK_CLUES.map((risk) => {
    const matching = candidates.filter((candidate) => risk.terms.includes(candidate.name));
    const confidence = matching.reduce((max, candidate) => Math.max(max, candidate.confidence), 0);
    return confidence >= 0.5 ? {code: risk.code, confidence, resolution: "REVIEW_SIGNAL_ONLY"} : null;
  }).filter(Boolean);
}

function visualEvidenceFromResponse({response, requestId, imageHash, observedAt = new Date()}) {
  const annotations = sanitizedAnnotations(response);
  const primary = [...annotations.objects, ...annotations.labels].sort((a, b) => b.confidence - a.confidence)[0] || null;
  const category = strongestCategory(annotations);
  const risks = riskClues(annotations);
  const confidenceScore = primary ? primary.confidence : 0;
  const calibratedConfidence = calibratedVisualConfidence({providerConfidence: confidenceScore});
  return {
    requestId,
    imageHash,
    mode: VISUAL_INFERENCE_MODE,
    systemStatus: VISUAL_SYSTEM_STATUS,
    evaluationMode: VISUAL_EVALUATION_MODE,
    authorityMode: VISUAL_AUTHORITY_MODE,
    provider: VISUAL_MODEL_PROVIDER,
    visualModelVersion: VISUAL_MODEL_VERSION,
    timestamp: observedAt,
    status: primary ? "COMPLETED" : "UNCERTAIN",
    candidateObject: primary ? primary.name : null,
    candidateCategory: category ? category.category : null,
    confidenceScore,
    confidence: calibratedConfidence.band,
    calibratedConfidence,
    handlingClues: risks.map((risk) => risk.code),
    riskClues: risks,
    sizeCue: risks.some((risk) => risk.code === "possible_oversized_item") ? "POSSIBLY_OVERSIZED" : "UNKNOWN",
    weightCue: risks.some((risk) => risk.code === "possible_oversized_item") ? "POTENTIALLY_HEAVY" : "UNKNOWN",
    annotations,
    authority: VISUAL_AUTHORITY_MODE,
    affectsCustomerDecision: false,
    affectsPricing: false,
    affectsWeightAuthority: false,
    affectsDispatch: false,
  };
}

function normalizedSignal(value = {}) {
  return {
    item: clean(value.item || value.detectedItem || value.inferredItemName || value.candidateObject),
    category: clean(value.category || value.inferredCategory || value.candidateCategory),
    weightBand: clean(value.weightBand && value.weightBand.label || value.weightBand || value.weightClass || value.proposedWeightBand),
    handling: new Set((value.handlingFlags || value.handlingClues || value.finalHandlingFlags || []).map(clean).filter(Boolean)),
    risks: new Set((value.riskCodes || value.riskClues || []).map((entry) => clean(entry && entry.code || entry)).filter(Boolean)),
  };
}

function valuesAgree(left, right) {
  if (!left || !right) return null;
  return left === right || left.includes(right) || right.includes(left);
}

function trustedTruth({admin = {}, measured = {}, finalOutcome = {}, approvedKnowledge = {}} = {}) {
  const candidates = [
    ["ADMIN_ADJUDICATION", admin],
    ["MEASURED_EVIDENCE", measured],
    ["FINAL_VERIFIED_OUTCOME", finalOutcome],
    ["APPROVED_CANONICAL_KNOWLEDGE", approvedKnowledge],
  ];
  for (const [source, value] of candidates) {
    const signal = normalizedSignal(value);
    if (signal.item || signal.category || signal.weightBand || signal.handling.size || signal.risks.size) {
      return {source, verified: true, signal};
    }
  }
  return {source: null, verified: false, signal: normalizedSignal()};
}

function comparisonStatus(checks, visual) {
  if (!visual.item && !visual.category && !visual.weightBand && !visual.handling.size && !visual.risks.size) return "UNKNOWN";
  const known = checks.filter((value) => value !== null);
  if (!known.length) return "UNKNOWN";
  if (known.every(Boolean)) return "AGREEMENT";
  if (known.every((value) => !value)) return "DISAGREEMENT";
  return "PARTIAL_AGREEMENT";
}

function buildVisualComparisonProjection({sender = {}, deterministic = {}, visual = {}, rider = {}, admin = {}, measured = {}, finalOutcome = {}, approvedKnowledge = {}} = {}) {
  const signals = {
    sender: normalizedSignal(sender),
    deterministic: normalizedSignal(deterministic),
    visual: normalizedSignal(visual),
    rider: normalizedSignal(rider),
  };
  const truth = trustedTruth({admin, measured, finalOutcome, approvedKnowledge});
  const objectAgreement = valuesAgree(signals.deterministic.item, signals.visual.item);
  const categoryAgreement = valuesAgree(signals.deterministic.category, signals.visual.category);
  const weightBandAgreement = valuesAgree(signals.deterministic.weightBand, signals.visual.weightBand);
  const senderCategoryAgreement = valuesAgree(signals.sender.category, signals.visual.category);
  const riderCategoryAgreement = valuesAgree(signals.rider.category, signals.visual.category);
  const truthCategoryCorrect = truth.verified ? valuesAgree(truth.signal.category, signals.visual.category) : null;
  const truthWeightBandCorrect = truth.verified ? valuesAgree(truth.signal.weightBand, signals.visual.weightBand) : null;
  const checks = [objectAgreement, categoryAgreement, weightBandAgreement, senderCategoryAgreement, riderCategoryAgreement];
  const status = comparisonStatus(checks, signals.visual);
  return {
    status,
    objectAgreement,
    categoryAgreement,
    weightBandAgreement,
    senderCategoryAgreement,
    riderCategoryAgreement,
    truth: {
      verified: truth.verified,
      source: truth.source,
      visualCategoryCorrect: truthCategoryCorrect,
      visualWeightBandCorrect: truthWeightBandCorrect,
    },
    deterministicItemHash: signals.deterministic.item ? crypto.createHash("sha256").update(signals.deterministic.item).digest("hex") : null,
    visualItemHash: signals.visual.item ? crypto.createHash("sha256").update(signals.visual.item).digest("hex") : null,
    requiresReview: visual.status === "UNCERTAIN" || status === "DISAGREEMENT" || (visual.riskClues || []).length > 0,
    authorityMode: VISUAL_AUTHORITY_MODE,
    affectsProductionTruth: false,
  };
}

function shadowComparison(input = {}) {
  return buildVisualComparisonProjection(input);
}

async function inferVisualEvidence({bytes, requestId, imageHash, client, timeoutMs = 4500, reuseResults = !client}) {
  const cacheKey = `${VISUAL_MODEL_VERSION}:${requestId}:${imageHash}`;
  if (reuseResults) {
    const cached = cachedVisualResult(cacheKey);
    if (cached) return cached;
  }
  const imageClient = client || visualClient();
  const providerRequest = imageClient.annotateImage({
    image: {content: bytes},
    features: [
      {type: "OBJECT_LOCALIZATION", maxResults: MAX_VISUAL_RESULTS, model: "builtin/stable"},
      {type: "LABEL_DETECTION", maxResults: MAX_VISUAL_RESULTS, model: "builtin/stable"},
    ],
  });
  let timeoutHandle;
  const timeout = new Promise((_, reject) => {
    timeoutHandle = setTimeout(() => reject(new Error("visual_inference_timeout")), timeoutMs);
  });
  let response;
  try {
    [response] = await Promise.race([providerRequest, timeout]);
  } finally {
    clearTimeout(timeoutHandle);
  }
  if (response && response.error && response.error.message) throw new Error("visual_provider_rejected_request");
  const result = visualEvidenceFromResponse({response, requestId, imageHash});
  if (reuseResults) cacheVisualResult(cacheKey, result);
  return result;
}

module.exports = {
  MAX_VISUAL_RESULTS,
  VISUAL_INFERENCE_MODE,
  VISUAL_SYSTEM_STATUS,
  VISUAL_AUTHORITY_MODE,
  VISUAL_EVALUATION_MODE,
  VISUAL_MODEL_PROVIDER,
  VISUAL_MODEL_VERSION,
  clearVisualRuntimeCaches,
  clearVisualModelStateCache,
  currentVisualModelState,
  inferVisualEvidence,
  normalizeVisualModelState,
  calibratedVisualConfidence,
  buildVisualComparisonProjection,
  shadowComparison,
  visualEvidenceFromResponse,
  warmVisualRuntime,
  _private: {riskClues, sanitizedAnnotations, strongestCategory},
};
