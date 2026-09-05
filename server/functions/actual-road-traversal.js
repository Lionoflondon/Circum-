"use strict";

const {
  deriveCircumRouteFacts,
  distanceMeters,
} = require("./road-charge-geography");
const {evaluateRoadCharges} = require("./road-charges-core");

const ACTUAL_TRAVERSAL_VERSION = "2026-08-actual-road-traversal-v1";
const MAX_POINTS = 120;
const MAX_SEGMENT_SPEED_MPS = 100;

function point(value) {
  const latitude = Number(value && (value.latitude ?? value.lat));
  const longitude = Number(value && (value.longitude ?? value.lng));
  if (
    !Number.isFinite(latitude) ||
    !Number.isFinite(longitude) ||
    latitude < -90 ||
    latitude > 90 ||
    longitude < -180 ||
    longitude > 180
  ) {
    return null;
  }
  return {latitude, longitude, at: value.at || null};
}

function timestampMs(value) {
  if (value && typeof value.toMillis === "function") return value.toMillis();
  if (value instanceof Date) return value.getTime();
  if (typeof value === "number") return Number.isFinite(value) ? value : NaN;
  const parsed = Date.parse(`${value || ""}`);
  return Number.isFinite(parsed) ? parsed : NaN;
}

function appendPoint(points, value) {
  const next = point(value);
  if (!next) return Array.isArray(points) ? points.slice(-MAX_POINTS) : [];
  const prior = Array.isArray(points) ? points.map(point).filter(Boolean) : [];
  const last = prior[prior.length - 1];
  if (
    last &&
    distanceMeters(
      [last.longitude, last.latitude],
      [next.longitude, next.latitude],
    ) < 25
  ) {
    return prior.slice(-MAX_POINTS);
  }
  return [...prior, next].slice(-MAX_POINTS);
}

function normalizeTraversalPoints(points) {
  const normalized = Array.isArray(points) ?
    points.map(point).filter(Boolean) :
    [];
  if (normalized.length < 2) {
    return {points: normalized, reason: "insufficient_server_observed_points"};
  }
  let previousAt = null;
  for (let index = 0; index < normalized.length; index += 1) {
    const current = normalized[index];
    const currentAt = timestampMs(current.at);
    if (!Number.isFinite(currentAt)) {
      return {points: [], reason: "invalid_movement_timestamp"};
    }
    if (previousAt !== null) {
      const elapsedSeconds = (currentAt - previousAt) / 1000;
      if (elapsedSeconds <= 0) {
        return {points: [], reason: "out_of_order_movement_timestamp"};
      }
      const previous = normalized[index - 1];
      const segmentMeters = distanceMeters(
        [previous.longitude, previous.latitude],
        [current.longitude, current.latitude],
      );
      if (segmentMeters / elapsedSeconds > MAX_SEGMENT_SPEED_MPS) {
        return {points: [], reason: "impossible_movement_segment"};
      }
    }
    current.at = new Date(currentAt).toISOString();
    previousAt = currentAt;
  }
  return {points: normalized, reason: null};
}

function evaluateActualTraversal({
  deliveryId,
  riderId,
  assignedVehicle,
  points,
} = {}) {
  const normalizedResult = normalizeTraversalPoints(points);
  const normalized = normalizedResult.points;
  if (normalized.length < 2 || normalizedResult.reason) {
    return {
      version: ACTUAL_TRAVERSAL_VERSION,
      deliveryId,
      riderId,
      status: "UNRESOLVED",
      evidenceCompleteness: "UNRESOLVED",
      reason: normalizedResult.reason,
    };
  }
  const startAt = new Date(normalized[0].at);
  const routeFacts = deriveCircumRouteFacts(
    normalized.map((item) => [item.longitude, item.latitude]),
    {at: startAt},
  );
  const charges = evaluateRoadCharges({
    routeFacts,
    selectedVehicle:
      assignedVehicle && (assignedVehicle.type || assignedVehicle.class),
    vehicleProfile: assignedVehicle || {},
    at: startAt,
    pricingContext: "actual_traversal",
  });
  const actualCustomerContributionPence = Number(
    charges.customerContributionPence || 0,
  );
  return {
    version: ACTUAL_TRAVERSAL_VERSION,
    deliveryId,
    riderId,
    assignedVehicleId: (assignedVehicle && assignedVehicle.id) || null,
    assignedVehicleClass:
      (assignedVehicle && (assignedVehicle.type || assignedVehicle.class)) ||
      "unknown",
    journeyStartAt: normalized[0].at || null,
    journeyEndAt: normalized[normalized.length - 1].at || null,
    observedPointCount: normalized.length,
    evidenceCompleteness: "COMPLETE",
    status: actualCustomerContributionPence > 0 ? "INCURRED" : "NOT_INCURRED",
    routeFacts,
    charges: charges.charges,
    actualCustomerContributionPence,
    evaluatedAt: new Date().toISOString(),
  };
}

module.exports = {
  ACTUAL_TRAVERSAL_VERSION,
  MAX_POINTS,
  MAX_SEGMENT_SPEED_MPS,
  point,
  appendPoint,
  normalizeTraversalPoints,
  evaluateActualTraversal,
};
