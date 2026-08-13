const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const source = fs.readFileSync(path.join(__dirname, "sender-saved-addresses.js"), "utf8");

test("saved address mutations require Auth, App Check, and server place re-resolution", () => {
  assert.match(source, /runWith\(\{enforceAppCheck: true\}\)\.https\.onCall/);
  assert.match(source, /resolveCanonicalAddress\(data && data\.address, "saved address"\)/);
  assert.match(source, /Choose a verified UK address from search results/);
  assert.match(source, /collection\("users"\)\.doc\(userId\)\.collection\("savedAddresses"\)/);
});
