/* eslint-disable require-jsdoc */
"use strict";

const crypto = require("crypto");
const {deriveCircumRouteFacts, GEOGRAPHY_VERSION} = require("./road-charge-geography");

const ROUTE_CACHE_MAX_AGE_MS = 24 * 60 * 60 * 1000;

function decodePolyline(encoded) {
  const points = [];
  let index = 0;
  let latitude = 0;
  let longitude = 0;
  while (index < `${encoded || ""}`.length) {
    for (const coordinate of ["latitude", "longitude"]) {
      let result = 0;
      let shift = 0;
      let byte;
      do {
        byte = encoded.charCodeAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20 && index <= encoded.length);
      const delta = result & 1 ? ~(result >> 1) : result >> 1;
      if (coordinate === "latitude") latitude += delta;
      else longitude += delta;
    }
    points.push([longitude / 1e5, latitude / 1e5]);
  }
  return points;
}

function coordinate(value) {
  if (Array.isArray(value) && value.length >= 2) return {latitude: Number(value[0]), longitude: Number(value[1])};
  const source = value && (value.position || value.coordinates || value);
  return {
    latitude: Number(source && (source.latitude ?? source.lat)),
    longitude: Number(source && (source.longitude ?? source.lng ?? source.lon)),
  };
}

function routeCacheKey(origin, destination) {
  const stable = [origin, destination].map((point) =>
    `${point.latitude.toFixed(5)},${point.longitude.toFixed(5)}`).join("|");
  return crypto.createHash("sha256").update(stable).digest("hex");
}

function routeFingerprint({origin, destination, points, distanceMeters}) {
  const payload = JSON.stringify({
    origin: [origin.latitude, origin.longitude],
    destination: [destination.latitude, destination.longitude],
    points,
    distanceMeters: Number(distanceMeters || 0),
  });
  return crypto.createHash("sha256").update(payload).digest("hex");
}

function serializeRoutePoints(points) {
  return points.map(([longitude, latitude]) => ({longitude, latitude}));
}

function deserializeRoutePoints(points) {
  if (!Array.isArray(points)) return [];
  return points.map((point) => Array.isArray(point) ? point : [
    Number(point && point.longitude),
    Number(point && point.latitude),
  ]);
}

function googleRouteProvider({fetchImpl = fetch, apiKey = process.env.GOOGLE_ROUTES_API_KEY} = {}) {
  return {
    name: "google_routes",
    async getRoute({origin, destination}) {
      if (!apiKey) throw Object.assign(new Error("Google Routes key is unavailable."), {code: "route_provider_unconfigured"});
      const response = await fetchImpl("https://routes.googleapis.com/directions/v2:computeRoutes", {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "X-Goog-Api-Key": apiKey,
          "X-Goog-FieldMask": "routes.distanceMeters,routes.duration,routes.polyline.encodedPolyline,routes.travelAdvisory.tollInfo",
        },
        body: JSON.stringify({
          origin: {location: {latLng: origin}},
          destination: {location: {latLng: destination}},
          travelMode: "DRIVE",
          routingPreference: "TRAFFIC_AWARE",
          computeAlternativeRoutes: false,
          extraComputations: ["TOLLS"],
        }),
        signal: AbortSignal.timeout(8000),
      });
      if (!response.ok) throw Object.assign(new Error(`Google Routes HTTP ${response.status}`), {code: "route_provider_http", status: response.status});
      const body = await response.json();
      const route = body && Array.isArray(body.routes) && body.routes[0];
      const encoded = route && route.polyline && route.polyline.encodedPolyline;
      const points = decodePolyline(encoded);
      if (points.length < 2) throw Object.assign(new Error("Google Routes returned malformed geometry."), {code: "route_provider_malformed"});
      return {
        provider: "google_routes",
        points,
        distanceMeters: Number(route.distanceMeters || 0),
        duration: route.duration || null,
        googleTollSignal: Boolean(route.travelAdvisory && route.travelAdvisory.tollInfo),
      };
    },
  };
}

async function authoritativeRoadRouteFacts({db, pickup, dropoff, provider = googleRouteProvider(), now = new Date()} = {}) {
  const origin = coordinate(pickup);
  const destination = coordinate(dropoff);
  if (![origin.latitude, origin.longitude, destination.latitude, destination.longitude].every(Number.isFinite)) {
    return {status: "ROUTE_UNAVAILABLE", known: false, reason: "canonical_endpoints_unavailable"};
  }
  const cacheId = routeCacheKey(origin, destination);
  const cacheRef = db && db.collection("roadChargeRouteCache").doc(cacheId);
  try {
    const route = await provider.getRoute({origin, destination});
    const facts = deriveCircumRouteFacts(route.points, {at: now, googleTollSignal: route.googleTollSignal});
    const fingerprint = routeFingerprint({
      origin,
      destination,
      points: route.points,
      distanceMeters: route.distanceMeters,
    });
    if (cacheRef) {
      try {
        await cacheRef.set({
          provider: route.provider,
          points: serializeRoutePoints(route.points),
          distanceMeters: route.distanceMeters,
          duration: route.duration,
          geographyVersion: GEOGRAPHY_VERSION,
          routeFingerprint: fingerprint,
          validatedAtMillis: now.getTime(),
        }, {merge: true});
      } catch (cacheError) {
        console.warn("Authoritative route cache write failed", {
          code: cacheError && cacheError.code || "route_cache_write_failed",
        });
      }
    }
    return {
      ...facts,
      routeFingerprint: fingerprint,
      routeDistanceMeters: route.distanceMeters,
      routeDuration: route.duration,
      routePointCount: route.points.length,
      routeSource: "fresh_google",
      provider: route.provider,
    };
  } catch (error) {
    if (cacheRef) {
      const snapshot = await cacheRef.get();
      const cached = snapshot.exists ? snapshot.data() : null;
      const age = cached ? now.getTime() - Number(cached.validatedAtMillis || 0) : Infinity;
      const cachedPoints = deserializeRoutePoints(cached && cached.points);
      if (cached && age >= 0 && age <= ROUTE_CACHE_MAX_AGE_MS && cachedPoints.length >= 2) {
        return {
          ...deriveCircumRouteFacts(cachedPoints, {at: now}),
          routeFingerprint: cached.routeFingerprint || routeFingerprint({
            origin,
            destination,
            points: cachedPoints,
            distanceMeters: cached.distanceMeters,
          }),
          routeDistanceMeters: Number(cached.distanceMeters || 0),
          routeDuration: cached.duration || null,
          routePointCount: cachedPoints.length,
          routeSource: "server_validated_cache",
          provider: cached.provider || "cached_route",
          providerFailureCode: error.code || "route_provider_failed",
        };
      }
    }
    return {
      status: "ROUTE_UNAVAILABLE",
      known: false,
      routeSource: "unavailable",
      reason: error.code || "route_provider_failed",
    };
  }
}

module.exports = {
  ROUTE_CACHE_MAX_AGE_MS,
  decodePolyline,
  coordinate,
  routeCacheKey,
  routeFingerprint,
  googleRouteProvider,
  authoritativeRoadRouteFacts,
};
