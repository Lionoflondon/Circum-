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

test("access resolution reports missing roles without granting access or writing admin records", () => {
  assert.match(source, /async function resolveActor\(context, \{allowMissingRole = false, db = getFirestore\(\)\} = \{\}\)/);
  assert.match(source, /if \(!roles\.size && !allowMissingRole\)/);
  assert.match(source, /resolveActor\(context, \{allowMissingRole: true, db\}\)/);
  assert.match(source, /if \(!actor\.roles\.length\) \{\s*return \{roles: \[\], permissions: \[\], accessGranted: false\};/);
  assert.match(source, /if \(!actor\.roles\.length\)[\s\S]*?return \{roles: \[\], permissions: \[\], accessGranted: false\};[\s\S]*?lastLoginAt/);
});
