/* eslint-disable max-len, require-jsdoc */
"use strict";
const {FieldValue, FieldPath, Timestamp} = require("firebase-admin/firestore");
const {createHash} = require("node:crypto");
const scheduled = require("./scheduled-delivery-core");
const {watchdogCondition, INCIDENT_MESSAGES} = require("./delivery-watchdog-policy");
const presenceCore = require("./rider-presence-core");
const {notificationInput, queueNotifications} = require("./delivery-maintenance-notifications");
const {eventRecord} = require("./delivery-operational-events");
const {dispatchDeliveryRequest} = require("./send-package");
const {canGoOnline} = presenceCore;
const text = (x) => `${x || ""}`.trim();
const normalized = (x) => text(x).toLowerCase().replace(/[\s-]+/g, "_");
const millis = scheduled.millis;
const OPEN = ["requested", "pending", "broadcast", "broadcasted", "awaiting_rider", "finding_rider"];
const THRESHOLDS = Object.freeze({accepted_no_movement: 15, arrived_not_collected: 15, collected_no_movement: 10, dropoff_completion_delay: 10, payment_dispatch_failure: 10});
const WATCHED = [...OPEN, "searching", "matching", "available", "accepted", "assigned", "navigating_to_pickup", "arrived_at_pickup", "waiting_at_pickup", "waiting", "collected", "picked_up", "navigating_to_dropoff", "in_transit", "arrived_at_dropoff", "verification_started"];
function digest(x) {
 return createHash("sha256").update(x).digest("hex");
}
async function page(db, worker, collection, field, values, limit) {
 const state = db.collection("operationsState").doc(`delivery_maintenance_cursor_${worker}`);
 const saved = (await state.get()).data() || {};
 let query = db.collection(collection);
 if (field) query = query.where(field, Array.isArray(values) ? "in" : "==", values);
 query = query.orderBy(FieldPath.documentId()).limit(limit);
 let result = await (saved.cursor ? query.startAfter(saved.cursor) : query).get();
 if (result.empty && saved.cursor) result = await query.get();
 return {docs: result.docs, save: () => state.set({cursor: result.size === limit ? result.docs[result.size - 1].id : null, updatedAt: FieldValue.serverTimestamp()}, {merge: true})};
}
async function activateOne(db, id, now) {
 const ref = db.collection("deliveryRequests").doc(id);
 return db.runTransaction(async (tx) => {
  const snap = await tx.get(ref); if (!snap.exists) return {activated: false};
  const delivery = snap.data(); if (normalized(delivery.status || delivery.deliveryStatus) !== "scheduled") return {activated: false};
  const plan = scheduled.activationPlan(delivery, now); if (!plan.activate) return {activated: false};
  const riderId = scheduled.assignedRiderId(delivery);
  let presence;
  if (plan.mode === "assigned") {
   const [p, profile] = await Promise.all([tx.get(db.collection("riderPresence").doc(riderId)), tx.get(db.collection("riderProfiles").doc(riderId))]);
   presence = p.data() || {};
   if (!profile.exists || !canGoOnline(profile.data() || {}) || presence.busy === true || text(presence.activeDeliveryId || presence.currentDeliveryId)) return {activated: false, blocked: true};
  }
  if (plan.mode === "open_dispatch") tx.set(db.collection("deliveryMaintenanceJobs").doc(digest(`activation:${id}`)), {deliveryId: id, kind: "scheduled_dispatch", state: "pending", createdAt: FieldValue.serverTimestamp()}, {merge: true});
  tx.set(ref, {status: plan.status, deliveryStatus: plan.status, deliveryStage: plan.status, dispatchStatus: plan.mode === "assigned" ? "assigned" : "requested", matchingStatus: plan.mode === "assigned" ? "assigned" : "available", scheduleActivatedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()}, {merge: true});
  if (presence) {
   tx.set(db.collection("riderPresence").doc(riderId), {riderId, busy: true, availabilityStatus: "busy", dispatchEligible: false, activeDeliveryId: id, currentDeliveryId: id, updatedAt: FieldValue.serverTimestamp(), source: "scheduledDeliveryActivation"}, {merge: true});
   for (const name of ["riders", "riderProfiles"]) tx.set(db.collection(name).doc(riderId), {activeDelivery: id, activeDeliveryId: id, currentDeliveryId: id, availabilityStatus: "busy", isOnline: presence.isOnline === true, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
  }
  return {activated: true, mode: plan.mode};
 });
}
async function activation({db, now, limit}) {
 const p = await page(db, "activation", "deliveryRequests", "status", "scheduled", limit);
 const result = {scanned: p.docs.length, activated: 0, dispatchRecovered: 0, blocked: 0};
 for (const doc of p.docs) {
const r = await activateOne(db, doc.id, now); if (r.activated) result.activated++; if (r.blocked) result.blocked++;
}
 await p.save();
 const jobs = await db.collection("deliveryMaintenanceJobs").where("state", "==", "pending").limit(limit).get();
 for (const job of jobs.docs) {
  const id = job.data().deliveryId; const ref = db.collection("deliveryRequests").doc(id); const current = await ref.get();
  const row = current.data() || {};
  if (current.exists && OPEN.includes(normalized(row.status)) && !scheduled.assignedRiderId(row)) {
   await dispatchDeliveryRequest({db, requestId: row.requestId || id, uid: row.senderId || row.userId || row.customerId, source: "activateDueScheduledDeliveries", durableOnly: true});
  }
  await job.ref.set({state: "completed", completedAt: FieldValue.serverTimestamp()}, {merge: true}); result.dispatchRecovered++;
 }
 return result;
}
async function escalation({db, now, limit}) {
 const platform = require("./platform-notifications")._private;
 const p = await page(db, "escalation", "deliveryRequests", "status", OPEN, limit);
 const result = {scanned: p.docs.length, escalated: 0};
 let candidates = null;
 for (const doc of p.docs) {
  const initial = doc.data(); const stage = platform.escalationStage(initial, now);
  if (!stage || Number(initial.notificationEscalationStage || 0) >= stage) continue;
  if (stage !== 5 && !candidates) candidates = await platform.onlineCandidateRiderRecords(db);
  const changed = await db.runTransaction(async (tx) => {
   const fresh = await tx.get(doc.ref); if (!fresh.exists) return false; const d = fresh.data();
   const currentStage = platform.escalationStage(d, now);
   if (currentStage !== stage || !OPEN.includes(normalized(d.status)) || scheduled.assignedRiderId(d) || !currentStage || Number(d.notificationEscalationStage || 0) >= currentStage) return false;
   const inputs = [];
   if (currentStage === 5) inputs.push(notificationInput({key: `delivery_escalation:${doc.id}:5:admin`, recipientRole: "admin", type: "unclaimed_delivery", title: "Unclaimed delivery", body: "A delivery remains unclaimed after five minutes.", deliveryId: doc.id}));
   else {
    for (const candidate of candidates || []) {
     const [profile, rider, presence] = await Promise.all([tx.get(db.collection("riderProfiles").doc(candidate.id)), tx.get(db.collection("riders").doc(candidate.id)), tx.get(db.collection("riderPresence").doc(candidate.id))]);
     if (platform.dispatchCandidateDecision({profile: profile.data() || {}, rider: rider.data() || {}, presence: presence.data() || {}}, d, now).eligible) inputs.push(notificationInput({key: `delivery_escalation:${doc.id}:${currentStage}:${candidate.id}`, recipientId: candidate.id, recipientRole: "rider", type: "delivery_reminder", title: "Delivery still available", body: "An eligible delivery is still waiting for a rider.", deliveryId: doc.id}));
    }
   }
   await queueNotifications(tx, db, inputs);
   tx.set(doc.ref, {notificationEscalationStage: currentStage, notificationEscalatedAt: FieldValue.serverTimestamp()}, {merge: true});
   return true;
  }); if (changed) result.escalated++;
 }
 await p.save(); return result;
}
function locationOf(value = {}) {
 const source = value.riderLiveLocation || value.currentLocation || value.position || value; const p = source.geopoint || source.geoPoint || source;
 const latitude = Number(p.latitude ?? p._latitude); const longitude = Number(p.longitude ?? p._longitude);
 return Number.isFinite(latitude) && Number.isFinite(longitude) && Math.abs(latitude) <= 90 && Math.abs(longitude) <= 180 ? {latitude, longitude} : null;
}
function distanceMeters(a, b) {
 if (!a || !b) return 0; const rad = (x) => x * Math.PI / 180; const h = Math.sin(rad(b.latitude - a.latitude) / 2) ** 2 + Math.cos(rad(a.latitude)) * Math.cos(rad(b.latitude)) * Math.sin(rad(b.longitude - a.longitude) / 2) ** 2;
 return 6371000 * 2 * Math.atan2(Math.sqrt(h), Math.sqrt(1 - h));
}
async function watchdogOne(db, id, now) {
 const ref = db.collection("deliveryRequests").doc(id); const projectionRef = db.collection("deliveryOperationalState").doc(id);
 return db.runTransaction(async (tx) => {
  const [snap, projectionSnap, trackingSnap] = await Promise.all([tx.get(ref), tx.get(projectionRef), tx.get(ref.collection("tracking").doc("liveLocation"))]);
  const d = snap.data() || {}; const previous = projectionSnap.data() || {}; const type = snap.exists ? watchdogCondition(d) : null;
  const oldIncidentRef = previous.openIncidentId ? db.collection("operationalIncidents").doc(previous.openIncidentId) : null;
  const oldIncident = oldIncidentRef ? await tx.get(oldIncidentRef) : null;
  if (!type) {
   if (oldIncident?.exists && !["RESOLVED"].includes(oldIncident.data().status)) {
    tx.set(oldIncidentRef, {status: "RESOLVED", resolvedAt: FieldValue.serverTimestamp(), resolvedBy: "delivery-watchdog", resolutionReason: "delivery_state_progressed", updatedAt: FieldValue.serverTimestamp()}, {merge: true});
    const event = eventRecord({deliveryId: id, eventType: "IncidentResolved", correlationId: `${oldIncidentRef.id}:${oldIncident.data().recurrenceCount || 1}:progressed`}); tx.create(ref.collection("timeline").doc(event.eventId), event);
   }
   if (projectionSnap.exists) tx.set(projectionRef, {active: false, nextCheckAt: null, openIncidentId: null, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
   return {created: false};
  }
  const same = previous.incidentType === type && previous.status === normalized(d.status) && text(previous.assignedRiderId) === scheduled.assignedRiderId(d);
  const stateTimes = {accepted_no_movement: d.acceptedAt || d.assignedAt || d.riderAssignedAt, arrived_not_collected: d.pickupArrivedAt || d.arrivedAtPickupAt || d.waiting?.startedAt, collected_no_movement: d.collectedAt || d.pickedUpAt || d.collectionVerifiedAt, dropoff_completion_delay: d.dropoffArrivedAt || d.arrivedAtDropoffAt, payment_dispatch_failure: d.paymentConfirmedAt || d.paidAt};
  const enteredAt = same && millis(previous.stateEnteredAt) || (!projectionSnap.exists && millis(stateTimes[type])) || now;
  const dueAt = same && millis(previous.nextCheckAt) || enteredAt + THRESHOLDS[type] * 60000;
  const tracking = trackingSnap.data() || {}; const currentLocation = locationOf(tracking); const baseline = same ? locationOf(previous.baselineLocation || {}) : currentLocation;
  const patch = {deliveryId: id, active: true, status: normalized(d.status), incidentType: type, assignedRiderId: scheduled.assignedRiderId(d), stateEnteredAt: Timestamp.fromMillis(enteredAt), nextCheckAt: Timestamp.fromMillis(dueAt), updatedAt: FieldValue.serverTimestamp(), projectionVersion: "cloud-run-recovery-v1"};
  if (dueAt > now || (["accepted_no_movement", "collected_no_movement"].includes(type) && currentLocation && !previous.baselineLocation)) {
   if (!same && oldIncident?.exists && oldIncident.data().status !== "RESOLVED") {
    tx.set(oldIncidentRef, {status: "RESOLVED", resolvedAt: FieldValue.serverTimestamp(), resolvedBy: "delivery-watchdog", resolutionReason: "delivery_state_progressed"}, {merge: true});
    const event = eventRecord({deliveryId: id, eventType: "IncidentResolved", correlationId: `${oldIncidentRef.id}:${oldIncident.data().recurrenceCount || 1}:progressed`}); tx.create(ref.collection("timeline").doc(event.eventId), event);
    patch.openIncidentId = null;
   }
   if (dueAt <= now) patch.nextCheckAt = Timestamp.fromMillis(now + THRESHOLDS[type] * 60000);
if (currentLocation && (!same || !previous.baselineLocation)) patch.baselineLocation = currentLocation; tx.set(projectionRef, patch, {merge: true}); return {created: false};
}
  const moved = ["accepted_no_movement", "collected_no_movement"].includes(type) && baseline && currentLocation && distanceMeters(baseline, currentLocation) >= 100;
  const incidentRef = db.collection("operationalIncidents").doc(`${id}_${type}`.replace(/[^A-Za-z0-9_-]/g, "_").slice(0, 500));
  const incident = await tx.get(incidentRef);
  let created = false;
  if (moved) {
   if (incident.exists && incident.data().status !== "RESOLVED") {
    tx.set(incidentRef, {status: "RESOLVED", resolvedAt: FieldValue.serverTimestamp(), resolvedBy: "delivery-watchdog", resolutionReason: "meaningful_movement_resumed"}, {merge: true});
    const event = eventRecord({deliveryId: id, eventType: "IncidentResolved", correlationId: `${incidentRef.id}:${incident.data().recurrenceCount || 1}:movement`}); tx.create(ref.collection("timeline").doc(event.eventId), event);
   }
   patch.openIncidentId = null;
  } else if (!incident.exists || incident.data().status === "RESOLVED") {
   const recurrence = Number(incident.data()?.recurrenceCount || 0) + 1;
   const inputs = [notificationInput({key: `watchdog:${incidentRef.id}:${recurrence}`, recipientRole: "admin", type: "operational_incident", title: `${["accepted_no_movement", "arrived_not_collected"].includes(type) ? "AMBER" : "RED"} delivery incident`, body: INCIDENT_MESSAGES[type], deliveryId: id, data: {incidentId: incidentRef.id, incidentType: type}})];
   await queueNotifications(tx, db, inputs);
   tx.set(incidentRef, {incidentId: incidentRef.id, deliveryId: id, incidentType: type, severity: ["accepted_no_movement", "arrived_not_collected"].includes(type) ? "AMBER" : "RED", status: "OPEN", detectedAt: FieldValue.serverTimestamp(), currentDeliveryState: d.status, assignedRider: scheduled.assignedRiderId(d) || null, lastKnownLocation: currentLocation, lastHeartbeat: tracking.updatedAt || tracking.lastBackendUploadAt || null, resolvedAt: null, resolvedBy: null, resolutionReason: null, source: "deliveryWatchdog", immutableDetection: true, recurrenceCount: recurrence, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
   const event = eventRecord({deliveryId: id, eventType: "IncidentCreated", correlationId: `${incidentRef.id}:${recurrence}`, source: "deliveryWatchdog", metadata: {incidentId: incidentRef.id, incidentType: type}}); tx.create(ref.collection("timeline").doc(event.eventId), event);
   patch.openIncidentId = incidentRef.id; created = true;
  } else patch.openIncidentId = incidentRef.id;
  if (currentLocation) patch.baselineLocation = currentLocation;
  patch.nextCheckAt = Timestamp.fromMillis(now + THRESHOLDS[type] * 60000); patch.lastEvaluatedAt = FieldValue.serverTimestamp();
  tx.set(projectionRef, patch, {merge: true}); return {created};
 });
}
async function watchdog({db, now, limit}) {
 let scanned = 0; let incidentsCreated = 0;
 for (let i = 0; i < WATCHED.length; i += 10) {
  const p = await page(db, `watchdog_${i}`, "deliveryRequests", "status", WATCHED.slice(i, i + 10), limit);
  for (const doc of p.docs) {
const r = await watchdogOne(db, doc.id, now); scanned++; if (r.created) incidentsCreated++;
} await p.save();
 }
 // Existing projections can require terminal-state resolution even after a delivery leaves the watched query.
 const existing = await page(db, "watchdog_projections", "deliveryOperationalState", "active", true, limit);
 for (const doc of existing.docs) await watchdogOne(db, doc.id, now);
 await existing.save();
 return {scanned, incidentsCreated};
}
async function stalePresence({db, now, limit}) {
 const docs = await db.collection("riderPresence").where("isOnline", "==", true).where("lastHeartbeatAt", "<", now - presenceCore.STALE_HEARTBEAT_MS).limit(limit).get(); let markedStale = 0;
 for (const doc of docs.docs) {
  const changed = await db.runTransaction(async (tx) => {
   const [fresh, profile] = await Promise.all([tx.get(doc.ref), tx.get(db.collection("riderProfiles").doc(doc.id))]); const row = fresh.data() || {};
   if (!fresh.exists || row.isOnline !== true || millis(row.lastHeartbeatAt) >= now - presenceCore.STALE_HEARTBEAT_MS || row.presenceFreshness === "stale") return false;
   const patch = {presenceState: presenceCore.PRESENCE_STATES.STALE, presenceFreshness: "stale", connectionStatus: "stale", dispatchEligible: false, staleAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(), source: "staleHeartbeat"};
   tx.set(doc.ref, patch, {merge: true}); if (profile.exists) tx.set(profile.ref, patch, {merge: true}); return true;
  }); if (changed) markedStale++;
 }
 return {scanned: docs.size, markedStale};
}
const WORKERS = {activateDueScheduledDeliveries: activation, escalateUnclaimedDeliveries: escalation, deliveryLifecycleWatchdog: watchdog, markStaleRiderPresenceOffline: stalePresence};
async function runWorker({worker, db, now = Date.now(), limit = 20}) {
 if (!WORKERS[worker]) throw new Error("unsupported_worker");
 return WORKERS[worker]({db, now, limit: Math.max(1, Math.min(200, limit))});
}
module.exports = {runWorker, WORKERS, activateOne, escalation, watchdogOne, watchdogCondition, stalePresence, queueNotifications, notificationInput, THRESHOLDS, locationOf, distanceMeters};
