/* eslint-disable require-jsdoc */

function finiteCoordinate(value) {
  return Number.isFinite(Number(value)) ? Number(value) : null;
}

function point(value) {
  if (!value || typeof value !== "object") return null;
  const latitude = finiteCoordinate(value.latitude ?? value.lat);
  const longitude = finiteCoordinate(value.longitude ?? value.lng);
  return latitude == null || longitude == null ? null : {latitude, longitude};
}

function routeUrl(origin, destination, apiKey) {
  const params = new URLSearchParams({
    origin: `${origin.latitude},${origin.longitude}`,
    destination: `${destination.latitude},${destination.longitude}`,
    key: apiKey,
  });
  return `https://maps.googleapis.com/maps/api/directions/json?${params}`;
}

const routeCache = new Map();
const ROUTE_CACHE_TTL_MS = 10 * 60 * 1000;

function cacheKey(origin, destination) {
  return [origin, destination].map((item) =>
    `${item.latitude.toFixed(4)},${item.longitude.toFixed(4)}`).join("|");
}

async function resolveAuthoritativeRoute({
  pickupCoordinates,
  dropoffCoordinates,
  apiKey = process.env.GOOGLE_PLACES_API_KEY || process.env.GOOGLE_MAPS_DIRECTIONS_API_KEY,
  fetchImpl = global.fetch,
} = {}) {
  const origin = point(pickupCoordinates);
  const destination = point(dropoffCoordinates);
  const resolvedAt = new Date().toISOString();
  if (!origin || !destination) {
    return {distanceMiles: null, durationMinutes: null, source: "unresolved", reason: "missing_coordinates", resolvedAt};
  }
  if (!apiKey || typeof fetchImpl !== "function") {
    return {distanceMiles: null, durationMinutes: null, source: "unresolved", reason: "route_authority_unavailable", resolvedAt};
  }
  const key = cacheKey(origin, destination);
  const cached = routeCache.get(key);
  if (cached && Date.now() - cached.cachedAt < ROUTE_CACHE_TTL_MS) return cached.value;
  try {
    const response = await fetchImpl(routeUrl(origin, destination, apiKey));
    if (!response || !response.ok) throw new Error("route_request_failed");
    const body = await response.json();
    const leg = body && body.routes && body.routes[0] && body.routes[0].legs && body.routes[0].legs[0];
    const durationSeconds = Number(leg && leg.duration && leg.duration.value);
    const distanceMeters = Number(leg && leg.distance && leg.distance.value);
    if (!Number.isFinite(durationSeconds) || durationSeconds < 0 ||
        !Number.isFinite(distanceMeters) || distanceMeters < 0) throw new Error("route_result_invalid");
    const route = body.routes[0];
    const value = {
      distanceMiles: distanceMeters / 1609.344,
      durationMinutes: durationSeconds / 60,
      durationSeconds,
      distanceMeters,
      encodedPolyline: route.overview_polyline && route.overview_polyline.points || null,
      source: "backend_distance_matrix_v1",
      authority: "google_directions_backend",
      resolvedAt,
    };
    routeCache.set(key, {cachedAt: Date.now(), value});
    return value;
  } catch (error) {
    return {distanceMiles: null, durationMinutes: null, source: "unresolved", reason: "route_request_failed", resolvedAt};
  }
}

async function resolvePickupRoute({origin, destination, apiKey = process.env.GOOGLE_MAPS_DIRECTIONS_API_KEY, fetchImpl = global.fetch}) {
  const start = point(origin);
  const end = point(destination);
  if (!start || !end || !apiKey || typeof fetchImpl !== "function") return null;

  const response = await fetchImpl(routeUrl(start, end, apiKey));
  if (!response || !response.ok) return null;
  const body = await response.json();
  const leg = body && body.routes && body.routes[0] && body.routes[0].legs && body.routes[0].legs[0];
  const durationSeconds = Number(leg && leg.duration && leg.duration.value);
  const distanceMeters = Number(leg && leg.distance && leg.distance.value);
  const firstRoute = body && body.routes && body.routes[0];
  const encodedPolyline = firstRoute && firstRoute.overview_polyline && firstRoute.overview_polyline.points;
  if (!Number.isFinite(durationSeconds) || durationSeconds < 0 ||
      !Number.isFinite(distanceMeters) || distanceMeters < 0) return null;

  return {
    durationSeconds,
    distanceMeters,
    encodedPolyline: typeof encodedPolyline === "string" ? encodedPolyline : null,
    calculatedAt: new Date().toISOString(),
    authority: "google_directions_backend",
  };
}

module.exports = {resolvePickupRoute, resolveAuthoritativeRoute};
