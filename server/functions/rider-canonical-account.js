/* eslint-disable max-len, require-jsdoc */

const {FieldValue} = require("firebase-admin/firestore");
const {payoutReadiness} = require("./rider-certification-policy");

const NON_DISPATCH_READINESS_CHECKS = new Set([
  "stripeAccountExists",
  "stripeDetailsSubmitted",
  "chargesEnabled",
  "payoutsEnabled",
  "noDisabledReason",
  "noComplianceRestrictions",
]);

function text(value, max = 500) {
  return `${value || ""}`.trim().slice(0, max);
}

function lower(value, max = 500) {
  return text(value, max).toLowerCase();
}

function cleanVehicle(source = {}) {
  const vehicle = source.vehicle && typeof source.vehicle === "object" ? source.vehicle : {};
  const vehicleType = lower(source.vehicleType || source.typeOfVehicle || vehicle.type, 80);
  const vehicleRegistration = text(source.vehicleRegistration || source.plateNumber || vehicle.registration || vehicle.plateNumber, 40);
  return {
    vehicleType,
    vehicleRegistration,
    vehicle: {
      ...vehicle,
      type: vehicleType,
      registration: vehicleRegistration,
      plateNumber: vehicleRegistration,
    },
  };
}

function latestApplication(applications = []) {
  return applications
      .filter(Boolean)
      .sort((a, b) => timestampMillis(b.updatedAt || b.submittedAt || b.createdAt) -
        timestampMillis(a.updatedAt || a.submittedAt || a.createdAt))[0] || {};
}

function timestampMillis(value) {
  if (!value) return 0;
  if (typeof value.toMillis === "function") return value.toMillis();
  if (value instanceof Date) return value.getTime();
  if (typeof value === "number") return value;
  if (typeof value.seconds === "number") return value.seconds * 1000;
  const parsed = Date.parse(`${value}`);
  return Number.isFinite(parsed) ? parsed : 0;
}

function approved(value) {
  const status = lower(value);
  return status === "approved" || status === "verified" || status === "complete" || status === "completed";
}

function canonicalInput({rider = {}, profile = {}, applications = []}) {
  const application = latestApplication(applications);
  const merged = {
    ...application,
    ...profile,
    ...rider,
  };
  const vehicle = cleanVehicle({
    ...rider,
    ...profile,
    ...application,
  });
  return {application, merged, vehicle};
}

function approvalProjection({rider = {}, profile = {}, applications = [], documents = [], actor = {}, reason = "", approve = false}) {
  const {application, merged, vehicle} = canonicalInput({rider, profile, applications});
  if (!vehicle.vehicleType) {
    return {
      ok: false,
      reason: "vehicle_missing",
      message: "Rider cannot be approved until submitted vehicle details are available.",
    };
  }

  const alreadyApproved = approved(merged.approvalStatus) &&
    approved(merged.verificationStatus) &&
    approved(merged.onboardingStatus);
  const shouldRecalculateEligibility = approve || alreadyApproved;
  const candidate = shouldRecalculateEligibility ? {
    ...merged,
    ...vehicle,
    onboardingStatus: approve ? "approved" : merged.onboardingStatus,
    approvalStatus: approve ? "approved" : merged.approvalStatus,
    verificationStatus: approve ? "approved" : merged.verificationStatus,
    applicationStatus: approve ? "approved" : merged.applicationStatus,
  } : {
    ...merged,
    ...vehicle,
  };
  const readiness = payoutReadiness(candidate, documents);
  const dispatchEligible = shouldRecalculateEligibility ?
    Object.entries(readiness.checks)
        .filter(([key]) => !NON_DISPATCH_READINESS_CHECKS.has(key))
        .every(([, ok]) => ok === true) :
    false;
  const timestamp = FieldValue.serverTimestamp();
  const basePatch = {
    ...vehicle,
    approvalStatus: approve ? "approved" : (merged.approvalStatus || null),
    verificationStatus: approve ? "approved" : (merged.verificationStatus || null),
    onboardingStatus: approve ? "approved" : (merged.onboardingStatus || null),
    documentsVerified: approve ? true : merged.documentsVerified === true,
    vehicleVerified: approve ? true : merged.vehicleVerified === true,
    dispatchEligible,
    riderEligibilityState: dispatchEligible ? "eligible" : "ineligible",
    eligibilityState: dispatchEligible ? "eligible" : "ineligible",
    canonicalRiderVersion: FieldValue.increment(1),
    canonicalRiderSyncedAt: timestamp,
    canonicalRiderSyncReason: reason || (approve ? "admin_approval" : "admin_repair"),
    updatedAt: timestamp,
    ...(approve ? {
      approvedAt: timestamp,
      approvedBy: actor.uid || null,
      adminApprovalStatus: "approved",
      driverStatus: "active",
    } : {}),
  };
  const applicationPatch = {
    ...vehicle,
    ...(approve ? {
      status: "approved",
      approvalStatus: "approved",
      verificationStatus: "approved",
      onboardingStatus: "approved",
      approvedAt: timestamp,
      approvedBy: actor.uid || null,
    } : {}),
    canonicalRiderSyncedAt: timestamp,
    updatedAt: timestamp,
  };
  const needsInformationFields = Array.isArray(merged.needsInformationFields) ?
    merged.needsInformationFields.filter((field) => lower(field) !== "vehicle") : [];
  if (vehicle.vehicleType) {
    basePatch.needsInformationFields = needsInformationFields.length ?
      needsInformationFields : FieldValue.delete();
    applicationPatch.needsInformationFields = needsInformationFields.length ?
      needsInformationFields : FieldValue.delete();
  }
  return {
    ok: true,
    applicationId: application.id || application.applicationId || null,
    readiness,
    riderPatch: basePatch,
    profilePatch: basePatch,
    applicationPatch,
    before: {
      rider: snapshotFields(rider),
      profile: snapshotFields(profile),
      application: snapshotFields(application),
    },
    after: {
      vehicleType: vehicle.vehicleType,
      vehicleRegistration: vehicle.vehicleRegistration,
      approvalStatus: basePatch.approvalStatus,
      verificationStatus: basePatch.verificationStatus,
      onboardingStatus: basePatch.onboardingStatus,
      dispatchEligible,
      eligibilityState: basePatch.eligibilityState,
    },
  };
}

function snapshotFields(value = {}) {
  return {
    approvalStatus: value.approvalStatus || null,
    verificationStatus: value.verificationStatus || null,
    onboardingStatus: value.onboardingStatus || null,
    vehicleType: value.vehicleType || null,
    vehicleRegistration: value.vehicleRegistration || value.plateNumber || null,
    dispatchEligible: value.dispatchEligible === true,
    needsInformationFields: Array.isArray(value.needsInformationFields) ? value.needsInformationFields : [],
  };
}

module.exports = {
  approvalProjection,
  cleanVehicle,
  latestApplication,
};
