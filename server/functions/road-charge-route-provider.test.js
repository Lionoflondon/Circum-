"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const {
  ROUTE_CACHE_MAX_AGE_MS,
  authoritativeRoadRouteFacts,
  routeFingerprint,
  googleRouteProvider,
} = require("./road-charge-route-provider");
const {deriveCircumRouteFacts} = require("./road-charge-geography");

const endpoints = {
  pickup: {latitude: 51.54, longitude: -0.2},
  dropoff: {latitude: 51.49, longitude: -0.1},
};

function fakeDb(initial = null) {
  let value = initial;
  return {
    collection: () => ({doc: () => ({
      get: async () => ({exists: value != null, data: () => value}),
      set: async (next) => {
 value = {...value, ...next};
},
    })}),
    value: () => value,
  };
}

const outsideRoute = [[-0.25, 51.55], [-0.2, 51.54]];
const cczRoute = [[-0.2, 51.54], [-0.12, 51.51], [-0.1, 51.49]];

test("fresh Google geometry is evaluated by CIRCUM rather than Google toll pricing", async () => {
  const provider = {name: "google_routes", getRoute: async () => ({
    provider: "google_routes",
    points: cczRoute,
    distanceMeters: 12000,
    duration: "900s",
    googleTollSignal: false,
  })};
  const result = await authoritativeRoadRouteFacts({...endpoints, db: fakeDb(), provider});
  assert.equal(result.financialAuthority, "circum_road_charge_engine");
  assert.equal(result.status, "CHARGE_CONFIRMED");
  assert.equal(result.congestionZone.entered, true);
  assert.equal(result.corroboration.disagreement, true);
  assert.match(result.routeFingerprint, /^[a-f0-9]{64}$/);
  assert.equal(result.routeDistanceMeters, 12000);
  assert.equal(result.routeDuration, "900s");
  assert.equal(result.routePointCount, cczRoute.length);
});

test("authoritative Google provider uses only GOOGLE_ROUTES_API_KEY", async () => {
  const previousRoutes = process.env.GOOGLE_ROUTES_API_KEY;
  const previousBrowser = process.env.CIRCUM_WEB_GOOGLE_MAPS_API_KEY;
  const previousLegacy = process.env.GOOGLE_MAPS_API_KEY;
  delete process.env.GOOGLE_ROUTES_API_KEY;
  process.env.CIRCUM_WEB_GOOGLE_MAPS_API_KEY = "browser-key-must-not-be-used";
  process.env.GOOGLE_MAPS_API_KEY = "legacy-key-must-not-be-used";
  try {
    await assert.rejects(
        googleRouteProvider().getRoute({
          origin: {latitude: 51.5, longitude: -0.1},
          destination: {latitude: 51.51, longitude: -0.11},
        }),
        (error) => error.code === "route_provider_unconfigured",
    );
  } finally {
    if (previousRoutes === undefined) delete process.env.GOOGLE_ROUTES_API_KEY;
    else process.env.GOOGLE_ROUTES_API_KEY = previousRoutes;
    if (previousBrowser === undefined) delete process.env.CIRCUM_WEB_GOOGLE_MAPS_API_KEY;
    else process.env.CIRCUM_WEB_GOOGLE_MAPS_API_KEY = previousBrowser;
    if (previousLegacy === undefined) delete process.env.GOOGLE_MAPS_API_KEY;
    else process.env.GOOGLE_MAPS_API_KEY = previousLegacy;
  }
});

test("Sender quote Function binds only the server Routes secret", () => {
  const source = fs.readFileSync(require.resolve("./sender-booking"), "utf8");
  assert.match(source, /createSenderBookingQuote\s*=\s*functions\.runWith\(\{\s*secrets:\s*\["GOOGLE_ROUTES_API_KEY"\]/s);
  const providerSource = fs.readFileSync(require.resolve("./road-charge-route-provider"), "utf8");
  assert.doesNotMatch(providerSource, /CIRCUM_WEB_GOOGLE_MAPS_API_KEY|process\.env\.GOOGLE_MAPS_API_KEY/);
});

test("GOOGLE_ROUTES_API_KEY is passed to the Routes API without exposing it", async () => {
  let observedKey = null;
  const provider = googleRouteProvider({
    apiKey: "server-routes-test-key",
    fetchImpl: async (_url, request) => {
      observedKey = request.headers["X-Goog-Api-Key"];
      return {
        ok: true,
        json: async () => ({routes: [{
          distanceMeters: 100,
          duration: "10s",
          polyline: {encodedPolyline: "_p~iF~ps|U_ulLnnqC"},
        }]}),
      };
    },
  });
  const route = await provider.getRoute({
    origin: {latitude: 51.5, longitude: -0.1},
    destination: {latitude: 51.51, longitude: -0.11},
  });
  assert.equal(observedKey, "server-routes-test-key");
  assert.equal(route.distanceMeters, 100);
});

test("route fingerprint binds endpoints, geometry, and distance", () => {
  const input = {
    origin: {latitude: 51.54, longitude: -0.2},
    destination: {latitude: 51.49, longitude: -0.1},
    points: cczRoute,
    distanceMeters: 12000,
  };
  assert.equal(routeFingerprint(input), routeFingerprint({...input}));
  assert.notEqual(
      routeFingerprint(input),
      routeFingerprint({...input, distanceMeters: input.distanceMeters + 1}),
  );
});

test("Google toll metadata does not change CIRCUM financial route facts", () => {
  const at = new Date("2026-08-08T12:00:00Z");
  const withoutMetadata = deriveCircumRouteFacts(cczRoute, {at, googleTollSignal: null});
  const withMetadata = deriveCircumRouteFacts(cczRoute, {at, googleTollSignal: true});
  assert.deepEqual(withoutMetadata.congestionZone, withMetadata.congestionZone);
  assert.deepEqual(withoutMetadata.crossings, withMetadata.crossings);
  assert.equal(withoutMetadata.status, withMetadata.status);
});

test("CIRCUM detects a crossing only when canonical geometry traverses both portals", () => {
  const blackwall = deriveCircumRouteFacts([
    [-0.0085, 51.497],
    [-0.0075, 51.503],
    [-0.0066, 51.5095],
  ], {at: new Date("2026-08-08T12:00:00Z")});
  const nearbyOnly = deriveCircumRouteFacts([
    [-0.0085, 51.497],
    [-0.02, 51.4975],
  ], {at: new Date("2026-08-08T12:00:00Z")});
  assert.equal(blackwall.crossings[0].crossingId, "blackwall");
  assert.equal(blackwall.crossings[0].direction, "northbound");
  assert.equal(nearbyOnly.crossings.length, 0);
});

test("Silvertown crossing detection follows both canonical portals and direction", () => {
  const northbound = deriveCircumRouteFacts([
    [0.00459, 51.49841],
    [0.01089, 51.50125],
    [0.0148, 51.5051],
  ], {at: new Date("2026-08-08T12:00:00Z")});
  const southbound = deriveCircumRouteFacts([
    [0.0148, 51.5051],
    [0.01089, 51.50125],
    [0.00459, 51.49841],
  ], {at: new Date("2026-08-08T12:00:00Z")});
  const nearbySouthBank = deriveCircumRouteFacts([
    [0.006, 51.491],
    [0.034, 51.493],
  ], {at: new Date("2026-08-08T12:00:00Z")});

  assert.deepEqual(
      northbound.crossings.map(({crossingId, direction}) => ({crossingId, direction})),
      [{crossingId: "silvertown", direction: "northbound"}],
  );
  assert.deepEqual(
      southbound.crossings.map(({crossingId, direction}) => ({crossingId, direction})),
      [{crossingId: "silvertown", direction: "southbound"}],
  );
  assert.equal(nearbySouthBank.crossings.length, 0);
});

test("provider timeout or 5xx uses sufficiently fresh validated geometry", async () => {
  for (const code of ["route_provider_timeout", "route_provider_http"]) {
    const now = new Date("2026-08-08T12:00:00Z");
    const db = fakeDb({
      provider: "google_routes",
      points: cczRoute,
      validatedAtMillis: now.getTime() - 1000,
    });
    const provider = {getRoute: async () => {
 throw Object.assign(new Error(code), {code});
}};
    const result = await authoritativeRoadRouteFacts({...endpoints, db, provider, now});
    assert.equal(result.routeSource, "server_validated_cache");
    assert.equal(result.status, "CHARGE_CONFIRMED");
  }
});

test("malformed provider response and absent cache fail safely, never as zero charge", async () => {
  const provider = {getRoute: async () => {
 throw Object.assign(new Error("bad"), {code: "route_provider_malformed"});
}};
  const result = await authoritativeRoadRouteFacts({...endpoints, db: fakeDb(), provider});
  assert.equal(result.status, "ROUTE_UNAVAILABLE");
  assert.equal(result.known, false);
  assert.notEqual(result.status, "NO_CHARGE");
});

test("expired cache is not financial evidence", async () => {
  const now = new Date("2026-08-08T12:00:00Z");
  const db = fakeDb({
    provider: "google_routes",
    points: outsideRoute,
    validatedAtMillis: now.getTime() - ROUTE_CACHE_MAX_AGE_MS - 1,
  });
  const provider = {getRoute: async () => {
 throw Object.assign(new Error("timeout"), {code: "route_provider_timeout"});
}};
  const result = await authoritativeRoadRouteFacts({...endpoints, db, provider, now});
  assert.equal(result.status, "ROUTE_UNAVAILABLE");
  assert.equal(result.known, false);
});

test("fresh cached geometry is re-evaluated by current CIRCUM geography policy", async () => {
  const now = new Date("2026-08-08T12:00:00Z");
  const db = fakeDb({points: outsideRoute, validatedAtMillis: now.getTime() - 1000});
  const provider = {getRoute: async () => {
 throw Object.assign(new Error("timeout"), {code: "route_provider_timeout"});
}};
  const result = await authoritativeRoadRouteFacts({...endpoints, db, provider, now});
  assert.equal(result.routeSource, "server_validated_cache");
  assert.equal(result.status, "NO_CHARGE");
  assert.equal(result.financialAuthority, "circum_road_charge_engine");
  assert.match(result.routeFingerprint, /^[a-f0-9]{64}$/);
  assert.equal(result.routePointCount, outsideRoute.length);
});
