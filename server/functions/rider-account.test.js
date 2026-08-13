/* eslint-disable max-len */
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const source = fs.readFileSync(path.join(__dirname, "rider-account.js"), "utf8");
const indexSource = fs.readFileSync(path.join(__dirname, "index.js"), "utf8");
const websiteSource = fs.readFileSync(
    path.join(__dirname, "../../lib/website/shared/circum_website_app.dart"),
    "utf8",
);

test("Rider self-service authority callables are exported", () => {
  assert.match(source, /exports\.updateRiderProfile\s*=\s*functions\.https\.onCall/);
  assert.match(source, /exports\.requestRiderEmailChange\s*=\s*functions\.https\.onCall/);
  assert.match(source, /exports\.createWeightAdjustedNotification\s*=\s*functions\.https\.onCall/);
  assert.match(source, /exports\.submitRiderApplication\s*=\s*functions\.https\.onCall/);
  assert.match(source, /exports\.updateRiderApplicationSection\s*=\s*functions\.https\.onCall/);
  assert.match(source, /exports\.submitRiderDocument\s*=\s*functions\.https\.onCall/);
  assert.match(indexSource, /exports\.updateRiderProfile\s*=\s*riderAccount\.updateRiderProfile/);
  assert.match(indexSource, /exports\.requestRiderEmailChange\s*=\s*riderAccount\.requestRiderEmailChange/);
  assert.match(indexSource, /exports\.createWeightAdjustedNotification\s*=\s*riderAccount\.createWeightAdjustedNotification/);
  assert.match(indexSource, /exports\.submitRiderApplication\s*=\s*riderAccount\.submitRiderApplication/);
  assert.match(indexSource, /exports\.updateRiderApplicationSection\s*=\s*riderAccount\.updateRiderApplicationSection/);
  assert.match(indexSource, /exports\.submitRiderDocument\s*=\s*riderAccount\.submitRiderDocument/);
});

test("Rider self-service authority validates auth ownership documents and audit", () => {
  assert.match(source, /function requireRider\(context\)/);
  assert.match(source, /context\.auth\.uid/);
  assert.match(source, /ALLOWED_DOCUMENT_TYPES/);
  assert.match(source, /ALLOWED_CONTENT_TYPES/);
  assert.match(source, /MAX_DOCUMENT_BYTES/);
  assert.match(source, /rider_documents\/\$\{rider\.uid\}/);
  assert.match(source, /riderOnboardingEvents/);
  assert.match(source, /riderApplicationIdempotency/);
  assert.match(source, /collection\("riderApplications"\)\.doc\(rider\.uid\)/);
  assert.match(source, /ALLOWED_APPLICATION_SECTIONS/);
  assert.match(source, /ALLOWED_SECTION_STATUSES/);
  assert.match(source, /cleanApplicationSection\(data\.section\)/);
  assert.match(source, /cleanSectionStatus\(data\.status \|\| "in_progress"\)/);
  assert.doesNotMatch(source, /const status = cleanDocumentType\(data\.status/);
  assert.match(source, /sectionStatus/);
  assert.match(source, /rider_application_section_updated/);
  assert.match(source, /data\.fullName \|\| existing\.fullName/);
  assert.match(source, /data\.vehicleType \|\| existing\.vehicleType/);
  assert.match(source, /function applicationPatchFromProfile/);
  assert.match(source, /transaction\.set\(applicationRef/);
  assert.match(source, /\{merge: true\}/);
  assert.match(source, /sectionStatus:\s*\{\[section\]:\s*"submitted"\}/);
  assert.match(source, /data\.phoneNumber \|\| data\.phone \|\| existing\.phoneNumber/);
  assert.match(source, /data\.homeAddress \|\| data\.address \|\| existing\.homeAddress/);
  assert.match(source, /approvalStatus:\s*existing\.approvalStatus \|\| "pending"/);
  assert.match(source, /Delivery is not assigned to this Rider/);
  assert.match(source, /runTransaction/);
});

test("Rider Application Centre authority requires App Check", () => {
  const start = source.indexOf("function requireRider");
  const end = source.indexOf("\n}\n", start) + 3;
  const guard = source.slice(start, end);
  assert.match(guard, /context\.app/);
  assert.match(guard, /Security verification is required/);
});

test("Rider account creation initializes backend-owned rank and trust", () => {
  assert.match(source, /riderRank:\s*"agent"/);
  assert.match(source, /trustPoints:\s*0/);
});

test("Rider Web routes operational self-service mutations through callables", () => {
  assert.match(websiteSource, /httpsCallable\('updateRiderProfile'\)/);
  assert.match(websiteSource, /httpsCallable\('requestRiderEmailChange'\)/);
  assert.match(websiteSource, /httpsCallable\('submitRiderApplication'\)/);
  assert.match(websiteSource, /httpsCallable\('submitRiderDocument'\)/);
  for (const method of [
    "_changeRiderEmail",
    "_saveRiderProfile",
    "_uploadRiderDocument",
    "_submit",
  ]) {
    const start = websiteSource.indexOf(`Future<void> ${method}`);
    assert.notEqual(start, -1, `${method} exists`);
    const nextMethod = websiteSource.indexOf("\n  Future<", start + 1);
    const body = websiteSource.slice(
        start,
        nextMethod === -1 ? start + 2400 : nextMethod,
    );
    assert.doesNotMatch(body, /collection\('riderApplications'\)[\s\S]{0,160}\.(?:set|update|delete)\(/);
    assert.doesNotMatch(body, /collection\('riderDocuments'\)[\s\S]{0,160}\.(?:set|update|delete)\(/);
    assert.doesNotMatch(body, /collection\('riderProfiles'\)[\s\S]{0,220}\.(?:set|update|delete)\(/);
    assert.doesNotMatch(body, /collection\('riders'\)[\s\S]{0,160}\.(?:set|update|delete)\(/);
  }
});
