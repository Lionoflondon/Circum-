"use strict";

const {deriveCircumRouteFacts, distanceMeters} = require("./road-charge-geography");
const {evaluateRoadCharges} = require("./road-charges-core");

const ACTUAL_TRAVERSAL_VERSION = "2026-08-actual-road-traversal-v1";
const MAX_POINTS = 120;

function point(value) {
  const latitude = Number(value && (value.latitude ?? value.lat));
  const longitude = Number(value && (value.longitude ?? value.lng));
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude) || latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) return null;
  return {latitude, longitude, at: value.at || null};
}

function appendPoint(points, value) {
  const next = point(value);
  if (!next) return Array.isArray(points) ? points.slice(-MAX_POINTS) : [];
  const prior = Array.isArray(points) ? points.map(point).filter(Boolean) : [];
  const last = prior[prior.length - 1];
  if (last && distanceMeters([last.longitude, last.latitude], [next.longitude, next.latitude]) < 25) return prior.slice(-MAX_POINTS);
  return [...prior, next].slice(-MAX_POINTS);
}

function evaluateActualTraversal({deliveryId, riderId, assignedVehicle, points} = {}) {
  const normalized = Array.isArray(points) ? points.map(point).filter(Boolean) : [];
  if (normalized.length < 2) {
    return {version: ACTUAL_TRAVERSAL_VERSION, deliveryId, riderId, status: "UNRESOLVED", evidenceCompleteness: "UNRESOLVED", reason: "insufficient_server_observed_points"};
  }
  const startAt = normalized[0].at ? new Date(normalized[0].at) : new Date();
  const routeFacts = deriveCircumRouteFacts(
      normalized.map((item) => [item.longitude, item.latitude]),
      {at: startAt},
  );
  const charges = evaluateRoadCharges({
    routeFacts,
    selectedVehicle: assignedVehicle && (assignedVehicle.type || assignedVehicle.class),
    vehicleProfile: assignedVehicle || {},
    at: startAt,
    pricingContext: "actual_traversal",
  });
  const actualCustomerContributionPence = Number(charges.customerContributionPence || 0);
  return {
    version: ACTUAL_TRAVERSAL_VERSION,
    deliveryId,
    riderId,
    assignedVehicleId: assignedVehicle && assignedVehicle.id || null,
    assignedVehicleClass: assignedVehicle && (assignedVehicle.type || assignedVehicle.class) || "unknown",
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

module.exports = {ACTUAL_TRAVERSAL_VERSION, MAX_POINTS, point, appendPoint, evaluateActualTraversal};
