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
    fetchImpl: async () => {
      calls += 1;
      return {
        ok: true,
        json: async () => ({routes: [{
          overview_polyline: {points: "encoded"},
          legs: [{distance: {value: 3218}, duration: {value: 600}}],
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
  const quote = {route: {
    origin: {latitude: 51.5, longitude: -0.1},
    destination: {latitude: 51.6, longitude: -0.2},
  }};
  const delivery = {
    pickup: {lat: 51.5, lng: -0.1},
    dropoff: {lat: 51.6, lng: -0.2},
    parcel: {itemName: "Parcel"},
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
  const payment = source.match(/exports\.createSenderPaymentSession[\s\S]*?\n\}\);\n\nasync function updateSenderPaymentIntentStatus/)[0];
  assert.match(payment, /assertDeliveryMatchesQuote\(deliveryPayload, quote\)/);
  assert.match(payment, /paymentSessionKey: requestedSessionKey,\n\s+deliveryPayload,/);
});
