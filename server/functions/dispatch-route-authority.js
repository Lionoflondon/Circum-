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

module.exports = {resolvePickupRoute};
