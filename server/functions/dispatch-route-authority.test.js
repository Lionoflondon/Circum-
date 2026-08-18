const assert = require("assert");
const {test} = require("node:test");
const {resolvePickupRoute} = require("./dispatch-route-authority");

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
