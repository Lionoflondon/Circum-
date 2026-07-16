"use strict";

const SENDER_TRACKING_STATES = Object.freeze({
  NO_ACTIVE_DELIVERY: "no_active_delivery",
  LOADING: "loading",
  FINDING_RIDER: "finding_rider",
  RIDER_ASSIGNED: "rider_assigned",
  RIDER_EN_ROUTE_TO_PICKUP: "rider_en_route_to_pickup",
  RIDER_ARRIVED_AT_PICKUP: "rider_arrived_at_pickup",
  PICKUP_COMPLETE: "pickup_complete",
  IN_TRANSIT: "in_transit",
  RIDER_ARRIVING_AT_DROPOFF: "rider_arriving_at_dropoff",
  DELIVERED: "delivered",
  CANCELLED: "cancelled",
  ISSUE: "issue",
  ERROR: "error",
});

const BACKEND_STATUS_TO_SENDER_STATE = Object.freeze({
  requested: SENDER_TRACKING_STATES.FINDING_RIDER,
  pending: SENDER_TRACKING_STATES.FINDING_RIDER,
  unmatched: SENDER_TRACKING_STATES.FINDING_RIDER,
  finding_rider: SENDER_TRACKING_STATES.FINDING_RIDER,
  awaiting_rider: SENDER_TRACKING_STATES.FINDING_RIDER,
  broadcast: SENDER_TRACKING_STATES.FINDING_RIDER,
  broadcasted: SENDER_TRACKING_STATES.FINDING_RIDER,
  accepted: SENDER_TRACKING_STATES.RIDER_ASSIGNED,
  rider_assigned: SENDER_TRACKING_STATES.RIDER_ASSIGNED,
  navigating_to_pickup: SENDER_TRACKING_STATES.RIDER_EN_ROUTE_TO_PICKUP,
  en_route_to_pickup: SENDER_TRACKING_STATES.RIDER_EN_ROUTE_TO_PICKUP,
  arrived_at_pickup: SENDER_TRACKING_STATES.RIDER_ARRIVED_AT_PICKUP,
  waiting: SENDER_TRACKING_STATES.RIDER_ARRIVED_AT_PICKUP,
  pickup_verification: SENDER_TRACKING_STATES.PICKUP_COMPLETE,
  pickup_verified: SENDER_TRACKING_STATES.PICKUP_COMPLETE,
  collected: SENDER_TRACKING_STATES.PICKUP_COMPLETE,
  out_for_delivery: SENDER_TRACKING_STATES.IN_TRANSIT,
  outfordelivery: SENDER_TRACKING_STATES.IN_TRANSIT,
  navigating_to_dropoff: SENDER_TRACKING_STATES.IN_TRANSIT,
  arrived_at_dropoff: SENDER_TRACKING_STATES.RIDER_ARRIVING_AT_DROPOFF,
  pin_required: SENDER_TRACKING_STATES.RIDER_ARRIVING_AT_DROPOFF,
  handover_pending: SENDER_TRACKING_STATES.RIDER_ARRIVING_AT_DROPOFF,
  delivered: SENDER_TRACKING_STATES.DELIVERED,
  completed: SENDER_TRACKING_STATES.DELIVERED,
  delivery_completed: SENDER_TRACKING_STATES.DELIVERED,
  cancelled: SENDER_TRACKING_STATES.CANCELLED,
  canceled: SENDER_TRACKING_STATES.CANCELLED,
  cancelled_verified_discrepancy: SENDER_TRACKING_STATES.CANCELLED,
  sender_no_show_pickup: SENDER_TRACKING_STATES.CANCELLED,
  issue: SENDER_TRACKING_STATES.ISSUE,
  issue_reported: SENDER_TRACKING_STATES.ISSUE,
  failed: SENDER_TRACKING_STATES.ISSUE,
  failed_delivery: SENDER_TRACKING_STATES.ISSUE,
  error: SENDER_TRACKING_STATES.ERROR,
});

const ALLOWED_TRANSITIONS = Object.freeze({
  requested: ["accepted", "cancelled", "issue_reported"],
  accepted: ["navigating_to_pickup", "arrived_at_pickup", "cancelled", "issue_reported"],
  navigating_to_pickup: ["arrived_at_pickup", "cancelled", "issue_reported"],
  arrived_at_pickup: ["waiting", "pickup_verification", "pickup_verified", "cancelled", "issue_reported"],
  waiting: ["pickup_verification", "pickup_verified", "cancelled", "issue_reported"],
  pickup_verification: ["pickup_verified", "issue_reported"],
  pickup_verified: ["collected", "navigating_to_dropoff", "issue_reported"],
  collected: ["navigating_to_dropoff", "issue_reported"],
  picked_up: ["navigating_to_dropoff", "issue_reported"],
  navigating_to_dropoff: ["arrived_at_dropoff", "issue_reported"],
  in_transit: ["arrived_at_dropoff", "issue_reported"],
  out_for_delivery: ["arrived_at_dropoff", "issue_reported"],
  arrived_at_dropoff: ["pin_required", "delivered", "issue_reported"],
  pin_required: ["delivered", "issue_reported"],
  issue_reported: ["cancelled", "delivered"],
  cancelled: [],
  delivered: [],
  completed: [],
});

const RIDER_ACTION_TO_STATUS = Object.freeze({
  start_heading_to_pickup: "navigating_to_pickup",
  arrived_at_pickup: "arrived_at_pickup",
  verify_collection_pin: "pickup_verified",
  confirm_collected: "collected",
  start_delivery: "navigating_to_dropoff",
  near_dropoff: "arrived_at_dropoff",
  arrived_at_dropoff: "arrived_at_dropoff",
  verify_receiver_pin: "delivered",
  report_issue: "issue_reported",
  cancel: "cancelled",
});

function normalizeStatus(value) {
  return `${value || ""}`.trim().toLowerCase().replace(/[-\s]+/g, "_");
}

function senderTrackingStateForBackendStatus(status) {
  const normalized = normalizeStatus(status);
  if (!normalized) return SENDER_TRACKING_STATES.NO_ACTIVE_DELIVERY;
  return BACKEND_STATUS_TO_SENDER_STATE[normalized] || SENDER_TRACKING_STATES.IN_TRANSIT;
}

function canTransitionDeliveryStatus(from, to) {
  const current = normalizeStatus(from);
  const next = normalizeStatus(to);
  if (!current || !next) return false;
  return (ALLOWED_TRANSITIONS[current] || []).includes(next);
}

function statusForRiderAction(action) {
  return RIDER_ACTION_TO_STATUS[normalizeStatus(action)] || "";
}

module.exports = {
  ALLOWED_TRANSITIONS,
  BACKEND_STATUS_TO_SENDER_STATE,
  RIDER_ACTION_TO_STATUS,
  SENDER_TRACKING_STATES,
  canTransitionDeliveryStatus,
  normalizeStatus,
  senderTrackingStateForBackendStatus,
  statusForRiderAction,
};
