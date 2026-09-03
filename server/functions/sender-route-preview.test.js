"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");

const source = fs.readFileSync("sender-booking.js", "utf8");

test("Sender route preview is authenticated and App Check protected", () => {
  const route = source.match(/exports\.getSenderRoutePreview[\s\S]*?\n\}\);/)[0];
  assert.match(route, /senderPaymentCallable/);
  assert.match(route, /requireSender\(context\)/);
  assert.match(source, /defineSecret\("GOOGLE_MAPS_DIRECTIONS_API_KEY"\)/);
  assert.match(route, /AbortController/);
  assert.doesNotMatch(route, /return \{[^}]*apiKey/);
});

test("Sender route preview validates coordinates and returns display-only data", () => {
  assert.match(source, /function routeCoordinate/);
  assert.match(source, /return \{encodedPolyline, distanceMetres\}/);
});
