/* eslint-disable max-len, require-jsdoc */
"use strict";
const scheduled = require("./scheduled-delivery-core");
const normalized = (x) => `${x || ""}`.trim().toLowerCase().replace(/[\s-]+/g, "_");
function watchdogCondition(d) {
 const s = normalized(d.status || d.deliveryStatus || d.deliveryStage); const rider = scheduled.assignedRiderId(d);
 if (["accepted", "assigned", "navigating_to_pickup"].includes(s) && rider) return "accepted_no_movement";
 if (["arrived_at_pickup", "waiting_at_pickup", "waiting"].includes(s)) return "arrived_not_collected";
 if (["collected", "picked_up", "navigating_to_dropoff", "in_transit"].includes(s)) return "collected_no_movement";
 if (["arrived_at_dropoff", "verification_started"].includes(s)) return "dropoff_completion_delay";
 if (!rider && ["paid", "succeeded", "confirmed", "complete"].includes(normalized(d.paymentStatus || d.stripePaymentStatus || d.checkoutStatus)) && ["requested", "searching", "matching", "available", "broadcasted"].includes(s)) return "payment_dispatch_failure";
 return null;
}

const INCIDENT_MESSAGES = Object.freeze({
 accepted_no_movement: "Delivery was accepted but the Rider has not moved for 15 minutes.",
 arrived_not_collected: "Delivery is waiting at pickup beyond the expected collection window.",
 collected_no_movement: "Delivery was collected but movement has not resumed.",
 dropoff_completion_delay: "Rider arrived at drop-off but completion is delayed.",
 payment_dispatch_failure: "Payment is confirmed but the delivery has not entered Rider dispatch.",
});
module.exports = {watchdogCondition, INCIDENT_MESSAGES};
