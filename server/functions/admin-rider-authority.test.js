const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");

test("Admin Rider authority is backend-owned and auditable", () => {
  const source = fs.readFileSync("admin-rider-authority.js", "utf8");

  assert.match(source, /exports\.adminReviewRider = functions\.https\.onCall/);
  assert.match(source, /assertRiderAdmin\(context\)/);
  assert.match(source, /isFounderContext\(context\)/);
  assert.match(source, /db\.runTransaction/);
  assert.match(source, /collection\("riderProfiles"\)\.doc\(riderId\)/);
  assert.match(source, /collection\("riders"\)\.doc\(riderId\)/);
  assert.match(source, /collection\("riderDocuments"\)\.doc\(documentId\)/);
  assert.match(source, /collection\("riderAuthorityAudit"\)/);
  assert.match(source, /idempotent: true/);
  assert.match(source, /deleteStorageObject/);
});

test("Admin Rider authority supports required certification actions", () => {
  const source = fs.readFileSync("admin-rider-authority.js", "utf8");

  for (const action of [
    "approve",
    "reject",
    "suspend",
    "reactivate",
    "request_more_information",
    "review_document",
    "remove_profile_photo",
    "set_eligibility",
  ]) {
    assert.match(source, new RegExp(`"${action}"`));
  }
});

test("Admin Rider approval performs canonical projection synchronisation", () => {
  const source = fs.readFileSync("admin-rider-authority.js", "utf8");

  assert.match(source, /approvalProjection/);
  assert.match(source, /riderApplicationsFor/);
  assert.match(source, /where\("email", "==", email\)/);
  assert.match(source, /applicationState\.refs\.forEach/);
  assert.match(source, /canonical_rider_approval_sync/);
});

test("Admin canonical Rider repair is admin-only, idempotent and audited", () => {
  const source = fs.readFileSync("admin-rider-authority.js", "utf8");

  assert.match(source, /exports\.adminRepairCanonicalRider = functions\.https\.onCall/);
  assert.match(source, /assertRiderAdmin\(context\)/);
  assert.match(source, /isFounderContext\(context\)/);
  assert.match(source, /db\.runTransaction/);
  assert.match(source, /repair_canonical_rider/);
  assert.match(source, /canonical_rider_repaired/);
  assert.match(source, /riderAuthorityAudit/);
  assert.match(source, /idempotent: true/);
});

test("Admin Rider document review status history stores event objects, not " +
    "nested arrays", () => {
  const source = fs.readFileSync("admin-rider-authority.js", "utf8");

  assert.match(source, /statusHistory: FieldValue\.arrayUnion\(\{/);
  assert.doesNotMatch(source, /statusHistory: FieldValue\.arrayUnion\(\[\{/);
});

test("Admin Rider authority is exported from Firebase Functions index", () => {
  const source = fs.readFileSync("index.js", "utf8");

  assert.match(source, /require\("\.\/admin-rider-authority"\)/);
  assert.match(
      source,
      /exports\.adminReviewRider = adminRiderAuthority\.adminReviewRider/,
  );
  assert.match(
      source,
      /exports\.adminRepairCanonicalRider =\s*adminRiderAuthority\.adminRepairCanonicalRider/,
  );
});
