"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const {
  canonicalAddress,
  canonicalAddressPair,
  resolveCanonicalAddress,
  sameCanonicalAddress,
} = require("./canonical-address-authority");

const address = (placeId, lat = 51.5, lng = -0.1) => ({
  displayAddress: "10 Example Street, London, SW1A 1AA, United Kingdom",
  addressLine1: "10 Example Street",
  city: "London",
  postcode: "SW1A 1AA",
  country: "United Kingdom",
  placeId,
  locationId: placeId,
  provider: "google_places",
  validationStatus: "verified",
  lat,
  lng,
});

test("canonical address accepts a verified UK address contract", () => {
  const result = canonicalAddress(address("place-1"), "pickup address");
  assert.deepEqual(result.coordinates, {latitude: 51.5, longitude: -0.1});
  assert.equal(result.placeId, "place-1");
});

test("raw coordinates without canonical identity are rejected", () => {
  assert.throws(() => canonicalAddress({lat: 51.5, lng: -0.1}), /verified canonical address/);
});

test("unverified or non-UK coordinates are rejected", () => {
  assert.throws(() => canonicalAddress({...address("place-1"), validationStatus: "unverified"}), /verified canonical address/);
  assert.throws(() => canonicalAddress({...address("place-1"), lat: 40.7, lng: -74}), /valid UK coordinate/);
});

test("financial address authority re-resolves Google place identity server-side", async () => {
  const result = await resolveCanonicalAddress(address("place-1"), "pickup address", {
    googlePlacesApiKey: "test-key",
    fetchImpl: async () => ({
      ok: true,
      json: async () => ({
        status: "OK",
        result: {
          place_id: "place-1",
          formatted_address: "10 Example Street, London, SW1A 1AA, UK",
          geometry: {location: {lat: 51.5, lng: -0.1}},
          address_components: [
            {long_name: "10", types: ["street_number"]},
            {long_name: "Example Street", types: ["route"]},
            {long_name: "London", types: ["postal_town"]},
            {long_name: "SW1A 1AA", types: ["postal_code"]},
            {long_name: "United Kingdom", types: ["country"]},
          ],
        },
      }),
    }),
  });
  assert.equal(result.provider, "google_places");
  assert.equal(result.postcode, "SW1A 1AA");
  assert.deepEqual(result.coordinates, {latitude: 51.5, longitude: -0.1});
});

test("financial address authority rejects a place identity with mismatched coordinates", async () => {
  await assert.rejects(
      resolveCanonicalAddress(address("place-1", 51.6, -0.1), "pickup address", {
        googlePlacesApiKey: "test-key",
        fetchImpl: async () => ({
          ok: true,
          json: async () => ({
            status: "OK",
            result: {
              place_id: "place-1",
              formatted_address: "10 Example Street, London, SW1A 1AA, UK",
              geometry: {location: {lat: 51.5, lng: -0.1}},
              address_components: [],
            },
          }),
        }),
      }),
      /server-resolved place identity/,
  );
});

test("canonical pair and identity comparison protect payment handoff", () => {
  const pair = canonicalAddressPair({
    pickupAddressCanonical: address("pickup"),
    dropoffAddressCanonical: address("dropoff", 51.51, -0.11),
  });
  assert.equal(sameCanonicalAddress(pair.pickup, canonicalAddress(address("pickup"))), true);
  assert.equal(sameCanonicalAddress(pair.pickup, pair.dropoff), false);
});

test("all financial address entry points use the shared canonical authority", () => {
  const sender = fs.readFileSync(path.join(__dirname, "sender-booking.js"), "utf8");
  const health = fs.readFileSync(path.join(__dirname, "health-plus.js"), "utf8");
  const gifts = fs.readFileSync(path.join(__dirname, "gifts-payment.js"), "utf8");
  assert.match(sender, /resolveCanonicalAddressPair\(data \|\| \{\}\)/);
  assert.match(sender, /sameCanonicalAddress\(submittedAddresses\.pickup/);
  assert.doesNotMatch(sender, /coordinate\(data && \(data\.pickupPosition/);
  assert.match(health, /resolveCanonicalAddress\(data\.pharmacyAddressCanonical/);
  assert.match(health, /resolveCanonicalAddress\(data\.deliveryAddressCanonical/);
  assert.doesNotMatch(health, /coordinate\(data\.pharmacyAddressCanonical \|\| data\.pharmacyPosition/);
  assert.match(gifts, /resolveCanonicalAddress\(\s*payload\.deliveryAddressData \|\| payload\.deliveryAddressCanonical/);
});
