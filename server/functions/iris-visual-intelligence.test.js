/* eslint-disable max-len */
"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const visual = require("./iris-visual-intelligence");

const providerResponse = {
  localizedObjectAnnotations: [
    {name: "Laptop", score: 0.91, boundingPoly: {normalizedVertices: [{x: 0.1, y: 0.2}]}, providerInternal: "never expose"},
  ],
  labelAnnotations: [
    {description: "Electronics", score: 0.94, topicality: 0.77},
    {description: "Battery", score: 0.73},
    {description: "Bottle", score: 0.62},
  ],
};

test("visual inference produces versioned shadow-only structured evidence", () => {
  const result = visual.visualEvidenceFromResponse({
    response: providerResponse,
    requestId: "request-1",
    imageHash: "hash-1",
    observedAt: new Date("2026-08-10T10:00:00.000Z"),
  });
  assert.equal(result.mode, "SHADOW");
  assert.equal(result.visualModelVersion, visual.VISUAL_MODEL_VERSION);
  assert.equal(result.candidateObject, "electronics");
  assert.equal(result.candidateCategory, "Electronics");
  assert.equal(result.authority, "EVIDENCE_ONLY");
  assert.equal(result.affectsPricing, false);
  assert.equal(result.affectsWeightAuthority, false);
  assert.equal(result.affectsDispatch, false);
  assert.equal(JSON.stringify(result).includes("providerInternal"), false);
  assert.equal(JSON.stringify(result).includes("boundingPoly"), false);
});

test("visual risk clues create review signals rather than accusations", () => {
  const result = visual.visualEvidenceFromResponse({response: providerResponse, requestId: "request-2", imageHash: "hash-2"});
  assert.deepEqual(result.riskClues.map((item) => item.code), [
    "possible_battery_or_electronics",
    "possible_liquid_container",
  ]);
  assert.ok(result.riskClues.every((item) => item.resolution === "REVIEW_SIGNAL_ONLY"));
});

test("empty provider response is explicitly uncertain and low confidence", () => {
  const result = visual.visualEvidenceFromResponse({response: {}, requestId: "request-3", imageHash: "hash-3"});
  assert.equal(result.status, "UNCERTAIN");
  assert.equal(result.confidence, "LOW");
  assert.equal(result.candidateObject, null);
});

test("shadow comparison hashes labels and never promotes disagreement", () => {
  const comparison = visual.shadowComparison({
    deterministic: {inferredItemName: "Laptop in sleeve", inferredCategory: "Electronics"},
    visual: {candidateObject: "laptop", candidateCategory: "Electronics", status: "COMPLETED", riskClues: []},
  });
  assert.equal(comparison.objectAgreement, true);
  assert.equal(comparison.categoryAgreement, true);
  assert.equal(comparison.requiresReview, false);
  assert.match(comparison.deterministicItemHash, /^[a-f0-9]{64}$/);
  assert.equal(Object.hasOwn(comparison, "promoted"), false);
});

test("provider invocation is bounded and uses stable visual features", async () => {
  let request;
  const client = {
    async annotateImage(value) {
      request = value;
      return [providerResponse];
    },
  };
  const result = await visual.inferVisualEvidence({bytes: Buffer.from("image"), requestId: "request-4", imageHash: "hash-4", client});
  assert.deepEqual(request.features.map((item) => item.type), ["OBJECT_LOCALIZATION", "LABEL_DETECTION"]);
  assert.ok(request.features.every((item) => item.model === "builtin/stable"));
  assert.equal(result.requestId, "request-4");
});

test("provider timeout rejects without manufacturing visual evidence", async () => {
  const client = {annotateImage: () => new Promise(() => {})};
  await assert.rejects(
      visual.inferVisualEvidence({bytes: Buffer.from("image"), requestId: "request-5", imageHash: "hash-5", client, timeoutMs: 5}),
      /visual_inference_timeout/,
  );
});

test("visual model state fails closed for unknown versions and supports rollback disable", () => {
  assert.deepEqual(visual.normalizeVisualModelState({enabled: true, visualModelVersion: visual.VISUAL_MODEL_VERSION}), {
    enabled: true,
    mode: "SHADOW",
    visualModelVersion: visual.VISUAL_MODEL_VERSION,
    rejectedUnknownVersion: false,
  });
  const unknown = visual.normalizeVisualModelState({enabled: true, visualModelVersion: "unknown-provider-version"});
  assert.equal(unknown.enabled, false);
  assert.equal(unknown.rejectedUnknownVersion, true);
  const rolledBack = visual.normalizeVisualModelState({enabled: false, mode: "DISABLED"});
  assert.equal(rolledBack.enabled, false);
  assert.equal(rolledBack.visualModelVersion, null);
});
