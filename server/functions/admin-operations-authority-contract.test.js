const fs = require("node:fs");
const test = require("node:test");
const assert = require("node:assert/strict");

const source = fs.readFileSync("admin-operations-authority.js", "utf8");

test("Admin cannot create canonical deliveries by duplicating live records", () => {
  assert.match(
      source,
      /exports\.adminDuplicateDelivery = functions\.runWith\(\{enforceAppCheck: true\}\)\.https\.onCall/,
  );
  assert.match(source, /delivery_duplicate_rejected/);
  assert.match(source, /rejected_duplicate_authority/);
  assert.match(source, /Delivery duplication is retired/);
  assert.doesNotMatch(source, /function duplicateDelivery\(/);
  assert.doesNotMatch(source, /collection\("deliveryRequests"\)\.doc\(newId\)\.set/);
  assert.doesNotMatch(source, /collection\('deliveryRequests'\)\.doc\(newId\)\.set/);
});
