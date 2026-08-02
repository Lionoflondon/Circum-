const test = require("node:test");
const assert = require("node:assert/strict");

const {
  approvalProjection,
  cleanVehicle,
  latestApplication,
} = require("./rider-canonical-account");

const approvedDocs = [
  {id: "profile_photo", status: "approved"},
  {id: "identity", status: "approved"},
  {id: "insurance", status: "approved"},
  {id: "right_to_work", status: "approved"},
];

test("canonical rider approval propagates vehicle into every projection", () => {
  const projection = approvalProjection({
    rider: {approvalStatus: "submitted", onboardingStatus: "application_submitted"},
    profile: {verificationStatus: "verification_pending"},
    applications: [{
      id: "RWEB-1",
      vehicleType: "Bike",
      vehicleRegistration: "AB12 CDE",
      updatedAt: "2026-08-01T10:00:00Z",
    }],
    documents: approvedDocs,
    actor: {uid: "admin-1"},
    reason: "Admin approved completed rider onboarding.",
    approve: true,
  });

  assert.equal(projection.ok, true);
  for (const patch of [
    projection.riderPatch,
    projection.profilePatch,
    projection.applicationPatch,
  ]) {
    assert.equal(patch.vehicleType, "bike");
    assert.equal(patch.vehicleRegistration, "AB12 CDE");
    assert.equal(patch.vehicle.type, "bike");
    assert.equal(patch.vehicle.registration, "AB12 CDE");
    assert.equal(patch.vehicle.plateNumber, "AB12 CDE");
  }
  assert.equal(projection.riderPatch.approvalStatus, "approved");
  assert.equal(projection.riderPatch.verificationStatus, "approved");
  assert.equal(projection.riderPatch.onboardingStatus, "approved");
});

test("canonical repair refuses to invent missing vehicle data", () => {
  const projection = approvalProjection({
    rider: {approvalStatus: "approved", verificationStatus: "approved", onboardingStatus: "approved"},
    profile: {},
    applications: [],
    documents: approvedDocs,
    reason: "Repair inconsistent canonical rider record.",
    approve: false,
  });

  assert.equal(projection.ok, false);
  assert.equal(projection.reason, "vehicle_missing");
});

test("canonical repair recalculates dispatch eligibility for already approved riders", () => {
  const projection = approvalProjection({
    rider: {approvalStatus: "approved", verificationStatus: "approved", onboardingStatus: "approved"},
    profile: {},
    applications: [{id: "RWEB-2", vehicleType: "Bike", vehicleRegistration: "XY99 ZZZ"}],
    documents: approvedDocs,
    reason: "Repair inconsistent canonical rider record.",
    approve: false,
  });

  assert.equal(projection.ok, true);
  assert.equal(projection.after.dispatchEligible, true);
  assert.equal(projection.riderPatch.eligibilityState, "eligible");
});

test("canonical repair keeps unapproved riders ineligible", () => {
  const projection = approvalProjection({
    rider: {approvalStatus: "submitted", verificationStatus: "pending", onboardingStatus: "application_submitted"},
    applications: [{id: "RWEB-3", vehicleType: "Bike", vehicleRegistration: "XY99 ZZZ"}],
    documents: approvedDocs,
    reason: "Repair vehicle projection only.",
    approve: false,
  });

  assert.equal(projection.ok, true);
  assert.equal(projection.after.dispatchEligible, false);
  assert.equal(projection.riderPatch.eligibilityState, "ineligible");
});

test("latest application wins vehicle reconciliation deterministically", () => {
  const latest = latestApplication([
    {id: "old", vehicleType: "Car", updatedAt: "2026-01-01T00:00:00Z"},
    {id: "new", vehicleType: "Bike", updatedAt: "2026-08-01T00:00:00Z"},
  ]);
  assert.equal(latest.id, "new");
  assert.deepEqual(cleanVehicle(latest).vehicle.type, "bike");
});
