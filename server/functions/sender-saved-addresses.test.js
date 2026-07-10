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
    placeId: "place-1",
  }});
  assert.equal(address.formattedAddress, "10 Downing Street, London, SW1A 2AA, United Kingdom");
  assert.equal(address.addressLine2, undefined);
  assert.equal(address.placeId, "place-1");
});
