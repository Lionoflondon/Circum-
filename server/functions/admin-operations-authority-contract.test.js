const fs = require("node:fs");
const test = require("node:test");
const assert = require("node:assert/strict");

const source = fs.readFileSync("admin-operations-authority.js", "utf8");

test("Admin cannot create canonical deliveries by duplicating live records", () => {
  assert.doesNotMatch(source, /exports\.adminDuplicateDelivery/);
  assert.doesNotMatch(source, /function duplicateDelivery\(/);
  assert.doesNotMatch(source, /collection\("deliveryRequests"\)\.doc\(newId\)\.set/);
  assert.doesNotMatch(source, /collection\('deliveryRequests'\)\.doc\(newId\)\.set/);
});
