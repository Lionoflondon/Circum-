"use strict";

const ROUTE_FACTS_VERSION = "circum_routes_v1";
const {deriveCircumRouteFacts, GEOGRAPHY_VERSION} = require("./road-charge-geography");
const {routeFingerprint} = require("./road-charge-route-provider");

function coordinate(value) {
  if (!value || typeof value !== "object") return null;
  const source = value.position && typeof value.position === "object" ? value.position : value;
  const lat = Number(source.latitude ?? source.lat);
  const lng = Number(source.longitude ?? source.lng ?? source.lon);
  if (!Number.isFinite(lat) || !Number.isFinite(lng) || lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
  return {latitude: lat, longitude: lng};
}

function decodePolyline(encoded) {
  const points = [];
  let index = 0;
  let lat = 0;
  let lng = 0;
  while (index < encoded.length) {
    let result = 0;
    let shift = 0;
    let byte;
    do {
      byte = encoded.charCodeAt(index++) - 63;
      result |= (byte & 31) << shift;
      shift += 5;
    } while (byte >= 32);
    lat += (result & 1) ? ~(result >> 1) : result >> 1;
    result = 0; shift = 0;
    do {
      byte = encoded.charCodeAt(index++) - 63;
      result |= (byte & 31) << shift;
      shift += 5;
    } while (byte >= 32);
    lng += (result & 1) ? ~(result >> 1) : result >> 1;
    points.push({latitude: lat / 1e5, longitude: lng / 1e5});
  }
  return points;
}

function routeEntersCentralLondon(points) {
  return points.some((point) => point.latitude >= 51.48 && point.latitude <= 51.54 && point.longitude >= -0.20 && point.longitude <= 0.05);
}

async function getAuthoritativeRouteFacts({origin, destination, fetchImpl = global.fetch} = {}) {
  const canonicalOrigin = coordinate(origin);
  const canonicalDestination = coordinate(destination);
  if (!canonicalOrigin || !canonicalDestination) {
    const error = new Error("Canonical route endpoints are required.");
    error.code = "missing_canonical_route_endpoints";
    throw error;
  }
  const key = `${process.env.GOOGLE_ROUTES_API_KEY || ""}`.trim();
  if (!key) {
    const error = new Error("Server-side Google Routes credential is not configured.");
    error.code = "routes_credential_missing";
    throw error;
  }
  const response = await fetchImpl("https://routes.googleapis.com/directions/v2:computeRoutes", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-goog-api-key": key,
      "x-goog-fieldmask": "routes.distanceMeters,routes.duration,routes.polyline.encodedPolyline,routes.travelAdvisory.tollInfo",
    },
    body: JSON.stringify({
      origin: {location: {latLng: canonicalOrigin}},
      destination: {location: {latLng: canonicalDestination}},
      travelMode: "DRIVE",
      computeAlternativeRoutes: false,
    }),
  });
  if (!response.ok) {
    const error = new Error(`Authoritative Routes request failed with HTTP ${response.status}.`);
    error.code = "routes_request_failed";
    throw error;
  }
  const body = await response.json();
  const route = Array.isArray(body.routes) ? body.routes[0] : null;
  if (!route || !Number.isFinite(Number(route.distanceMeters))) {
    const error = new Error("Authoritative Routes returned no usable route.");
    error.code = "routes_result_invalid";
    throw error;
  }
  const geometry = route.polyline && route.polyline.encodedPolyline ? decodePolyline(route.polyline.encodedPolyline) : [];
  const geography = deriveCircumRouteFacts(
      geometry.map((point) => [point.longitude, point.latitude]),
      {googleTollSignal: Boolean(route.travelAdvisory && route.travelAdvisory.tollInfo)},
  );
  const fingerprint = routeFingerprint({
    origin: canonicalOrigin,
    destination: canonicalDestination,
    points: geometry.map((point) => [point.longitude, point.latitude]),
    distanceMeters: Number(route.distanceMeters),
  });
  return {
    authority: "authoritative_route",
    known: true,
    version: ROUTE_FACTS_VERSION,
    provider: "google_routes",
    origin: canonicalOrigin,
    destination: canonicalDestination,
    distanceMeters: Number(route.distanceMeters),
    distanceMiles: Number(route.distanceMeters) / 1609.344,
    durationSeconds: Number.parseFloat(`${route.duration || ""}`) || null,
    encodedPolyline: route.polyline && route.polyline.encodedPolyline || null,
    centralLondonEntered: Boolean(geography.congestionZone && geography.congestionZone.entered === true),
    geography,
    geographyVersion: GEOGRAPHY_VERSION,
    routeFingerprint: fingerprint,
    tollInfo: route.travelAdvisory && route.travelAdvisory.tollInfo || null,
    evaluatedAt: new Date().toISOString(),
  };
}

module.exports = {ROUTE_FACTS_VERSION, coordinate, decodePolyline, getAuthoritativeRouteFacts, routeEntersCentralLondon};
