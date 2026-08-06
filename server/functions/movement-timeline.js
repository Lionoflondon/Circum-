/* eslint-disable max-len, require-jsdoc */
"use strict";

const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");

function normalized(value) {
  return `${value || ""}`.trim().toLowerCase().replace(/[\s-]+/g, "_");
}

function deliveryType(data = {}) {
  const source = normalized(data.sourceModule);
  if (source === "gifts" || source === "gift" || data.giftOrderId) return "GIFTS";
  if (["health", "healthplus", "health_plus"].includes(source) || data.healthPlusOrderId) return "HEALTH_PLUS";
  if (source === "business") return "BUSINESS";
  const explicit = normalized(data.serviceType).toUpperCase();
  if (["STANDARD", "SCHEDULED", "HEAVY_DUTY", "BUSINESS", "VANGUARD", "GIFTS", "HEALTH_PLUS"].includes(explicit)) return explicit;
  if (data.vanguardEnabled === true) return "VANGUARD";
  return "STANDARD";
}

const CORE_EVENTS = Object.freeze({
  created: "Created",
  assigned: "Assigned",
  accepted: "Accepted",
  navigating_to_pickup: "Rider En Route to Pickup",
  en_route_to_pickup: "Rider En Route to Pickup",
  arrived_at_pickup: "Rider Arrived at Pickup",
  rider_arrived_pickup: "Rider Arrived at Pickup",
  collected: "Collected",
  picked_up: "Collected",
  navigating_to_dropoff: "In Transit",
  in_transit: "In Transit",
  out_for_delivery: "In Transit",
  arrived_at_dropoff: "Rider Arrived at Drop-off",
  delivered: "Delivered",
  completed: "Completed",
  complete: "Completed",
});

const GIFT_EVENTS = Object.freeze({
  approved: "Gift Approved",
  gift_approved: "Gift Approved",
  purchased: "Gift Purchased",
  gift_purchased: "Gift Purchased",
  packed: "Gift Packed",
  gift_packed: "Gift Packed",
  assigned: "Rider Assigned",
  rider_assigned: "Rider Assigned",
  out_for_delivery: "Out For Delivery",
  in_transit: "Out For Delivery",
  delivered: "Delivered",
  story_prepared: "Story Prepared",
  story_released: "Story Released",
});

const HEALTH_EVENTS = Object.freeze({
  scheduled: "Prescription Scheduled",
  prescription_scheduled: "Prescription Scheduled",
  reminder_sent: "Reminder Sent",
  assigned: "Rider Assigned",
  rider_assigned: "Rider Assigned",
  collected: "Prescription Collected",
  prescription_collected: "Prescription Collected",
  in_transit: "In Transit",
  delivered: "Delivered",
  completed: "Completed",
});

const VANGUARD_EVENTS = Object.freeze({
  custody_started: "Custody Started",
  custody_verified: "Custody Verified",
  secure_handover: "Secure Handover",
  vanguard_complete: "Vanguard Complete",
});

function eventName(type, status) {
  const key = normalized(status);
  if (type === "GIFTS" && GIFT_EVENTS[key]) return GIFT_EVENTS[key];
  if (type === "HEALTH_PLUS" && HEALTH_EVENTS[key]) return HEALTH_EVENTS[key];
  if (type === "VANGUARD" && VANGUARD_EVENTS[key]) return VANGUARD_EVENTS[key];
  return CORE_EVENTS[key] || null;
}

function actor(data = {}) {
  return {
    actor: data.updatedBy || data.actorName || data.actorId || "system",
    actorType: normalized(data.actorType || data.updatedByRole || "system"),
    actorId: data.actorId || data.updatedById || null,
    actorName: data.actorName || data.updatedByName || null,
  };
}

function timelineEventsForChange(before, after) {
  const previous = before || {};
  const current = after || {};
  const type = deliveryType(current);
  const events = [];
  const seen = new Set();
  const add = (status, explicitName) => {
    const key = normalized(status);
    const name = explicitName || eventName(type, key);
    if (!name || seen.has(name)) return;
    seen.add(name);
    events.push({eventKey: key || normalized(name), event: name, status: key});
  };

  if (!before) add("created", "Created");

  const previousRider = previous.assignedRiderId || previous.riderId || null;
  const currentRider = current.assignedRiderId || current.riderId || null;
  if (currentRider && currentRider !== previousRider) {
    add("assigned", type === "GIFTS" || type === "HEALTH_PLUS" ? "Rider Assigned" : "Assigned");
  }

  const previousSourceStatus = normalized(previous.sourceStatus);
  const currentSourceStatus = normalized(current.sourceStatus);
  if (currentSourceStatus && currentSourceStatus !== previousSourceStatus) {
    add(currentSourceStatus);
  }

  const previousStatus = normalized(previous.status);
  const currentStatus = normalized(current.status);
  if (currentStatus && currentStatus !== previousStatus) add(currentStatus);

  const previousVanguardEvent = normalized(previous.vanguardTimelineEvent);
  const currentVanguardEvent = normalized(current.vanguardTimelineEvent);
  if (currentVanguardEvent && currentVanguardEvent !== previousVanguardEvent) {
    add(currentVanguardEvent, VANGUARD_EVENTS[currentVanguardEvent]);
  }

  return events.map((event) => ({
    ...event,
    deliveryType: type,
    notes: current.timelineNote || current.statusNote || null,
    ...actor(current),
  }));
}

function assignedRiderId(data = {}) {
  return data.assignedRiderId || data.riderId || data.driverId || data.assignedDriverId || null;
}

function terminalStatus(value) {
  return ["completed", "delivered", "cancelled", "canceled", "failed", "deleted"].includes(normalized(value));
}

function trackingEventForChange(before, after) {
  const previousStatus = normalized(before && before.trackingStatus);
  if (!after) return previousStatus === "active" ? "Rider live tracking stopped" : null;
  const currentStatus = normalized(after.trackingStatus);
  if (currentStatus === "active" && previousStatus !== "active") {
    return "Rider live tracking started";
  }
  if (["stopped", "offline", "permission_lost", "switching"].includes(currentStatus) && currentStatus !== previousStatus) {
    return "Rider live tracking stopped";
  }
  return null;
}

exports.onMovementTimelineWrite = functions.firestore
    .document("deliveryRequests/{deliveryId}")
    .onWrite(async (change, context) => {
      if (!change.after.exists) return null;
      const before = change.before.exists ? change.before.data() : null;
      const after = change.after.data() || {};
      const events = timelineEventsForChange(before, after);
      const db = getFirestore();
      const eventId = `${context.eventId || context.timestamp}`.replace(/[^a-zA-Z0-9_-]/g, "_");
      const batch = db.batch();
      events.forEach((event, index) => {
        const ref = db.collection("deliveryRequests")
            .doc(context.params.deliveryId)
            .collection("timeline")
            .doc(`${eventId}_${index}`);
        batch.set(ref, {
          ...event,
          deliveryId: context.params.deliveryId,
          timestamp: FieldValue.serverTimestamp(),
          createdAt: FieldValue.serverTimestamp(),
        });
      });
      const reassigned = before && assignedRiderId(before) &&
        assignedRiderId(before) !== assignedRiderId(after);
      if (terminalStatus(after.status) || reassigned) {
        batch.delete(db.collection("deliveryLiveLocations").doc(context.params.deliveryId));
      }
      if (events.length === 0 && !terminalStatus(after.status) && !reassigned) return null;
      await batch.commit();
      return null;
    });

exports.onDeliveryLiveLocationWrite = functions.firestore
    .document("deliveryLiveLocations/{deliveryId}")
    .onWrite(async (change, context) => {
      const before = change.before.exists ? change.before.data() : null;
      const after = change.after.exists ? change.after.data() : null;
      const event = trackingEventForChange(before, after);
      if (!event) return null;
      const db = getFirestore();
      const delivery = await db.collection("deliveryRequests")
          .doc(context.params.deliveryId).get();
      if (!delivery.exists) return null;
      const data = delivery.data() || {};
      const eventId = `${context.eventId || context.timestamp}`.replace(/[^a-zA-Z0-9_-]/g, "_");
      await delivery.ref.collection("timeline").doc(`tracking_${eventId}`).set({
        eventKey: normalized(event),
        event,
        status: normalized(data.status),
        deliveryType: deliveryType(data),
        actor: (after || before || {}).riderId || "system",
        actorType: (after || before || {}).riderId ? "rider" : "system",
        actorId: (after || before || {}).riderId || null,
        actorName: null,
        notes: null,
        deliveryId: context.params.deliveryId,
        timestamp: FieldValue.serverTimestamp(),
        createdAt: FieldValue.serverTimestamp(),
      });
      return null;
    });

module.exports.deliveryType = deliveryType;
module.exports.eventName = eventName;
module.exports.timelineEventsForChange = timelineEventsForChange;
module.exports.trackingEventForChange = trackingEventForChange;
module.exports.terminalStatus = terminalStatus;
