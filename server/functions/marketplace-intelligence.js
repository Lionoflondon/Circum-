/* eslint-disable max-len, require-jsdoc */
"use strict";

const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue, Timestamp} = require("firebase-admin/firestore");
const {requireAdmin} = require("./admin-auth");
const {appendOperationalEvent} = require("./delivery-operational-events");
const {emitNotification} = require("./communication-engine");

const MODEL_VERSION = "2026-08-marketplace-intelligence-v1";
const BASE_SCORE = 80;
const EVENT_ADJUSTMENTS = Object.freeze({
  Completed: {points: 2, reason: "Successful delivery completed", counter: "completedDeliveries"},
  EvidenceUploaded: {points: 1, reason: "Required delivery evidence supplied", counter: "evidenceCompliantDeliveries"},
  RiderCancelled: {points: -6, reason: "Rider cancelled accepted work", counter: "cancelledDeliveries"},
  Failed: {points: -8, reason: "Assigned delivery failed", counter: "failedDeliveries"},
  RiderRejected: {points: -1, reason: "Accepted work later rejected", counter: "rejectedDeliveries"},
  ConfirmedOperationalIncident: {points: -3, reason: "Operational review confirmed a Rider-attributable incident", counter: "operationalIncidents"},
  GPSRiskFlag: {points: -2, reason: "GPS movement requires operational review", counter: "gpsReviewSignals"},
  VerificationFailed: {points: -4, reason: "Delivery verification failed", counter: "verificationFailures"},
  ConfirmedDeliveryDispute: {points: -4, reason: "Operational review confirmed a Rider-attributable dispute", counter: "disputes"},
});

function clean(value, max = 300) {
  return `${value || ""}`.trim().slice(0, max);
}

function clampScore(value) {
  return Math.max(0, Math.min(100, Math.round(Number(value) || 0)));
}

function trend(previous, next) {
  if (next >= previous + 2) return "IMPROVING";
  if (next <= previous - 2) return "DECLINING";
  return "STABLE";
}

function riskLevel(score, openHighRiskFlags = 0) {
  if (openHighRiskFlags > 0 || score < 50) return "RED";
  if (score < 70) return "AMBER";
  return "GREEN";
}

function riderIdFor(event = {}, delivery = {}) {
  if (`${event.actorType || ""}`.toLowerCase() === "rider" && clean(event.actorId)) return clean(event.actorId);
  return clean(delivery.assignedRiderId || delivery.riderId || delivery.driverId || delivery.assignedDriverId);
}

function adjustmentFor(event = {}, delivery = {}) {
  let eventType = clean(event.eventType, 100);
  if (eventType === "Cancelled" && `${event.actorType || ""}`.toLowerCase() === "rider") eventType = "RiderCancelled";
  let policy = EVENT_ADJUSTMENTS[eventType];
  if (eventType === "CustomerRatingReceived") {
    const rating = Number(event.metadata && event.metadata.rating);
    if (rating >= 4) policy = {points: 1, reason: "Positive customer rating received", counter: "positiveRatings"};
    if (rating > 0 && rating <= 2) policy = {points: -2, reason: "Low customer rating requires trend review", counter: "lowRatings"};
  }
  if (!policy) return null;
  const riderId = riderIdFor(event, delivery);
  if (!riderId) return null;
  return {...policy, riderId, deliveryId: clean(event.deliveryId), eventId: clean(event.eventId)};
}

function flagPolicy(event = {}) {
  const type = clean(event.eventType, 100);
  const incidentType = clean(event.metadata && event.metadata.incidentType, 100);
  if (type === "GPSRiskFlag") return {flagType: clean(event.metadata && event.metadata.signal, 100) || "gps_anomaly", severity: clean(event.metadata && event.metadata.severity, 20) || "AMBER"};
  if (type === "VerificationFailed") return {flagType: "verification_failure", severity: "AMBER"};
  if (type === "DisputeCreated") return {flagType: "delivery_dispute", severity: "AMBER"};
  if (type === "IncidentCreated" && ["collected_no_movement", "dropoff_completion_delay"].includes(incidentType)) return {flagType: incidentType, severity: "RED"};
  if (type === "IncidentCreated") return {flagType: incidentType || "operational_incident", severity: "AMBER"};
  return null;
}

function dispatchIntelligenceSignal(profile = {}) {
  const score = clampScore(profile.reliabilityScore === undefined ? BASE_SCORE : profile.reliabilityScore);
  const risk = clean(profile.reliabilityRiskLevel || profile.marketplaceRiskLevel, 20).toUpperCase() || riskLevel(score);
  return {score, riskLevel: risk, priorityBand: score >= 85 && risk === "GREEN" ? "PREFERRED" : score < 60 || risk === "RED" ? "REVIEW" : "STANDARD", advisoryOnly: true};
}

function number(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function coordinate(value = {}) {
  const source = value.geopoint || value.currentLocation || value.location || value;
  const latitude = number(source.latitude ?? source.lat ?? source._latitude);
  const longitude = number(source.longitude ?? source.lng ?? source.lon ?? source._longitude);
  if (latitude === null || longitude === null || Math.abs(latitude) > 90 || Math.abs(longitude) > 180) return null;
  return {latitude, longitude};
}

function timestampMillis(value) {
  if (!value) return null;
  if (typeof value.toMillis === "function") return value.toMillis();
  if (value._seconds !== undefined) return Number(value._seconds) * 1000;
  const parsed = new Date(value).getTime();
  return Number.isFinite(parsed) ? parsed : null;
}

function distanceMeters(a, b) {
  if (!a || !b) return null;
  const radians = (degrees) => degrees * Math.PI / 180;
  const dLat = radians(b.latitude - a.latitude);
  const dLng = radians(b.longitude - a.longitude);
  const x = Math.sin(dLat / 2) ** 2 + Math.cos(radians(a.latitude)) * Math.cos(radians(b.latitude)) * Math.sin(dLng / 2) ** 2;
  return 6371000 * 2 * Math.atan2(Math.sqrt(x), Math.sqrt(1 - x));
}

function gpsRiskDecision(before = {}, after = {}) {
  const from = coordinate(before);
  const to = coordinate(after);
  const fromTime = timestampMillis(before.updatedAt || before.recordedAt || before.timestamp);
  const toTime = timestampMillis(after.updatedAt || after.recordedAt || after.timestamp);
  if (!to) return {flag: true, signal: "gps_unavailable", severity: "AMBER", evidence: {hasPreviousCoordinate: Boolean(from)}};
  if (!from || !fromTime || !toTime || toTime <= fromTime) return {flag: false};
  const elapsedSeconds = (toTime - fromTime) / 1000;
  const metres = distanceMeters(from, to);
  const speedKph = metres / elapsedSeconds * 3.6;
  if (metres >= 10000 && elapsedSeconds <= 300) return {flag: true, signal: "teleporting_coordinates", severity: "RED", evidence: {distanceMeters: Math.round(metres), elapsedSeconds: Math.round(elapsedSeconds), speedKph: Math.round(speedKph)}};
  if (speedKph > 180) return {flag: true, signal: "impossible_speed", severity: "RED", evidence: {distanceMeters: Math.round(metres), elapsedSeconds: Math.round(elapsedSeconds), speedKph: Math.round(speedKph)}};
  return {flag: false, evidence: {distanceMeters: Math.round(metres), elapsedSeconds: Math.round(elapsedSeconds), speedKph: Math.round(speedKph)}};
}

async function processTimelineEvent(db, event, delivery) {
  const adjustment = adjustmentFor(event, delivery);
  const policy = flagPolicy(event);
  if (!adjustment && !policy) return {processed: false};
  const riderId = adjustment && adjustment.riderId || riderIdFor(event, delivery);
  if (!riderId) return {processed: false};
  const metricRef = db.collection("driverPerformanceMetrics").doc(riderId);
  const adjustmentRef = db.collection("riderReliabilityAdjustments").doc(clean(event.eventId));
  const flagRef = policy ? db.collection("marketplaceRiskFlags").doc(clean(event.eventId)) : null;
  return db.runTransaction(async (transaction) => {
    const [existingAdjustment, metricSnapshot] = await Promise.all([transaction.get(adjustmentRef), transaction.get(metricRef)]);
    if (existingAdjustment.exists) return {processed: false, duplicate: true};
    const metric = metricSnapshot.exists ? metricSnapshot.data() || {} : {};
    const previousScore = clampScore(metric.reliabilityScore === undefined ? BASE_SCORE : metric.reliabilityScore);
    const nextScore = clampScore(previousScore + (adjustment ? adjustment.points : 0));
    const highRiskDelta = policy && policy.severity === "RED" ? 1 : 0;
    const openHighRiskFlags = Math.max(0, Number(metric.openHighRiskFlags || 0) + highRiskDelta);
    const patch = {
      riderId,
      reliabilityScore: nextScore,
      reliabilityTrend: trend(previousScore, nextScore),
      reliabilityRiskLevel: riskLevel(nextScore, openHighRiskFlags),
      openHighRiskFlags,
      reliabilityModelVersion: MODEL_VERSION,
      reliabilityUpdatedAt: FieldValue.serverTimestamp(),
      lastReliabilityReason: adjustment ? adjustment.reason : `Review signal: ${policy.flagType}`,
    };
    if (adjustment && adjustment.counter) patch[adjustment.counter] = FieldValue.increment(1);
    transaction.set(metricRef, patch, {merge: true});
    transaction.create(adjustmentRef, {
      adjustmentId: clean(event.eventId), riderId, deliveryId: clean(event.deliveryId), eventId: clean(event.eventId), eventType: clean(event.eventType),
      points: adjustment ? adjustment.points : 0, reason: adjustment ? adjustment.reason : "Risk signal recorded", source: clean(event.source),
      timestamp: event.timestamp || FieldValue.serverTimestamp(), createdAt: FieldValue.serverTimestamp(), modelVersion: MODEL_VERSION, immutable: true,
    });
    if (flagRef) {
      transaction.create(flagRef, {
        flagId: flagRef.id, riderId, deliveryId: clean(event.deliveryId), flagType: policy.flagType, severity: policy.severity,
        status: "OPEN", evidence: event.metadata && event.metadata.evidence || event.metadata || {}, sourceEventId: clean(event.eventId),
        detectedAt: event.timestamp || FieldValue.serverTimestamp(), reviewedAt: null, reviewedBy: null, resolution: null,
        modelVersion: MODEL_VERSION, immutableDetection: true,
      });
    }
    return {processed: true, riderId, score: nextScore, flagCreated: Boolean(flagRef)};
  });
}

async function createSourceEvent(db, {deliveryId, eventType, correlationId, actorType = "system", actorId = null, source, metadata = {}}) {
  if (!deliveryId) return false;
  await appendOperationalEvent(db, {deliveryId, eventType, correlationId, actorType, actorId, source, metadata});
  return true;
}

exports.onDeliveryIntelligenceEventCreate = functions.firestore.document("deliveryRequests/{deliveryId}/timeline/{eventId}").onCreate(async (snapshot, context) => {
  const db = getFirestore();
  const deliverySnapshot = await db.collection("deliveryRequests").doc(context.params.deliveryId).get();
  if (!deliverySnapshot.exists) return null;
  await processTimelineEvent(db, snapshot.data() || {}, deliverySnapshot.data() || {});
  return null;
});

exports.onDeliveryLocationRiskWrite = functions.firestore.document("deliveryLiveLocations/{deliveryId}").onWrite(async (change, context) => {
  if (!change.after.exists) return null;
  const decision = gpsRiskDecision(change.before.exists ? change.before.data() : {}, change.after.data() || {});
  if (!decision.flag) return null;
  const db = getFirestore();
  const deliverySnapshot = await db.collection("deliveryRequests").doc(context.params.deliveryId).get();
  if (!deliverySnapshot.exists) return null;
  const delivery = deliverySnapshot.data() || {};
  const riderId = riderIdFor({actorType: "rider", actorId: (change.after.data() || {}).riderId}, delivery);
  if (!riderId) return null;
  await appendOperationalEvent(db, {
    deliveryId: context.params.deliveryId, eventType: "GPSRiskFlag", correlationId: `${context.eventId}:${decision.signal}`,
    timestamp: Timestamp.fromDate(new Date(context.timestamp)), actorType: "rider", actorId: riderId,
    source: "deliveryLiveLocations.onWrite", metadata: {signal: decision.signal, severity: decision.severity, evidence: decision.evidence},
  });
  return null;
});

exports.onDeliveryDisputeIntelligenceCreate = functions.firestore.document("disputes/{disputeId}").onCreate(async (snapshot, context) => {
  const data = snapshot.data() || {};
  return createSourceEvent(getFirestore(), {deliveryId: clean(data.deliveryId || data.bookingId || data.requestId), eventType: "DisputeCreated", correlationId: context.params.disputeId, actorType: clean(data.createdByRole || "customer"), actorId: clean(data.createdBy || data.userId), source: "disputes.onCreate", metadata: {disputeId: context.params.disputeId, category: clean(data.category || data.type)}});
});

exports.onDriverRatingIntelligenceCreate = functions.firestore.document("driverRatings/{ratingId}").onCreate(async (snapshot, context) => {
  const data = snapshot.data() || {};
  return createSourceEvent(getFirestore(), {deliveryId: clean(data.deliveryId || data.bookingId || data.requestId), eventType: "CustomerRatingReceived", correlationId: context.params.ratingId, actorType: "customer", actorId: clean(data.senderId || data.userId), source: "driverRatings.onCreate", metadata: {ratingId: context.params.ratingId, rating: Number(data.starRating || data.rating || data.score || 0)}});
});

exports.onMarketplaceRiskFlagCreate = functions.firestore.document("marketplaceRiskFlags/{flagId}").onCreate(async (snapshot, context) => {
  const flag = snapshot.data() || {};
  if (!["AMBER", "RED"].includes(clean(flag.severity, 20).toUpperCase())) return null;
  await emitNotification({recipientId: "circum-support", recipientRole: "admin", type: "marketplace_risk_review", title: `${clean(flag.severity, 20).toUpperCase()} marketplace review`, body: "A marketplace risk signal requires operational review.", data: {deliveryId: clean(flag.deliveryId), riderId: clean(flag.riderId), flagId: context.params.flagId, flagType: clean(flag.flagType), category: "system"}});
  return null;
});

exports.reviewMarketplaceRiskFlag = functions.https.onCall(async (data, context) => {
  const actorId = requireAdmin(context, "Marketplace risk review access is required.");
  const flagId = clean(data && data.flagId);
  const resolution = clean(data && data.resolution, 500);
  const status = clean(data && data.status, 30).toUpperCase();
  if (!flagId || !resolution || !["REVIEWED", "DISMISSED", "ACTION_TAKEN"].includes(status)) throw new functions.https.HttpsError("invalid-argument", "Flag, outcome, and review reason are required.");
  const db = getFirestore();
  const ref = db.collection("marketplaceRiskFlags").doc(flagId);
  const result = await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (!snapshot.exists) throw new functions.https.HttpsError("not-found", "Risk flag was not found.");
    const flag = snapshot.data() || {};
    if (flag.status !== "OPEN") return {changed: false, flag};
    let metricRef = null;
    let metricPatch = null;
    if (flag.severity === "RED" && flag.riderId) {
      metricRef = db.collection("driverPerformanceMetrics").doc(flag.riderId);
      const metricSnapshot = await transaction.get(metricRef);
      const metric = metricSnapshot.exists ? metricSnapshot.data() || {} : {};
      const openHighRiskFlags = Math.max(0, Number(metric.openHighRiskFlags || 0) - 1);
      metricPatch = {openHighRiskFlags, reliabilityRiskLevel: riskLevel(metric.reliabilityScore === undefined ? BASE_SCORE : metric.reliabilityScore, openHighRiskFlags), reliabilityUpdatedAt: FieldValue.serverTimestamp()};
    }
    transaction.set(ref, {status, reviewedAt: FieldValue.serverTimestamp(), reviewedBy: actorId, resolution}, {merge: true});
    if (metricRef) transaction.set(metricRef, metricPatch, {merge: true});
    return {changed: true, flag};
  });
  if (!result.changed) return {ok: true, flagId, status: result.flag.status, existing: true};
  const flag = result.flag;
  await appendOperationalEvent(db, {deliveryId: flag.deliveryId, eventType: "RiskFlagReviewed", correlationId: flagId, actorType: "admin", actorId, source: "adminOperations", metadata: {flagId, status, resolution}});
  if (status === "ACTION_TAKEN") {
    const confirmedType = flag.flagType === "delivery_dispute" ? "ConfirmedDeliveryDispute" : "ConfirmedOperationalIncident";
    await appendOperationalEvent(db, {deliveryId: flag.deliveryId, eventType: confirmedType, correlationId: `${flagId}:confirmed`, actorType: "admin", actorId, source: "adminOperations", metadata: {flagId, flagType: flag.flagType, resolution}});
  }
  return {ok: true, flagId, status};
});

module.exports = {BASE_SCORE, EVENT_ADJUSTMENTS, MODEL_VERSION, adjustmentFor, clampScore, coordinate, createSourceEvent, dispatchIntelligenceSignal, distanceMeters, flagPolicy, gpsRiskDecision, processTimelineEvent, riskLevel, riderIdFor, trend};
