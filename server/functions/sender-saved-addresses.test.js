const test = require("node:test");
const assert = require("node:assert/strict");
const {canonicalAddress} = require("./sender-saved-addresses");

test("saved address canonical validation rejects incomplete text", () => {
  assert.throws(() => canonicalAddress({address: {
    addressLine1: "10 Downing Street",
  }}), /Address is missing/);
});

test("saved address canonical payload removes literal null values", () => {
  const address = canonicalAddress({address: {
    addressLine1: "10 Downing Street",
    addressLine2: "null",
    city: "London",
    postcode: "SW1A 2AA",
    country: "United Kingdom",
  }});
  assert.equal(address.formattedAddress, "10 Downing Street, London, SW1A 2AA, United Kingdom");
  assert.equal(address.addressLine2, undefined);
  assert.equal(address.placeId, undefined);
});

test("place-backed saved addresses require canonical coordinates", () => {
  assert.throws(() => canonicalAddress({address: {
    addressLine1: "10 Downing Street",
    city: "London",
    postcode: "SW1A 2AA",
    country: "United Kingdom",
    placeId: "google-place-1",
  }}), /Resolve the selected address/);
});

test("place-backed canonical addresses preserve provenance and coordinates", () => {
  const address = canonicalAddress({address: {
    addressLine1: "10 Downing Street",
    city: "London",
    postcode: "SW1A 2AA",
    country: "United Kingdom",
    placeId: "google-place-1",
    provider: "google_places",
    latitude: 51.5034,
    longitude: -0.1276,
  }});
  assert.equal(address.provider, "google_places");
  assert.equal(address.latitude, 51.5034);
  assert.equal(address.longitude, -0.1276);
});
