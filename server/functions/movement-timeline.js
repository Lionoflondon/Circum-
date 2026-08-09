/* eslint-disable max-len, require-jsdoc */
"use strict";

const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue, Timestamp} = require("firebase-admin/firestore");
const {appendOperationalEvent} = require("./delivery-operational-events");

const WATCHDOG_THRESHOLDS_MINUTES = Object.freeze({
  accepted_no_movement: 15,
  arrived_not_collected: 15,
  collected_no_movement: 10,
  dropoff_completion_delay: 10,
  payment_dispatch_failure: 10,
});

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
  arrived_at_pickup: "Arrived At Pickup",
  waiting: "Waiting Started",
  waiting_at_pickup: "Waiting Started",
  customer_responded: "Customer Responded",
  collected: "Collected",
  picked_up: "Collected",
  in_transit: "In Transit",
  navigating_to_dropoff: "In Transit",
  arrived_at_dropoff: "Arrived At Drop-off",
  verification_started: "Verification Started",
  delivered: "Delivered",
  completed: "Completed",
  complete: "Completed",
  cancelled: "Cancelled",
  canceled: "Cancelled",
  failed: "Failed",
  refunded: "Refunded",
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
  const adminActor = data.adminOperationUpdatedBy || data.archivedByAdminId || null;
  return {
    actor: data.updatedBy || data.actorName || data.actorId || adminActor || "system",
    actorType: normalized(data.actorType || data.updatedByRole || (adminActor ? "admin" : "system")),
    actorId: data.actorId || data.updatedById || data.archivedByAdminId || null,
    actorName: data.actorName || data.updatedByName || data.adminOperationUpdatedBy || null,
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

  const previousQuote = previous.quoteId || previous.authoritativeQuoteId || null;
  const currentQuote = current.quoteId || current.authoritativeQuoteId || null;
  if (currentQuote && currentQuote !== previousQuote) add("quote_confirmed", "Quote Confirmed");

  const previousPayment = normalized(previous.paymentStatus || previous.stripePaymentStatus || previous.checkoutStatus);
  const currentPayment = normalized(current.paymentStatus || current.stripePaymentStatus || current.checkoutStatus);
  if (["paid", "succeeded", "confirmed", "complete"].includes(currentPayment) && currentPayment !== previousPayment) {
    add("payment_confirmed", "Payment Confirmed");
  }
  const previousRefund = normalized(previous.refundStatus);
  const currentRefund = normalized(current.refundStatus);
  if (["refunded", "succeeded", "complete"].includes(currentRefund) && currentRefund !== previousRefund) {
    add("refunded", "Refunded");
  }

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

  const previousAdminOperation = normalized(previous.adminOperationStatus || previous.adminArchiveStatus);
  const currentAdminOperation = normalized(current.adminOperationStatus || current.adminArchiveStatus);
  if (currentAdminOperation && currentAdminOperation !== previousAdminOperation) {
    add("admin_override", "Admin Override");
  }

  return events.map((event) => ({
    ...event,
    deliveryType: type,
    notes: current.timelineNote || current.statusNote || current.adminOperationReason || current.adminArchiveReason || null,
    ...actor(current),
  }));
}

function assignedRiderId(data = {}) {
  return data.assignedRiderId || data.riderId || data.driverId || data.assignedDriverId || null;
}

function terminalStatus(value) {
  return ["completed", "delivered", "cancelled", "canceled", "failed", "deleted"].includes(normalized(value));
}

function canonicalEventType(event, before, after) {
  const key = normalized(event.status || event.eventKey);
  const map = {
    created: "DeliveryCreated",
    requested: "DeliveryCreated",
    quote_confirmed: "QuoteConfirmed",
    payment_confirmed: "PaymentConfirmed",
    assigned: "RiderAssigned",
    accepted: "RiderAccepted",
    arrived_at_pickup: "RiderArrivedPickup",
    waiting: "WaitingStarted",
    waiting_at_pickup: "WaitingStarted",
    customer_responded: "CustomerResponded",
    collected: "Collected",
    picked_up: "Collected",
    in_transit: "InTransit",
    navigating_to_dropoff: "InTransit",
    arrived_at_dropoff: "RiderArrivedDropoff",
    verification_started: "VerificationStarted",
    delivered: "Completed",
    completed: "Completed",
    cancelled: "Cancelled",
    canceled: "Cancelled",
    failed: "Failed",
    refunded: "Refunded",
    admin_override: "AdminOverride",
  };
  if (map[key]) return map[key];
  if (event.eventKey === "assigned") return "RiderAssigned";
  if (!before && after) return "DeliveryCreated";
  return null;
}

function watchdogCondition(data = {}) {
  const status = normalized(data.status || data.deliveryStatus || data.deliveryStage);
  const rider = assignedRiderId(data);
  const payment = normalized(data.paymentStatus || data.stripePaymentStatus || data.checkoutStatus);
  if (["accepted", "assigned", "navigating_to_pickup"].includes(status) && rider) return "accepted_no_movement";
  if (["arrived_at_pickup", "waiting_at_pickup", "waiting"].includes(status)) return "arrived_not_collected";
  if (["collected", "picked_up", "navigating_to_dropoff", "in_transit"].includes(status)) return "collected_no_movement";
  if (["arrived_at_dropoff", "verification_started"].includes(status)) return "dropoff_completion_delay";
  if (!rider && ["paid", "succeeded", "confirmed", "complete"].includes(payment) &&
      ["requested", "searching", "matching", "available", "broadcasted"].includes(status)) {
    return "payment_dispatch_failure";
  }
  return null;
}

function operationalProjection(deliveryId, before, after, now = Timestamp.now(), existing = null) {
  const currentStatusValue = after.status || after.deliveryStatus || after.deliveryStage;
  const condition = terminalStatus(currentStatusValue) ? null : watchdogCondition(after);
  const previousStatus = normalized(before && (before.status || before.deliveryStatus || before.deliveryStage));
  const status = normalized(after.status || after.deliveryStatus || after.deliveryStage);
  const stateChanged = status !== previousStatus;
  const enteredAt = !stateChanged && existing && existing.stateEnteredAt ? existing.stateEnteredAt : now;
  const threshold = condition ? WATCHDOG_THRESHOLDS_MINUTES[condition] : null;
  return {
    deliveryId,
    status,
    incidentType: condition,
    active: Boolean(condition),
    assignedRiderId: assignedRiderId(after),
    stateEnteredAt: enteredAt,
    nextCheckAt: condition ? Timestamp.fromMillis(now.toMillis() + threshold * 60000) : null,
    openIncidentId: condition && existing && existing.incidentType === condition ? existing.openIncidentId || null : null,
    updatedAt: now,
    projectionVersion: "2026-08-operations-brain-v1",
  };
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
      const projectionRef = db.collection("deliveryOperationalState").doc(context.params.deliveryId);
      const projectionSnapshot = await projectionRef.get();
      const eventId = `${context.eventId || context.timestamp}`.replace(/[^a-zA-Z0-9_-]/g, "_");
      const batch = db.batch();
      events.forEach((event, index) => {
        const eventType = canonicalEventType(event, before, after);
        if (!eventType) return;
        appendOperationalEvent(db, {
          deliveryId: context.params.deliveryId,
          eventType,
          correlationId: `${eventId}:${index}`,
          timestamp: Timestamp.fromDate(new Date(context.timestamp)),
          actorType: event.actorType,
          actorId: event.actorId,
          source: "deliveryRequests.onWrite",
          previousState: before && before.status,
          newState: after.status,
          metadata: {
            deliveryType: event.deliveryType,
            notes: event.notes,
            quoteId: after.quoteId || after.authoritativeQuoteId || null,
            paymentRecordId: after.paymentRecordId || null,
          },
        }, {batch});
      });
      batch.set(projectionRef, operationalProjection(
          context.params.deliveryId,
          before,
          after,
          Timestamp.now(),
          projectionSnapshot.exists ? projectionSnapshot.data() : null,
      ), {merge: false});
      const previousProjection = projectionSnapshot.exists ? projectionSnapshot.data() || {} : {};
      const nextCondition = watchdogCondition(after);
      if (previousProjection.openIncidentId && previousProjection.incidentType !== nextCondition) {
        const incidentId = previousProjection.openIncidentId;
        batch.set(db.collection("operationalIncidents").doc(incidentId), {
          status: "RESOLVED",
          resolvedAt: FieldValue.serverTimestamp(),
          resolvedBy: "delivery-state-transition",
          resolutionReason: "delivery_state_progressed",
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
        appendOperationalEvent(db, {
          deliveryId: context.params.deliveryId,
          eventType: "IncidentResolved",
          correlationId: incidentId,
          timestamp: Timestamp.fromDate(new Date(context.timestamp)),
          source: "deliveryRequests.onWrite",
          previousState: before && before.status,
          newState: after.status,
          metadata: {incidentId, incidentType: previousProjection.incidentType, reason: "delivery_state_progressed"},
        }, {batch});
      }
      const reassigned = before && assignedRiderId(before) &&
        assignedRiderId(before) !== assignedRiderId(after);
      if (terminalStatus(after.status) || reassigned) {
        batch.delete(db.collection("deliveryLiveLocations").doc(context.params.deliveryId));
      }
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
      await appendOperationalEvent(db, {
        deliveryId: context.params.deliveryId,
        eventType: event.includes("started") ? "LiveTrackingStarted" : "LiveTrackingStopped",
        correlationId: eventId,
        timestamp: Timestamp.fromDate(new Date(context.timestamp)),
        actorType: (after || before || {}).riderId ? "rider" : "system",
        actorId: (after || before || {}).riderId || null,
        source: "deliveryLiveLocations.onWrite",
        previousState: normalized(before && before.trackingStatus) || null,
        newState: normalized(after && after.trackingStatus) || null,
        metadata: {deliveryType: deliveryType(data), deliveryStatus: normalized(data.status)},
      });
      return null;
    });

module.exports.deliveryType = deliveryType;
module.exports.eventName = eventName;
module.exports.timelineEventsForChange = timelineEventsForChange;
module.exports.trackingEventForChange = trackingEventForChange;
module.exports.canonicalEventType = canonicalEventType;
module.exports.operationalProjection = operationalProjection;
module.exports.watchdogCondition = watchdogCondition;
module.exports.WATCHDOG_THRESHOLDS_MINUTES = WATCHDOG_THRESHOLDS_MINUTES;
