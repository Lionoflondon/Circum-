"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {getAuthoritativeRouteFacts, routeEntersCentralLondon} = require("./route-authority");

function mockFetch(body) {
  return async (_url, options) => {
    assert.equal(options.method, "POST");
    assert.match(options.headers["x-goog-fieldmask"], /routes\.distanceMeters/);
    return {
      ok: true,
      async json() {
        return body;
      },
    };
  };
}

test("server route authority returns Google route facts without trusting client distance", async () => {
  const previousKey = process.env.GOOGLE_ROUTES_API_KEY;
  process.env.GOOGLE_ROUTES_API_KEY = "test-only-redacted";
  try {
    const facts = await getAuthoritativeRouteFacts({
      origin: {latitude: 51.5007, longitude: -0.1246},
      destination: {latitude: 51.5014, longitude: -0.1419},
      fetchImpl: mockFetch({
        routes: [{
          distanceMeters: 3210,
          duration: "480s",
          polyline: {encodedPolyline: ""},
        }],
      }),
    });
    assert.equal(facts.provider, "google_routes");
    assert.equal(facts.distanceMeters, 3210);
    assert.equal(facts.distanceMiles, 3210 / 1609.344);
    assert.equal(facts.durationSeconds, 480);
    assert.equal(facts.centralLondonEntered, false);
  } finally {
    if (previousKey === undefined) delete process.env.GOOGLE_ROUTES_API_KEY;
    else process.env.GOOGLE_ROUTES_API_KEY = previousKey;
  }
});

test("central London detection is based on decoded route geometry", () => {
  assert.equal(routeEntersCentralLondon([
    {latitude: 51.5007, longitude: -0.1246},
  ]), true);
  assert.equal(routeEntersCentralLondon([
    {latitude: 51.455, longitude: -0.1246},
  ]), false);
});
