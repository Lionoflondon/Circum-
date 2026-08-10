/* eslint-disable max-len, require-jsdoc */
"use strict";

const crypto = require("crypto");
const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {classifyIris, weightBandFor} = require("./iris-core");
const {enforceIrisRequestLimit} = require("./iris-request-guard");
const {
  VISUAL_MODEL_VERSION,
  clearVisualModelStateCache,
  currentVisualModelState,
  inferVisualEvidence,
  shadowComparison,
} = require("./iris-visual-intelligence");

const MAX_IMAGE_BYTES = 10 * 1024 * 1024;
const MIN_IMAGE_BYTES = 128;
const ALLOWED_CONTENT_TYPES = new Set(["image/jpeg", "image/png", "image/webp"]);

function text(value, max = 1000) {
  return `${value || ""}`.trim().slice(0, max);
}

function decodeBase64Image(data) {
  const raw = text(data.imageBase64 || data.base64 || "", Math.ceil(MAX_IMAGE_BYTES * 1.4));
  const cleaned = raw.replace(/^data:image\/[a-z0-9.+-]+;base64,/i, "").replace(/\s/g, "");
  if (!cleaned) {
    throw new functions.https.HttpsError("invalid-argument", "Parcel photo is required.");
  }
  const bytes = Buffer.from(cleaned, "base64");
  if (bytes.length < MIN_IMAGE_BYTES || bytes.length > MAX_IMAGE_BYTES) {
    throw new functions.https.HttpsError("invalid-argument", "Parcel photo must be an image under 10MB.");
  }
  return bytes;
}

function detectImageType(bytes, declaredContentType) {
  if (bytes[0] === 0xff && bytes[1] === 0xd8) return "image/jpeg";
  if (bytes.slice(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) return "image/png";
  if (bytes.slice(0, 4).toString("ascii") === "RIFF" && bytes.slice(8, 12).toString("ascii") === "WEBP") return "image/webp";
  const declared = text(declaredContentType, 80).toLowerCase();
  if (ALLOWED_CONTENT_TYPES.has(declared)) return declared;
  throw new functions.https.HttpsError("invalid-argument", "Parcel photo must be JPG, PNG, or WebP.");
}

function pngDimensions(bytes) {
  if (bytes.length < 24) return null;
  return {width: bytes.readUInt32BE(16), height: bytes.readUInt32BE(20)};
}

function webpDimensions(bytes) {
  if (bytes.length < 30) return null;
  const chunk = bytes.slice(12, 16).toString("ascii");
  if (chunk === "VP8 " && bytes.length >= 30) {
    return {
      width: bytes.readUInt16LE(26) & 0x3fff,
      height: bytes.readUInt16LE(28) & 0x3fff,
    };
  }
  if (chunk === "VP8L" && bytes.length >= 25) {
    const b0 = bytes[21];
    const b1 = bytes[22];
    const b2 = bytes[23];
    const b3 = bytes[24];
    return {
      width: 1 + (((b1 & 0x3f) << 8) | b0),
      height: 1 + (((b3 & 0x0f) << 10) | (b2 << 2) | ((b1 & 0xc0) >> 6)),
    };
  }
  if (chunk === "VP8X" && bytes.length >= 30) {
    return {
      width: 1 + bytes.readUIntLE(24, 3),
      height: 1 + bytes.readUIntLE(27, 3),
    };
  }
  return null;
}

function jpegDimensions(bytes) {
  let offset = 2;
  while (offset + 9 < bytes.length) {
    if (bytes[offset] !== 0xff) {
      offset += 1;
      continue;
    }
    const marker = bytes[offset + 1];
    if (marker === 0xd8 || marker === 0xd9 || marker === 0x01) {
      offset += 2;
      continue;
    }
    const length = bytes.readUInt16BE(offset + 2);
    if (length < 2 || offset + 2 + length > bytes.length) return null;
    if ((marker >= 0xc0 && marker <= 0xc3) || (marker >= 0xc5 && marker <= 0xc7) || (marker >= 0xc9 && marker <= 0xcb) || (marker >= 0xcd && marker <= 0xcf)) {
      return {
        height: bytes.readUInt16BE(offset + 5),
        width: bytes.readUInt16BE(offset + 7),
      };
    }
    offset += 2 + length;
  }
  return null;
}

function imageDimensions(bytes, contentType) {
  if (contentType === "image/png") return pngDimensions(bytes);
  if (contentType === "image/webp") return webpDimensions(bytes);
  if (contentType === "image/jpeg") return jpegDimensions(bytes);
  return null;
}

function visualQuality({bytes, width, height}) {
  const megapixels = width && height ? (width * height) / 1000000 : 0;
  if (megapixels >= 2 && bytes.length >= 180000) return {score: 0.72, label: "clear"};
  if (megapixels >= 0.8 && bytes.length >= 80000) return {score: 0.6, label: "usable"};
  return {score: 0.42, label: "limited"};
}

function buildPhotoAnalysis({uid, data, bytes, contentType}) {
  const dimensions = imageDimensions(bytes, contentType);
  if (!dimensions || !dimensions.width || !dimensions.height) {
    throw new functions.https.HttpsError("invalid-argument", "Parcel photo dimensions could not be verified.");
  }
  const description = text(data.description || data.packageDescription, 1000);
  if (description.length < 3) {
    throw new functions.https.HttpsError("invalid-argument", "Item details are required before IRIS can use a parcel photo.");
  }
  const declaredWeightText = text(data.declaredWeightText || data.weight, 80);
  const baseIris = classifyIris({
    description,
    declaredWeightText,
    distanceMiles: Number(data.distanceMiles || 0),
    speed: data.speed || data.selectedSpeed || "",
    vehicleType: data.vehicleType || "",
  });
  const quality = visualQuality({bytes, width: dimensions.width, height: dimensions.height});
  const baseWeight = Number(baseIris.recommendation && baseIris.recommendation.estimatedWeightKg || 2);
  const confidence = Math.max(0.2, Math.min(0.97,
    Number(baseIris.recommendation && baseIris.recommendation.confidencePercent || 0) / 100));
  const weightBand = weightBandFor(baseWeight);
  const imageHash = crypto.createHash("sha256").update(bytes).digest("hex");
  const descriptionHash = crypto.createHash("sha256").update(description.toLowerCase()).digest("hex");
  const analysisId = crypto.createHash("sha256")
      .update(`${uid}:${imageHash}:${descriptionHash}:${declaredWeightText}`)
      .digest("hex")
      .slice(0, 32);
  return {
    analysisId,
    userId: uid,
    serverAuthored: true,
    authority: "backend",
    source: "backend_parcel_photo_verification",
    imageIntelligenceStatus: "verification_only",
    visualModelVersion: VISUAL_MODEL_VERSION,
    engineVersion: baseIris.engineVersion || null,
    knowledgeVersion: baseIris.knowledgeVersion || null,
    imageHash,
    descriptionHash,
    description,
    declaredWeightText: declaredWeightText || null,
    contentType,
    sizeBytes: bytes.length,
    width: dimensions.width,
    height: dimensions.height,
    imageQuality: quality.label,
    confidenceScore: confidence,
    confidence: confidence >= 0.7 ? "high" : confidence >= 0.55 ? "medium" : "low",
    inferredItemName: baseIris.recommendation && baseIris.recommendation.detectedItem || description || "Parcel",
    inferredCategory: baseIris.recommendation && baseIris.recommendation.category || "Parcel",
    estimatedWeightKg: Math.round(baseWeight * 100) / 100,
    baseIrisWeightKg: Math.round(baseWeight * 100) / 100,
    weightClass: weightBand.label,
    needsHumanReview: confidence < 0.7 || baseIris.verification && baseIris.verification.photoEvidenceRequired === true,
    riderGuidance: "Use the parcel photo as supporting evidence when verifying the parcel at pickup.",
    handlingNotes: "The photo was validated and retained for verification; item classification came from the supplied item details.",
  };
}

const analyseParcelPhotoForIris = functions.runWith({enforceAppCheck: true}).https.onCall(async (data, context) => {
  const startedAt = Date.now();
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Sign in to analyse a parcel photo.");
  }
  await enforceIrisRequestLimit({db: getFirestore(), uid: context.auth.uid, action: "analyse_iris_photo"});
  const bytes = decodeBase64Image(data || {});
  const contentType = detectImageType(bytes, data && data.contentType);
  const analysis = buildPhotoAnalysis({uid: context.auth.uid, data: data || {}, bytes, contentType});
  const db = getFirestore();
  const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000);
  const visualState = await currentVisualModelState(db);
  let visualShadow = null;
  let visualFailure = false;
  try {
    if (!visualState.enabled) throw new Error("visual_shadow_disabled");
    visualShadow = await inferVisualEvidence({
      bytes,
      requestId: analysis.analysisId,
      imageHash: analysis.imageHash,
    });
  } catch (error) {
    visualFailure = visualState.enabled;
    functions.logger.warn("iris_visual_shadow_failed", {
      requestId: analysis.analysisId,
      visualModelVersion: VISUAL_MODEL_VERSION,
      reason: visualState.enabled ? `${error && error.message || "visual_inference_failed"}`.slice(0, 80) : "visual_shadow_disabled",
    });
  }
  const comparison = visualShadow ? shadowComparison({deterministic: analysis, visual: visualShadow}) : null;
  const writes = [db.collection("irisPhotoAnalyses").doc(analysis.analysisId).set({
    ...analysis,
    createdAt: FieldValue.serverTimestamp(),
    expiresAt,
    visualShadowStatus: visualShadow ? visualShadow.status : visualState.enabled ? "FAILED" : "DISABLED",
  }, {merge: true})];
  if (visualShadow) {
    writes.push(db.collection("irisVisualShadowResults").doc(analysis.analysisId).set({
      ...visualShadow,
      comparison,
      userId: context.auth.uid,
      analysisId: analysis.analysisId,
      engineVersion: analysis.engineVersion,
      knowledgeVersion: analysis.knowledgeVersion,
      createdAt: FieldValue.serverTimestamp(),
      expiresAt,
    }, {merge: false}));
  }
  const metricDate = new Date().toISOString().slice(0, 10);
  writes.push(db.collection("irisMetricsDaily").doc(metricDate).set({
    metricDate,
    visualShadowRequestCount: FieldValue.increment(1),
    visualShadowSuccessCount: FieldValue.increment(visualShadow ? 1 : 0),
    visualShadowFailureCount: FieldValue.increment(visualFailure ? 1 : 0),
    visualObjectAgreementCount: FieldValue.increment(comparison && comparison.objectAgreement ? 1 : 0),
    visualCategoryAgreementCount: FieldValue.increment(comparison && comparison.categoryAgreement ? 1 : 0),
    visualReviewSignalCount: FieldValue.increment(comparison && comparison.requiresReview ? 1 : 0),
    visualModelVersion: VISUAL_MODEL_VERSION,
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true}));
  await Promise.all(writes);
  functions.logger.info("iris_classification_timing", {
    endpoint: "analyseParcelPhotoForIris",
    totalMs: Date.now() - startedAt,
    confidence: analysis.confidence,
    imageQuality: analysis.imageQuality,
    visualShadowStatus: visualShadow ? visualShadow.status : visualState.enabled ? "FAILED" : "DISABLED",
    visualModelVersion: visualState.visualModelVersion,
  });
  return {
    ...analysis,
    imageIntelligenceStatus: "visual_shadow",
    visualShadowStatus: visualShadow ? visualShadow.status : visualState.enabled ? "FAILED" : "DISABLED",
    imageHash: undefined,
    descriptionHash: undefined,
  };
});

const adminSetIrisVisualModelState = functions.runWith({enforceAppCheck: true}).https.onCall(async (data, context) => {
  if (!context.auth || context.auth.token.admin !== true || context.auth.token.irisAdmin !== true) {
    throw new functions.https.HttpsError("permission-denied", "IRIS administrator access is required.");
  }
  const action = text(data && data.action, 40).toUpperCase();
  if (!["PAUSE", "RESUME", "ROLLBACK"].includes(action)) {
    throw new functions.https.HttpsError("invalid-argument", "Choose PAUSE, RESUME, or ROLLBACK.");
  }
  const reason = text(data && data.reason, 500);
  if (reason.length < 5) {
    throw new functions.https.HttpsError("invalid-argument", "A reason is required.");
  }
  const db = getFirestore();
  const stateRef = db.collection("irisVisualModelState").doc("current");
  const eventId = crypto.createHash("sha256").update(`${action}:${VISUAL_MODEL_VERSION}:${reason}`).digest("hex").slice(0, 32);
  const eventRef = db.collection("irisVisualModelEvents").doc(eventId);
  await db.runTransaction(async (transaction) => {
    const [state, event] = await Promise.all([transaction.get(stateRef), transaction.get(eventRef)]);
    if (event.exists) return;
    const previous = state.exists ? state.data() || {} : {};
    const enabled = action === "RESUME";
    transaction.set(stateRef, {
      enabled,
      mode: enabled ? "SHADOW" : "DISABLED",
      visualModelVersion: enabled ? VISUAL_MODEL_VERSION : null,
      previousVisualModelVersion: previous.visualModelVersion || VISUAL_MODEL_VERSION,
      lastAction: action,
      updatedAt: FieldValue.serverTimestamp(),
      updatedBy: context.auth.uid,
      reason,
    }, {merge: true});
    transaction.create(eventRef, {
      eventId,
      action,
      reason,
      previousState: previous,
      newState: {enabled, mode: enabled ? "SHADOW" : "DISABLED", visualModelVersion: enabled ? VISUAL_MODEL_VERSION : null},
      actorId: context.auth.uid,
      createdAt: FieldValue.serverTimestamp(),
      immutable: true,
    });
  });
  clearVisualModelStateCache();
  return {ok: true, action, mode: action === "RESUME" ? "SHADOW" : "DISABLED", visualModelVersion: action === "RESUME" ? VISUAL_MODEL_VERSION : null};
});

async function verifiedPhotoAnalysis({db, uid, analysisId, description = ""}) {
  const id = text(analysisId, 80);
  if (!id) return null;
  const snap = await db.collection("irisPhotoAnalyses").doc(id).get();
  if (!snap.exists) return null;
  const data = snap.data() || {};
  if (data.userId !== uid || data.serverAuthored !== true || data.authority !== "backend") return null;
  const expectedDescriptionHash = crypto.createHash("sha256").update(text(description, 1000).toLowerCase()).digest("hex");
  if (data.descriptionHash !== expectedDescriptionHash) return null;
  const estimate = Number(data.estimatedWeightKg);
  if (!Number.isFinite(estimate) || estimate <= 0) return null;
  return data;
}

module.exports = {
  analyseParcelPhotoForIris,
  adminSetIrisVisualModelState,
  verifiedPhotoAnalysis,
  _private: {
    buildPhotoAnalysis,
    detectImageType,
    imageDimensions,
  },
};
