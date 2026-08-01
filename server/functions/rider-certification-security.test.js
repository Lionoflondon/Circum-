/* eslint-disable max-len */
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const storageRules = fs.readFileSync(
    path.join(__dirname, "..", "..", "storage.rules"),
    "utf8",
);
const riderAccount = fs.readFileSync(
    path.join(__dirname, "rider-account.js"),
    "utf8",
);
const adminAuthority = fs.readFileSync(
    path.join(__dirname, "admin-rider-authority.js"),
    "utf8",
);

test("rider document storage paths are not client-writable", () => {
  for (const collection of ["riderDocuments", "riders", "vehicleDocuments"]) {
    assert.match(storageRules, new RegExp(`match /${collection}/`));
  }
  assert.doesNotMatch(
      storageRules,
      /allow create, update: if \(isAdmin\(\) \|\| \(signedIn\(\) && request\.auth\.uid == riderId\)\) && isSafeUpload\(\);/,
  );
  assert.match(storageRules, /allow create, update: if isAdmin\(\) && isSafeUpload\(\);/);
});

test("rider document uploads use backend callable and canonical matrix", () => {
  assert.match(riderAccount, /exports\.submitRiderDocument = functions\.https\.onCall/);
  assert.match(riderAccount, /canonicalDocumentId/);
  assert.match(riderAccount, /DOCUMENT_MATRIX/);
  assert.match(riderAccount, /source: "cloud-functions"/);
});

test("admin rider approval enforces application compliance without blocking Stripe self-service", () => {
  assert.match(adminAuthority, /payoutReadiness/);
  assert.match(adminAuthority, /action === "approve"/);
  assert.match(adminAuthority, /overrideCompliance/);
  assert.match(adminAuthority, /isSuperAdminContext/);
  assert.match(adminAuthority, /if \(!overrideCompliance \|\| !isSuperAdminContext\(context\)\)/);
  assert.match(adminAuthority, /mandatory application, identity and document requirements pass/);
  assert.match(adminAuthority, /Super Admin compliance override requires a detailed reason/);
  assert.match(adminAuthority, /stripeAccountExists/);
  assert.match(adminAuthority, /payoutsEnabled/);
  assert.match(adminAuthority, /patch\.complianceOverride = true/);
  assert.match(adminAuthority, /patch\.complianceOverrideBy = actor\.uid/);
  assert.match(adminAuthority, /patch\.complianceOverrideReason = reason/);
  assert.match(adminAuthority, /patch\.complianceOverrideAt = FieldValue\.serverTimestamp\(\)/);
  assert.match(adminAuthority, /complianceOverrideFailedChecks/);
});
