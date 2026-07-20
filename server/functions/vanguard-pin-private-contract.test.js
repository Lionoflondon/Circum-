/* eslint-disable max-len, require-jsdoc */
"use strict";

const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const assert = require("node:assert/strict");

const root = path.join(__dirname, "..", "..");

function read(relativePath) {
  return fs.readFileSync(path.join(root, relativePath), "utf8");
}

test("Sender paid delivery creates private Vanguard PIN authority", () => {
  const source = read("server/functions/sender-booking.js");
  assert.match(source, /deliveryRequestsPrivate/);
  assert.match(source, /privateVanguardPinFields/);
  assert.match(source, /collectionPinAttemptCount: 0/);
  assert.match(source, /deliveryPinAttemptCount: 0/);
});

test("client Vanguard initial fields do not emit plaintext PINs", () => {
  for (const file of [
    "lib/app/delivery_security/vanguard_protection.dart",
    "lib/website/shared/policies/vanguard_protection.dart",
  ]) {
    const source = read(file);
    const initialFields = source.slice(
        source.indexOf("static Map<String, dynamic> initialFields"),
        source.indexOf("static String? matchedCategoryName"),
    );
    assert.doesNotMatch(initialFields, /'collectionPin'\s*:/, file);
    assert.doesNotMatch(initialFields, /'deliveryPin'\s*:/, file);
    assert.doesNotMatch(initialFields, /'collectionPinAttemptCount'\s*:/, file);
    assert.doesNotMatch(initialFields, /'deliveryPinAttemptCount'\s*:/, file);
    assert.doesNotMatch(initialFields, /'vanguardReviewRequired'\s*:/, file);
  }
});

test("Rider and Sender clients do not read or render plaintext Vanguard PINs", () => {
  const clientFiles = [
    "lib/app/send_package/models/delivery_data.m.dart",
    "lib/app/sender_mobile/sender_tracking_screen.dart",
    "lib/website/shared/circum_website_app.dart",
  ];
  for (const file of clientFiles) {
    const source = read(file);
    assert.doesNotMatch(source, /vanguardProtection[^;\n]+collectionPin/, file);
    assert.doesNotMatch(source, /vanguardProtection[^;\n]+deliveryPin/, file);
    assert.doesNotMatch(source, /data\['collectionPin'\]/, file);
    assert.doesNotMatch(source, /data\['deliveryPin'\]/, file);
    assert.doesNotMatch(source, /job\['collectionPin'\]/, file);
    assert.doesNotMatch(source, /job\['deliveryPin'\]/, file);
  }
});
