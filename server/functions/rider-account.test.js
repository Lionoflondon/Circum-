/* eslint-disable max-len */
const test = require("node:test");
const assert = require("node:assert/strict");
const riderAccount = require("./rider-account");

test("public Rider IDs are opaque, stable-format identifiers", () => {
  const ids = new Set(Array.from({length: 100}, () => riderAccount._test.newPublicRiderId()));
  assert.equal(ids.size, 100);
  for (const id of ids) assert.match(id, /^CR-[A-F0-9]{10}$/);
  assert.equal([...ids].some((id) => id.includes("firebase-uid")), false);
});
const fs = require("node:fs");
const path = require("node:path");

const source = fs.readFileSync(path.join(__dirname, "rider-account.js"), "utf8");
const indexSource = fs.readFileSync(path.join(__dirname, "index.js"), "utf8");
const websiteSource = fs.readFileSync(
    path.join(__dirname, "../../lib/website/shared/circum_website_app.dart"),
    "utf8",
);

test("Rider self-service authority callables are exported", () => {
  assert.match(source, /exports\.updateRiderProfile\s*=\s*riderCallable/);
  assert.match(source, /exports\.requestRiderEmailChange\s*=\s*riderCallable/);
  assert.match(source, /exports\.createWeightAdjustedNotification\s*=\s*riderCallable/);
  assert.match(source, /exports\.submitRiderApplication\s*=\s*riderCallable/);
  assert.match(source, /exports\.updateRiderApplicationSection\s*=\s*riderCallable/);
  assert.match(source, /exports\.submitRiderDocument\s*=\s*riderCallable/);
  assert.match(indexSource, /exports\.updateRiderProfile\s*=\s*riderAccount\.updateRiderProfile/);
  assert.match(indexSource, /exports\.requestRiderEmailChange\s*=\s*riderAccount\.requestRiderEmailChange/);
  assert.match(indexSource, /exports\.createWeightAdjustedNotification\s*=\s*riderAccount\.createWeightAdjustedNotification/);
  assert.match(indexSource, /exports\.submitRiderApplication\s*=\s*riderAccount\.submitRiderApplication/);
  assert.match(indexSource, /exports\.updateRiderApplicationSection\s*=\s*riderAccount\.updateRiderApplicationSection/);
  assert.match(indexSource, /exports\.submitRiderDocument\s*=\s*riderAccount\.submitRiderDocument/);
});

test("Rider application submission is non-blocking while lifecycle authority stays server-side", () => {
  const start = source.indexOf("exports.submitRiderApplication");
  const end = source.indexOf("exports.updateRiderApplicationSection", start);
  const body = source.slice(start, end);
  assert.doesNotMatch(body, /data\.rightToWorkConfirmed !== true/);
  assert.doesNotMatch(body, /data\.sealedPackageConsent !== true/);
  assert.match(body, /rightToWorkConfirmed: data\.rightToWorkConfirmed === undefined/);
  assert.match(body, /sealedPackageConsent: data\.sealedPackageConsent === undefined/);
  assert.match(body, /status: "submitted"/);
  assert.match(body, /approvalStatus: "pending"/);
  assert.match(body, /verificationStatus: "pending"/);
  assert.doesNotMatch(body, /dispatchEligible:\s*true/);
});

test("Incomplete application fields and confirmations do not gate submission", () => {
  const start = source.indexOf("exports.submitRiderApplication");
  const end = source.indexOf("exports.updateRiderApplicationSection", start);
  const body = source.slice(start, end);
  assert.doesNotMatch(body, /Name, phone and vehicle type are required/);
  assert.match(body, /status: "submitted"/);
  assert.match(body, /onboardingSubmittedAt: now/);
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

test("Rider profile authority validates canonical adult dates and preserves legal names", () => {
  assert.match(source, /function canonicalDateOfBirth\(value\)/);
  assert.match(source, /Date of birth must use YYYY-MM-DD/);
  assert.match(source, /Date of birth cannot be in the future/);
  assert.match(source, /Riders must be at least 18 years old/);
  assert.match(source, /legalFirstName/);
  assert.match(source, /legalSurname/);
  assert.match(source, /preferredName/);
  assert.match(source, /data\.section/);
});

test("Rider document authority supports validated multipart identity submissions", () => {
  assert.match(source, /function normalizeRiderDocumentFiles\(data, documentType\)/);
  assert.match(source, /Array\.isArray\(data && data\.files\)/);
  assert.match(source, /side === "front"/);
  assert.match(source, /side === "back"/);
  assert.match(source, /Front and back document files are required/);
  assert.match(source, /bytes\.toString\("base64"\)/);
  assert.match(source, /attachments/);
  assert.match(source, /Promise\.all\(uploaded\.map/);
  assert.doesNotMatch(source, /recordRiderDocumentUpload/);
  assert.doesNotMatch(indexSource, /recordRiderDocumentUpload/);
});

test("Rider document authority ignores client review and storage authority fields", () => {
  assert.match(source, /source: "cloud-functions"/);
  assert.match(source, /status: "pending"/);
  assert.match(source, /verificationStatus: "pending"/);
  assert.match(source, /rider_documents\/\$\{rider\.uid\}/);
  assert.doesNotMatch(source, /data\.storagePath/);
  assert.doesNotMatch(source, /data\.downloadUrl/);
  assert.doesNotMatch(source, /data\.reviewedBy/);
  assert.doesNotMatch(source, /data\.approvalStatus/);
});

test("Rider account creation initializes backend-owned rank and trust", () => {
  assert.match(source, /riderRank:\s*"agent"/);
  assert.match(source, /trustPoints:\s*0/);
});

test("profile completion initializes authority defaults only without prior review", () => {
  assert.match(source, /onboardingStatus === "profile_complete" && !existing\.approvalStatus/);
  assert.match(source, /approvalStatus: "pending"/);
  assert.match(source, /verificationStatus: "verification_pending"/);
  assert.match(source, /driverStatus: "offline"/);
  assert.match(source, /rating: "0\.0"/);
  assert.doesNotMatch(source, /existing\.approvalStatus\s*\|\|\s*"pending"[\s\S]{0,120}onboardingStatus === "profile_complete"/);
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
