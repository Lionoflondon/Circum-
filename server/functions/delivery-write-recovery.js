/* eslint-disable max-len, require-jsdoc */
"use strict";
const {createHash} = require("node:crypto");
const {FieldValue, Timestamp} = require("firebase-admin/firestore");
const timeline = require("./movement-timeline");
const presenceCore = require("./rider-presence-core");
const text = (v) => String(v || "").trim();
const riderId = (d = {}) => text(d.assignedRiderId || d.riderId || d.driverId || d.assignedDriverId);
const status = (d = {}) => text(d.status || d.state || d.deliveryStage).toLowerCase().replace(/[\s-]+/g, "_");
const terminal = (d) => ["delivered", "completed", "complete", "cancelled", "canceled", "cancelled_admin", "admin_removed_stale", "archived_stale", "archived_expired", "expired", "failed", "deleted"].includes(status(d));
const active = (d) => ["accepted", "assigned", "heading_to_pickup", "arrived_at_pickup", "collected", "picked_up", "in_transit", "out_for_delivery", "arrived_at_dropoff", "receiver_pin_verified", "custody_started", "custody_verified", "secure_handover"].includes(status(d));
function claimRef(db, kind, event) {
 return db.collection("eventHandlerClaims").doc(`delivery_write_${createHash("sha256").update(`${kind}:${event.eventId}`).digest("hex")}`);
}
function assertEvent(e) {
 if (!/^[A-Za-z0-9_-]{1,128}$/.test(e.deliveryId || "") || !text(e.eventId) || e.eventId.length > 128) throw Object.assign(new Error("invalid_delivery_event"), {statusCode: 400});
}
async function projectTimeline({db, event, live = false}) {
 assertEvent(event);
 const claim = claimRef(db, live ? "tracking" : "timeline", event);
 const deliveryRef = db.collection("deliveryRequests").doc(event.deliveryId);
 const locationRef = db.collection("deliveryLiveLocations").doc(event.deliveryId);
 return db.runTransaction(async (tx) => {
  const [receipt, delivery, location] = await Promise.all([tx.get(claim), tx.get(deliveryRef), tx.get(locationRef)]);
  if (receipt.exists) return {outcome: "DUPLICATE", events: 0};
  const current = delivery.data() || {};
  const events = live ? (timeline.trackingEventForChange(event.before, event.after) ? [{event: timeline.trackingEventForChange(event.before, event.after), eventKey: "tracking", deliveryType: timeline.deliveryType(current), status: status(current), actor: riderId(event.after || event.before || {}) || "system", actorType: riderId(event.after || event.before || {}) ? "rider" : "system"}] : []) : (event.after ? timeline.timelineEventsForChange(event.before, event.after) : []);
  const timestamp = Number.isFinite(Date.parse(event.time)) ? Timestamp.fromDate(new Date(event.time)) : FieldValue.serverTimestamp();
  if (delivery.exists) for (let i = 0; i < events.length; i++) tx.create(deliveryRef.collection("timeline").doc(`${claim.id}_${i}`), {...events[i], deliveryId: event.deliveryId, timestamp, createdAt: FieldValue.serverTimestamp(), sourceEventId: event.eventId});
  // Only fresh canonical state can retire tracking. A delayed terminal event
  // must never delete the new assignment's live location.
  const locationRider = riderId(location.data() || {});
  const staleLocation = location.exists && (!delivery.exists || terminal(current) || (riderId(current) && locationRider && riderId(current) !== locationRider));
  if (!live && staleLocation) tx.delete(locationRef);
  tx.create(claim, {handler: live ? "delivery_tracking" : "delivery_timeline", deliveryId: event.deliveryId, eventId: event.eventId, events: delivery.exists ? events.length : 0, clearedStaleLocation: !live && staleLocation, createdAt: FieldValue.serverTimestamp()});
  return {outcome: "APPLIED", events: delivery.exists ? events.length : 0, clearedStaleLocation: !live && staleLocation};
 });
}
async function projectPresence({db, event}) {
 assertEvent(event);
 const claim = claimRef(db, "presence", event);
 const deliveryRef = db.collection("deliveryRequests").doc(event.deliveryId);
 return db.runTransaction(async (tx) => {
  const [receipt, delivery] = await Promise.all([tx.get(claim), tx.get(deliveryRef)]);
  if (receipt.exists) return {outcome: "DUPLICATE", changed: 0};
  const current = delivery.data() || {};
  const ids = [...new Set([riderId(event.before), riderId(event.after), riderId(current)].filter(Boolean))];
  const rows = await Promise.all(ids.map(async (id) => {
   const ref = db.collection("riderPresence").doc(id);
   const [presence, rider, profile] = await Promise.all([tx.get(ref), tx.get(db.collection("riders").doc(id)), tx.get(db.collection("riderProfiles").doc(id))]);
   return {id, ref, presence, rider, profile};
  }));
  let changed = 0; let conflicts = 0;
  for (const row of rows) {
   if (!row.presence.exists) continue;
   const p = row.presence.data();
   const aliases = [text(p.activeDeliveryId), text(p.currentDeliveryId)].filter(Boolean);
   if (aliases.some((id) => id !== event.deliveryId)) {
conflicts++; continue;
}
   const assigned = delivery.exists && riderId(current) === row.id && active(current);
   const clear = aliases.includes(event.deliveryId) && (!delivery.exists || terminal(current) || riderId(current) !== row.id);
   if (!assigned && !clear) continue;
   const onlineIntent = typeof p.onlineIntent === "boolean" ? p.onlineIntent : p.isOnline === true;
   const candidate = {...p, onlineIntent, isOnline: onlineIntent, busy: assigned, activeDeliveryId: assigned ? event.deliveryId : null, currentDeliveryId: assigned ? event.deliveryId : null};
   const desired = presenceCore.computeRiderOperationalState({profile: {...row.rider.data(), ...row.profile.data()}, presence: candidate});
   const patch = presenceCore.semanticPatch(p, {...desired, busy: assigned, activeDeliveryId: candidate.activeDeliveryId, currentDeliveryId: candidate.currentDeliveryId, availabilityStatus: desired.isOnline ? assigned ? "busy" : "available" : "offline"});
   if (Object.keys(patch).length) {
    tx.set(row.ref, {...patch, riderId: row.id, source: "cloudRunDeliveryPresence", updatedAt: FieldValue.serverTimestamp()}, {merge: true}); changed++;
   }
  }
  tx.create(claim, {handler: "delivery_presence", deliveryId: event.deliveryId, eventId: event.eventId, changed, conflicts, createdAt: FieldValue.serverTimestamp()});
  return {outcome: "APPLIED", changed, conflicts};
 });
}
module.exports = {projectTimeline, projectPresence, riderId, terminal, active};
