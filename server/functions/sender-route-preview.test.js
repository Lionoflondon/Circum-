"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const {_private} = require("./sender-booking");

const source = fs.readFileSync("sender-booking.js", "utf8");

test("Sender route preview is authenticated and App Check protected", () => {
  const route = source.match(/exports\.getSenderRoutePreview[\s\S]*?\n\}\);/)[0];
  assert.match(route, /senderPaymentCallable/);
  assert.match(route, /requireSender\(context\)/);
  assert.match(source, /defineSecret\("GOOGLE_MAPS_DIRECTIONS_API_KEY"\)/);
  assert.match(source, /AbortController/);
  assert.doesNotMatch(route, /return \{[^}]*apiKey/);
});

test("Sender route preview validates coordinates and returns display-only data", () => {
  assert.match(source, /function routeCoordinate/);
  assert.match(source, /distanceMetres/);
});

test("route provider result is authoritative and includes duration", async () => {
  let calls = 0;
  const result = await _private.fetchSenderRoute({
    origin: {latitude: 51.5, longitude: -0.1},
    destination: {latitude: 51.6, longitude: -0.2},
    apiKey: "redacted",
    fetchImpl: async (url, options) => {
      assert.equal(url, "https://routes.googleapis.com/directions/v2:computeRoutes");
      assert.equal(options.method, "POST");
      assert.equal(options.headers["X-Goog-Api-Key"], "redacted");
      assert.equal(options.headers["X-Goog-FieldMask"], "routes.duration,routes.distanceMeters,routes.polyline.encodedPolyline");
      assert.deepEqual(JSON.parse(options.body).origin, {location: {latLng: {latitude: 51.5, longitude: -0.1}}});
      assert.ok(options.signal instanceof AbortSignal);
      calls += 1;
      return {
        ok: true,
        json: async () => ({routes: [{
          polyline: {encodedPolyline: "encoded"},
          distanceMeters: 3218, duration: "600s",
        }]}),
      };
    },
  });
  assert.equal(calls, 1);
  assert.deepEqual(result, {
    encodedPolyline: "encoded",
    distanceMetres: 3218,
    durationSeconds: 600,
  });
});

test("paid delivery must match the backend-quoted endpoints", () => {
  const quote = {parcelAuthority: {description: "Book", weightKg: 1}, route: {
    origin: {latitude: 51.5, longitude: -0.1},
    destination: {latitude: 51.6, longitude: -0.2},
  }};
  const delivery = {
    pickup: {lat: 51.5, lng: -0.1},
    dropoff: {lat: 51.6, lng: -0.2},
    parcel: {itemName: "Book", weightKg: 1},
    recipient: {name: "Recipient"},
  };
  assert.deepEqual(_private.assertDeliveryMatchesQuote(delivery, quote), {
    origin: {latitude: 51.5, longitude: -0.1},
    destination: {latitude: 51.6, longitude: -0.2},
  });
  assert.throws(
      () => _private.assertDeliveryMatchesQuote({
        ...delivery,
        dropoff: {lat: 51.7, lng: -0.2},
      }, quote),
      (error) => error.code === "failed-precondition",
  );
  assert.throws(
      () => _private.assertDeliveryMatchesQuote({...delivery, recipient: null}, quote),
      (error) => error.code === "invalid-argument",
  );
});

test("booking quote pricing receives only provider-computed distance", () => {
  const callable = source.match(/exports\.createSenderBookingQuote[\s\S]*?\}, \{secrets: \[senderDirectionsApiKey\]\}\);/)[0];
  assert.match(callable, /authoritativeDistanceMiles = authoritativeRoute\.distanceMetres \/ 1609\.344/);
  assert.match(callable, /distanceMiles: authoritativeDistanceMiles/);
  assert.match(callable, /routeCoordinate\(requestedRoute\.origin/);
});

test("every payment mode persists complete delivery payload before confirmation", () => {
  const payment = source.match(/exports\.createSenderPaymentSession[\s\S]*?\n\}, \{secrets: \["STRIPE_SECRET_KEY"\]\}\);\n\nasync function updateSenderPaymentIntentStatus/)[0];
  assert.match(payment, /assertDeliveryMatchesQuote\(deliveryPayload, quote\)/);
  assert.match(payment, /paymentSessionKey: requestedSessionKey,\n\s+deliveryPayload,/);
});


test("Routes API failures and missing route metrics fail closed", async () => {
  const input = {origin: {latitude: 51.5, longitude: -0.1}, destination: {latitude: 51.6, longitude: -0.2}, apiKey: "not-exposed"};
  for (const response of [
    {ok: false, status: 403},
    {ok: true, json: async () => ({routes: []})},
    {ok: true, json: async () => ({routes: [{polyline: {encodedPolyline: "encoded"}}]})},
  ]) {
    await assert.rejects(_private.fetchSenderRoute({...input, fetchImpl: async () => response}), (error) => !error.message.includes(input.apiKey));
  }
});
