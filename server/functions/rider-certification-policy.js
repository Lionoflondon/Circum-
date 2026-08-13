/* eslint-disable max-len, require-jsdoc */

const CANONICAL_RIDER_APPLICATION_STATES = [
  "draft",
  "submitted",
  "under_review",
  "needs_information",
  "resubmitted",
  "approved",
  "rejected",
  "suspended",
  "reactivated",
  "archived",
];

const RIDER_APPLICATION_TRANSITIONS = {
  draft: ["submitted", "archived"],
  submitted: ["under_review", "needs_information", "rejected", "archived"],
  under_review: ["needs_information", "approved", "rejected", "suspended", "archived"],
  needs_information: ["resubmitted", "rejected", "archived"],
  resubmitted: ["under_review", "needs_information", "approved", "rejected", "archived"],
  approved: ["suspended", "archived"],
  rejected: ["resubmitted", "archived"],
  suspended: ["reactivated", "archived"],
  reactivated: ["suspended", "archived"],
  archived: [],
};

const DOCUMENT_MATRIX = {
  // Retained for historical records; new onboarding must not offer it.
  electric_bike: ["profile_photo", "identity", "insurance", "right_to_work"],
  motorbike: ["driving_licence", "insurance", "registration_v5c", "mot", "right_to_work", "identity"],
  car: ["driving_licence", "insurance", "registration_v5c", "mot", "right_to_work", "identity"],
  van: ["driving_licence", "insurance", "registration_v5c", "mot", "right_to_work", "identity"],
};

const DOCUMENT_ALIASES = {
  photo: "profile_photo",
  profilephoto: "profile_photo",
  profile_photo: "profile_photo",
  identity: "identity",
  id: "identity",
  passport: "identity",
  drivinglicence: "driving_licence",
  driving_licence: "driving_licence",
  driver_licence: "driving_licence",
  drivers_license: "driving_licence",
  licence: "driving_licence",
  license: "driving_licence",
  insurance: "insurance",
  registration: "registration_v5c",
  vehicle_registration: "registration_v5c",
  v5c: "registration_v5c",
  registration_v5c: "registration_v5c",
  mot: "mot",
  righttowork: "right_to_work",
  right_to_work: "right_to_work",
  rtw: "right_to_work",
};

function text(value) {
  return `${value || ""}`.trim();
}

function lower(value) {
  return text(value).toLowerCase();
}

function normalizeToken(value) {
  return lower(value).replace(/[^a-z0-9]+/g, "_").replace(/^_+|_+$/g, "");
}

function canonicalVehicle(value) {
  const token = normalizeToken(value || "motorbike");
  if (token.includes("van")) return "van";
  if (token.includes("car")) return "car";
  if (token.includes("motor")) return "motorbike";
  if (token.includes("electric") || token.includes("bike") || token.includes("bicycle")) return "electric_bike";
  return "motorbike";
}

function canonicalDocumentId(value) {
  const token = normalizeToken(value);
  return DOCUMENT_ALIASES[token] || token;
}

function requiredDocumentIds(vehicleType) {
  return [...(DOCUMENT_MATRIX[canonicalVehicle(vehicleType)] || DOCUMENT_MATRIX.motorbike)];
}

function documentApproved(document) {
  const status = lower(document && (document.status || document.verificationStatus || document.reviewStatus));
  return status === "approved" || document.approved === true || document.identityApproved === true;
}

function documentIdFrom(document) {
  return canonicalDocumentId(document && (
    document.documentId ||
    document.documentType ||
    document.type ||
    document.category ||
    document.id
  ));
}

function approvedDocumentIds(documents = []) {
  const approved = new Set();
  documents.forEach((document) => {
    if (!documentApproved(document)) return;
    const id = documentIdFrom(document);
    if (id) approved.add(id);
  });
  return approved;
}

function statusApproved(value) {
  const status = lower(value);
  return status === "approved" || status === "verified" || status === "complete" || status === "completed";
}

function riderApproved(profile = {}) {
  return statusApproved(profile.approvalStatus) ||
    statusApproved(profile.verificationStatus) ||
    statusApproved(profile.onboardingStatus) ||
    profile.approved === true ||
    profile.isApproved === true;
}

function activeSuspension(profile = {}) {
  const status = lower(profile.driverStatus || profile.riderStatus || profile.accountStatus || profile.onboardingStatus);
  return status === "suspended" || profile.suspended === true || profile.activeSuspension === true || profile.payoutPaused === true;
}

function payoutReadiness(profile = {}, documents = []) {
  const vehicleType = profile.vehicleType || profile.vehicle || profile.typeOfVehicle;
  const requiredDocuments = requiredDocumentIds(vehicleType);
  const approvedDocs = approvedDocumentIds(documents);
  const missingDocuments = requiredDocuments.filter((id) => !approvedDocs.has(id));
  const riderIsApproved = riderApproved(profile);
  const internalOnboardingComplete = profile.internalOnboardingComplete === true ||
    statusApproved(profile.onboardingStatus) ||
    statusApproved(profile.applicationStatus);
  const identityApproved = profile.identityApproved === true ||
    statusApproved(profile.identityStatus) ||
    approvedDocs.has("identity");
  const requiredDocumentsApproved = missingDocuments.length === 0;
  const stripeAccountExists = Boolean(text(profile.stripeConnectAccountId || profile.stripeAccountId));
  const stripeDetailsSubmitted = profile.stripeDetailsSubmitted === true;
  const chargesEnabled = profile.stripeChargesEnabled === true || profile.chargesEnabled === true;
  const payoutsEnabled = profile.stripePayoutsEnabled === true || profile.payoutsEnabled === true;
  const disabledReason = text(profile.stripeDisabledReason);
  const complianceRestrictions = Array.isArray(profile.stripeRequirementsDue) && profile.stripeRequirementsDue.length > 0;
  const suspended = activeSuspension(profile);
  const checks = {
    riderApproved: riderIsApproved,
    internalOnboardingComplete,
    requiredDocumentsApproved,
    identityApproved,
    stripeAccountExists,
    stripeDetailsSubmitted,
    chargesEnabled,
    payoutsEnabled,
    noDisabledReason: !disabledReason,
    noComplianceRestrictions: !complianceRestrictions,
    noActiveSuspension: !suspended,
  };
  const ready = Object.values(checks).every(Boolean);
  const status = !stripeAccountExists ? "not_started" :
    !stripeDetailsSubmitted ? "in_progress" :
    disabledReason || complianceRestrictions ? "additional_information_required" :
    chargesEnabled && payoutsEnabled && ready ? "fully_payout_ready" :
    payoutsEnabled ? "payouts_enabled" :
    chargesEnabled ? "charges_enabled" :
    "in_progress";
  return {
    ready,
    status,
    checks,
    vehicleType: canonicalVehicle(vehicleType),
    requiredDocuments,
    approvedDocuments: [...approvedDocs],
    missingDocuments,
    disabledReason: disabledReason || null,
  };
}

function canTransitionApplication(from, to) {
  const current = normalizeToken(from || "draft");
  const next = normalizeToken(to);
  return CANONICAL_RIDER_APPLICATION_STATES.includes(current) &&
    CANONICAL_RIDER_APPLICATION_STATES.includes(next) &&
    (current === next || (RIDER_APPLICATION_TRANSITIONS[current] || []).includes(next));
}

module.exports = {
  CANONICAL_RIDER_APPLICATION_STATES,
  RIDER_APPLICATION_TRANSITIONS,
  DOCUMENT_MATRIX,
  canonicalVehicle,
  canonicalDocumentId,
  requiredDocumentIds,
  payoutReadiness,
  canTransitionApplication,
};
