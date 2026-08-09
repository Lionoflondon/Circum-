/* eslint-disable max-len, require-jsdoc */
"use strict";

const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue, Timestamp} = require("firebase-admin/firestore");
const {requireAdmin} = require("./admin-auth");
const {emitNotification} = require("./communication-engine");
const {appendOperationalEvent} = require("./delivery-operational-events");
const {WATCHDOG_THRESHOLDS_MINUTES} = require("./movement-timeline");

const MOVEMENT_METERS = 100;
const BATCH_LIMIT = 100;
const INCIDENTS = Object.freeze({
  accepted_no_movement: {severity: "AMBER", message: "Delivery was accepted but the Rider has not moved for 15 minutes."},
  arrived_not_collected: {severity: "AMBER", message: "Delivery is waiting at pickup beyond the expected collection window."},
  collected_no_movement: {severity: "RED", message: "Delivery was collected but movement has not resumed."},
  dropoff_completion_delay: {severity: "RED", message: "Rider arrived at drop-off but completion is delayed."},
  payment_dispatch_failure: {severity: "RED", message: "Payment is confirmed but the delivery has not entered Rider dispatch."},
});

function number(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function locationOf(value = {}) {
  const source = value.riderLiveLocation || value.currentLocation || value.position || value;
  const point = source.geopoint || source.geoPoint || source;
  const latitude = number(point.latitude !== undefined ? point.latitude : point._latitude);
  const longitude = number(point.longitude !== undefined ? point.longitude : point._longitude);
  if (latitude === null || longitude === null || Math.abs(latitude) > 90 || Math.abs(longitude) > 180) return null;
  return {latitude, longitude};
}

function distanceMeters(a, b) {
  if (!a || !b) return 0;
  const radians = (degrees) => degrees * Math.PI / 180;
  const dLat = radians(b.latitude - a.latitude);
  const dLng = radians(b.longitude - a.longitude);
  const x = Math.sin(dLat / 2) ** 2 + Math.cos(radians(a.latitude)) *
    Math.cos(radians(b.latitude)) * Math.sin(dLng / 2) ** 2;
  return 6371000 * 2 * Math.atan2(Math.sqrt(x), Math.sqrt(1 - x));
}

function incidentId(deliveryId, incidentType) {
  return `${deliveryId}_${incidentType}`.replace(/[^A-Za-z0-9_-]/g, "_").slice(0, 500);
}

function evaluation(projection, tracking) {
  const type = `${projection.incidentType || ""}`;
  if (!INCIDENTS[type]) return {action: "none"};
  if (["arrived_not_collected", "dropoff_completion_delay", "payment_dispatch_failure"].includes(type)) {
    return {action: "incident", incidentType: type};
  }
  const current = locationOf(tracking || {});
  const baseline = locationOf(projection.baselineLocation || {});
  if (!current) return {action: "incident", incidentType: type, reason: "location_unavailable"};
  if (!baseline) return {action: "baseline", location: current};
  const movement = distanceMeters(baseline, current);
  return movement >= MOVEMENT_METERS ?
    {action: "movement", location: current, movementMeters: movement} :
    {action: "incident", incidentType: type, movementMeters: movement};
}

function nextCheck(type, now = Timestamp.now()) {
  return Timestamp.fromMillis(now.toMillis() + (WATCHDOG_THRESHOLDS_MINUTES[type] || 15) * 60000);
}

async function resolveIncident(db, deliveryId, type, reason, actorId = "delivery-watchdog") {
  if (!type) return false;
  const ref = db.collection("operationalIncidents").doc(incidentId(deliveryId, type));
  const snapshot = await ref.get();
  if (!snapshot.exists || snapshot.data().status === "RESOLVED") return false;
  await ref.set({status: "RESOLVED", resolvedAt: FieldValue.serverTimestamp(), resolvedBy: actorId, resolutionReason: reason, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
  await appendOperationalEvent(db, {deliveryId, eventType: "IncidentResolved", correlationId: ref.id, actorType: actorId === "delivery-watchdog" ? "system" : "admin", actorId, source: "deliveryWatchdog", metadata: {incidentId: ref.id, incidentType: type, reason}});
  return true;
}

async function createIncident(db, delivery, projection, tracking) {
  const type = projection.incidentType;
  const policy = INCIDENTS[type];
  const deliveryId = projection.deliveryId;
  const ref = db.collection("operationalIncidents").doc(incidentId(deliveryId, type));
  const existing = await ref.get();
  if (existing.exists && existing.data().status !== "RESOLVED") return {created: false, id: ref.id};
  const location = locationOf(tracking || {});
  const record = {
    incidentId: ref.id,
    deliveryId,
    incidentType: type,
    severity: policy.severity,
    status: "OPEN",
    detectedAt: FieldValue.serverTimestamp(),
    currentDeliveryState: delivery.status || projection.status || null,
    assignedRider: projection.assignedRiderId || null,
    lastKnownLocation: location,
    lastHeartbeat: tracking && (tracking.updatedAt || tracking.lastBackendUploadAt) || null,
    resolvedAt: null,
    resolvedBy: null,
    resolutionReason: null,
    source: "deliveryWatchdog",
    immutableDetection: true,
    updatedAt: FieldValue.serverTimestamp(),
  };
  if (existing.exists) {
    await ref.set({...record, recurrenceCount: FieldValue.increment(1)}, {merge: true});
  } else {
    await ref.create({...record, recurrenceCount: 1}).catch((error) => {
      if (!(error && (error.code === 6 || error.code === "already-exists"))) throw error;
    });
  }
  await appendOperationalEvent(db, {deliveryId, eventType: "IncidentCreated", correlationId: ref.id, source: "deliveryWatchdog", metadata: {incidentId: ref.id, incidentType: type, severity: policy.severity}});
  await emitNotification({recipientId: "circum-support", recipientRole: "admin", type: "operational_incident", title: `${policy.severity} delivery incident`, body: policy.message, data: {deliveryId, incidentId: ref.id, incidentType: type, correlationId: ref.id, category: "system"}});
  return {created: true, id: ref.id};
}

async function runDeliveryWatchdog(db = getFirestore(), now = Timestamp.now()) {
  const due = await db.collection("deliveryOperationalState")
      .where("active", "==", true).where("nextCheckAt", "<=", now)
      .orderBy("nextCheckAt").limit(BATCH_LIMIT).get();
  let incidentsCreated = 0;
  let evaluated = 0;
  for (const projectionDoc of due.docs) {
    const projection = projectionDoc.data() || {};
    const deliveryRef = db.collection("deliveryRequests").doc(projection.deliveryId || projectionDoc.id);
    const [deliveryDoc, trackingDoc] = await Promise.all([
      deliveryRef.get(), deliveryRef.collection("tracking").doc("liveLocation").get(),
    ]);
    if (!deliveryDoc.exists) {
      await projectionDoc.ref.set({active: false, nextCheckAt: null, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
      continue;
    }
    evaluated += 1;
    const result = evaluation(projection, trackingDoc.exists ? trackingDoc.data() : {});
    if (result.action === "incident") {
      const created = await createIncident(db, deliveryDoc.data() || {}, projection, trackingDoc.exists ? trackingDoc.data() : {});
      if (created.created) incidentsCreated += 1;
      await projectionDoc.ref.set({openIncidentId: created.id}, {merge: true});
    } else if (result.action === "movement") {
      await resolveIncident(db, projectionDoc.id, projection.incidentType, "meaningful_movement_resumed");
    }
    const patch = {lastEvaluatedAt: FieldValue.serverTimestamp(), nextCheckAt: nextCheck(projection.incidentType, now)};
    if (result.location) patch.baselineLocation = result.location;
    await projectionDoc.ref.set(patch, {merge: true});
  }
  return {evaluated, incidentsCreated, remainingMayExist: due.size === BATCH_LIMIT};
}

exports.deliveryLifecycleWatchdog = functions.pubsub.schedule("every 5 minutes").timeZone("Europe/London").onRun(() => runDeliveryWatchdog());

exports.acknowledgeOperationalIncident = functions.https.onCall(async (data, context) => {
  const actorId = requireAdmin(context, "Operations access is required.");
  const incidentIdValue = `${data && data.incidentId || ""}`.trim();
  if (!incidentIdValue) throw new functions.https.HttpsError("invalid-argument", "Incident is required.");
  const db = getFirestore();
  const ref = db.collection("operationalIncidents").doc(incidentIdValue);
  const snapshot = await ref.get();
  if (!snapshot.exists) throw new functions.https.HttpsError("not-found", "Incident not found.");
  const incident = snapshot.data() || {};
  await ref.set({status: "ACKNOWLEDGED", acknowledgedAt: FieldValue.serverTimestamp(), acknowledgedBy: actorId, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
  await appendOperationalEvent(db, {deliveryId: incident.deliveryId, eventType: "IncidentAcknowledged", correlationId: ref.id, actorType: "admin", actorId, source: "adminOperations", metadata: {incidentId: ref.id, incidentType: incident.incidentType}});
  return {ok: true, incidentId: ref.id};
});

exports.resolveOperationalIncident = functions.https.onCall(async (data, context) => {
  const actorId = requireAdmin(context, "Operations access is required.");
  const incidentIdValue = `${data && data.incidentId || ""}`.trim();
  const reason = `${data && data.reason || ""}`.trim().slice(0, 500);
  if (!incidentIdValue || !reason) throw new functions.https.HttpsError("invalid-argument", "Incident and resolution reason are required.");
  const db = getFirestore();
  const snapshot = await db.collection("operationalIncidents").doc(incidentIdValue).get();
  if (!snapshot.exists) throw new functions.https.HttpsError("not-found", "Incident not found.");
  await resolveIncident(db, snapshot.data().deliveryId, snapshot.data().incidentType, reason, actorId);
  return {ok: true, incidentId: incidentIdValue};
});

module.exports.BATCH_LIMIT = BATCH_LIMIT;
module.exports.INCIDENTS = INCIDENTS;
module.exports.MOVEMENT_METERS = MOVEMENT_METERS;
module.exports.distanceMeters = distanceMeters;
module.exports.evaluation = evaluation;
module.exports.incidentId = incidentId;
module.exports.locationOf = locationOf;
module.exports.runDeliveryWatchdog = runDeliveryWatchdog;
