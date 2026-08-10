/* eslint-disable max-len, require-jsdoc */
"use strict";

const crypto = require("crypto");

const VISUAL_MODEL_VERSION = "google-cloud-vision-v1-builtin-stable-2026-08-shadow-1";
const VISUAL_MODEL_PROVIDER = "google_cloud_vision";
const VISUAL_INFERENCE_MODE = "SHADOW";
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
  return Object.freeze({
    enabled: enabled && (!requestedVersion || requestedVersion === VISUAL_MODEL_VERSION),
    mode: enabled ? VISUAL_INFERENCE_MODE : "DISABLED",
    visualModelVersion: enabled ? VISUAL_MODEL_VERSION : null,
    rejectedUnknownVersion: Boolean(requestedVersion && requestedVersion !== VISUAL_MODEL_VERSION),
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
  return {
    requestId,
    imageHash,
    mode: VISUAL_INFERENCE_MODE,
    provider: VISUAL_MODEL_PROVIDER,
    visualModelVersion: VISUAL_MODEL_VERSION,
    timestamp: observedAt,
    status: primary ? "COMPLETED" : "UNCERTAIN",
    candidateObject: primary ? primary.name : null,
    candidateCategory: category ? category.category : null,
    confidenceScore,
    confidence: confidenceScore >= 0.8 ? "HIGH" : confidenceScore >= 0.5 ? "MEDIUM" : "LOW",
    handlingClues: risks.map((risk) => risk.code),
    riskClues: risks,
    sizeCue: risks.some((risk) => risk.code === "possible_oversized_item") ? "POSSIBLY_OVERSIZED" : "UNKNOWN",
    weightCue: risks.some((risk) => risk.code === "possible_oversized_item") ? "POTENTIALLY_HEAVY" : "UNKNOWN",
    annotations,
    authority: "EVIDENCE_ONLY",
    affectsCustomerDecision: false,
    affectsPricing: false,
    affectsWeightAuthority: false,
    affectsDispatch: false,
  };
}

function shadowComparison({deterministic = {}, visual = {}}) {
  const deterministicItem = clean(deterministic.inferredItemName || deterministic.detectedItem);
  const deterministicCategory = clean(deterministic.inferredCategory || deterministic.category);
  const visualItem = clean(visual.candidateObject);
  const visualCategory = clean(visual.candidateCategory);
  return {
    objectAgreement: Boolean(deterministicItem && visualItem && (deterministicItem.includes(visualItem) || visualItem.includes(deterministicItem))),
    categoryAgreement: Boolean(deterministicCategory && visualCategory && deterministicCategory === visualCategory),
    deterministicItemHash: deterministicItem ? crypto.createHash("sha256").update(deterministicItem).digest("hex") : null,
    visualItemHash: visualItem ? crypto.createHash("sha256").update(visualItem).digest("hex") : null,
    requiresReview: visual.status === "UNCERTAIN" || (visual.riskClues || []).length > 0,
  };
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
  VISUAL_MODEL_PROVIDER,
  VISUAL_MODEL_VERSION,
  clearVisualRuntimeCaches,
  clearVisualModelStateCache,
  currentVisualModelState,
  inferVisualEvidence,
  normalizeVisualModelState,
  shadowComparison,
  visualEvidenceFromResponse,
  warmVisualRuntime,
  _private: {riskClues, sanitizedAnnotations, strongestCategory},
};
