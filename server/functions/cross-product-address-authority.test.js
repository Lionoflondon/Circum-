/* eslint-disable max-len */
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");

test("Google-backed address callables keep static egress guard", () => {
  const source = fs.readFileSync("free-address-search.js", "utf8");

  assert.match(source, /defineSecret\("GOOGLE_PLACES_API_KEY"\)/);
  assert.match(source, /searchFreeUkAddresses = functions\.runWith\(\{[\s\S]*?vpcConnector: "circum-fn-conn-v2"[\s\S]*?vpcConnectorEgressSettings: "ALL_TRAFFIC"/);
  assert.match(source, /resolveUkAddressPlace = functions\.runWith\(\{[\s\S]*?vpcConnector: "circum-fn-conn-v2"[\s\S]*?vpcConnectorEgressSettings: "ALL_TRAFFIC"/);
});

test("Business backend accepts only bounded canonical address fields", () => {
  const source = fs.readFileSync("business-access.js", "utf8");

  assert.match(source, /function cleanAddressData\(value\)/);
  assert.match(source, /"buildingNumber"/);
  assert.match(source, /"apartment"/);
  assert.match(source, /"resolutionPrecision"/);
  assert.match(source, /const businessAddressData = cleanAddressData\(data\.businessAddressData\)/);
  assert.match(source, /\.\.\.\(businessAddressData \? \{businessAddressData\} : \{\}\)/);
  assert.match(source, /defaultPickupAddressData: Array\.isArray\(data\.defaultPickupAddressData\)/);
  const sanitizer = source.slice(
      source.indexOf("function cleanAddressData"),
      source.indexOf("function slug"),
  );
  assert.doesNotMatch(sanitizer, /"email"/);
  assert.doesNotMatch(sanitizer, /"phone"/);
});
