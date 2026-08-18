const assert = require("assert");
const {test} = require("node:test");
const {resolvePickupRoute, resolveAuthoritativeRoute} = require("./dispatch-route-authority");

test("pickup route authority returns backend duration, distance and provenance", async () => {
  const result = await resolvePickupRoute({
    origin: {latitude: 51.5, longitude: -0.1},
    destination: {latitude: 51.51, longitude: -0.09},
    apiKey: "test-key",
    fetchImpl: async () => ({
      ok: true,
      json: async () => ({
        routes: [{
          overview_polyline: {points: "encoded"},
          legs: [{
            duration: {value: 420},
            distance: {value: 2500},
          }],
        }],
      }),
    }),
  });

  assert.equal(result.durationSeconds, 420);
  assert.equal(result.distanceMeters, 2500);
  assert.equal(result.encodedPolyline, "encoded");
  assert.equal(result.authority, "google_directions_backend");
});

test("route authority fails closed when configuration or route data is absent", async () => {
  assert.equal(await resolvePickupRoute({
    origin: {latitude: 51.5, longitude: -0.1},
    destination: {latitude: 51.51, longitude: -0.09},
    apiKey: "",
    fetchImpl: async () => ({ok: true}),
  }), null);

  assert.equal(await resolvePickupRoute({
    origin: {latitude: 51.5, longitude: -0.1},
    destination: {latitude: 51.51, longitude: -0.09},
    apiKey: "test-key",
    fetchImpl: async () => ({ok: true, json: async () => ({routes: []})}),
  }), null);
});

test("authoritative quote route returns distance and duration with no client fallback", async () => {
  const result = await resolveAuthoritativeRoute({
    pickupCoordinates: {latitude: 51.52, longitude: -0.12},
    dropoffCoordinates: {latitude: 51.53, longitude: -0.11},
    apiKey: "test-key",
    fetchImpl: async () => ({
      ok: true,
      json: async () => ({routes: [{legs: [{duration: {value: 600}, distance: {value: 8046.72}}]}]}),
    }),
  });

  assert.equal(result.source, "backend_distance_matrix_v1");
  assert.equal(result.distanceMiles, 5);
  assert.equal(result.durationMinutes, 10);
  assert.equal(result.reason, undefined);
});

test("authoritative quote route is explicitly unresolved on provider failure", async () => {
  const result = await resolveAuthoritativeRoute({
    pickupCoordinates: {latitude: 51.54, longitude: -0.12},
    dropoffCoordinates: {latitude: 51.55, longitude: -0.11},
    apiKey: "test-key",
    fetchImpl: async () => ({ok: false}),
  });

  assert.equal(result.distanceMiles, null);
  assert.equal(result.durationMinutes, null);
  assert.equal(result.source, "unresolved");
  assert.equal(result.reason, "route_request_failed");
});
