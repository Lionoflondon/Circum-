/* eslint-disable max-len, require-jsdoc */
const test = require("node:test");
const assert = require("node:assert/strict");
const {classifyIris} = require("./iris-core");
const photoAnalysis = require("./iris-photo-analysis");
const senderBooking = require("./sender-booking");

function pngFixture({width = 1200, height = 900, size = 120000} = {}) {
  const bytes = Buffer.alloc(size);
  Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]).copy(bytes, 0);
  bytes.writeUInt32BE(width, 16);
  bytes.writeUInt32BE(height, 20);
  return bytes;
}

test("backend parcel photo analysis requires meaningful text IRIS details", () => {
  assert.throws(() => photoAnalysis._private.buildPhotoAnalysis({
    uid: "sender-1",
    data: {description: ""},
    bytes: pngFixture(),
    contentType: "image/png",
  }), /Item details are required/);
});

test("backend parcel photo analysis emits IRIS-compatible weight evidence", () => {
  const analysis = photoAnalysis._private.buildPhotoAnalysis({
    uid: "sender-1",
    data: {description: "laptop in sleeve", declaredWeightText: "1 kg"},
    bytes: pngFixture({width: 1600, height: 1200, size: 220000}),
    contentType: "image/png",
  });

  assert.equal(analysis.serverAuthored, true);
  assert.equal(analysis.authority, "backend");
  assert.equal(analysis.source, "backend_parcel_photo_analysis");
  assert.equal(analysis.userId, "sender-1");
  assert.ok(analysis.analysisId);
  assert.ok(analysis.estimatedWeightKg > 0);
  assert.ok(analysis.weightClass);
  assert.ok(["low", "medium", "high"].includes(analysis.confidence));
});

test("parcel photo signal does not replace text IRIS accuracy", () => {
  const textOnly = classifyIris({description: "iPhone 13 in box"});
  const analysis = photoAnalysis._private.buildPhotoAnalysis({
    uid: "sender-1",
    data: {description: "iPhone 13 in box"},
    bytes: pngFixture({width: 3000, height: 1000, size: 240000}),
    contentType: "image/png",
  });

  assert.equal(
      analysis.estimatedWeightKg,
      textOnly.recommendation.estimatedWeightKg,
  );
});

test("sender quote uses verified server photo analysis without trusting client photo fields", () => {
  const quote = senderBooking._private.quotePayload({
    quoteId: "quote-photo",
    distanceMiles: 4,
    weightKg: 1,
    parcel: {
      description: "laptop",
      weightKg: 1,
    },
    irisPhotoAnalysisId: "client-supplied-id",
    irisImageAnalysis: {
      estimatedWeightKg: 900,
      source: "client_forged",
    },
  }, "sender-1", {
    analysisId: "server-analysis",
    serverAuthored: true,
    source: "backend_parcel_photo_analysis",
    estimatedWeightKg: 12,
    weightClass: "Large Parcel",
    inferredItemName: "laptop",
    inferredCategory: "Electronics",
    confidence: "medium",
    confidenceScore: 0.6,
    width: 1600,
    height: 1200,
    imageQuality: "usable",
    needsHumanReview: true,
  });

  assert.equal(quote.weightKg, 12);
  assert.equal(quote.photoEstimatedWeightKg, 12);
  assert.equal(quote.photoAnalysis.analysisId, "server-analysis");
  assert.equal(quote.photoAnalysis.estimatedWeightKg, 12);
});
