/* eslint-disable max-len, require-jsdoc */
const STALE_HEARTBEAT_MS = 2 * 60 * 1000;
const STALE_LOCATION_MS = 2 * 60 * 1000;
const MAX_DISPATCH_ACCURACY_METERS = 100;

function text(value) {
  return `${value || ""}`.trim();
}

function lower(value) {
  return text(value).toLowerCase();
}

function bool(value) {
  return value === true || lower(value) === "true" || lower(value) === "approved";
}

function vehicleVerified(profile = {}) {
  const vehicle = profile.vehicle || profile.vehicleDetails || {};
  return bool(profile.vehicleApproved) ||
    bool(profile.vehicleVerified) ||
    lower(profile.vehicleStatus) === "approved" ||
    lower(vehicle.status) === "approved" ||
    bool(vehicle.approved);
}

function riderApproved(profile = {}) {
  const status = lower(profile.riderStatus || profile.onboardingStatus || profile.approvalStatus || profile.verificationStatus);
  return status === "active" ||
    status === "approved" ||
    status === "payouts_enabled" ||
    bool(profile.identityApproved) && bool(profile.documentsApproved);
}

function founderDispatchOverride(profile = {}) {
  const designation = profile.founderTestAccount || profile.internalTestAccount || {};
  if (designation.active !== true) return false;
  const accountType = lower(designation.accountType || designation.type);
  if (!new Set(["internal_tester", "qa_account", "demo_account"]).has(accountType)) return false;
  const waivers = Array.isArray(designation.waivers) ? designation.waivers.map(lower) : [];
  return waivers.includes("dispatch_eligibility");
}

function blockedReason(profile = {}) {
  if (profile.isFrozen === true || lower(profile.riderStatus) === "frozen") return "Account frozen.";
  if (profile.isSuspended === true || lower(profile.riderStatus) === "suspended") return "Account suspended.";
  if (profile.isClosed === true || lower(profile.riderStatus) === "closed") return "Account closed.";
  if (founderDispatchOverride(profile)) return "";
  if (!riderApproved(profile)) return "Rider approval required.";
  if (!vehicleVerified(profile)) return "Vehicle verification required.";
  return "";
}

function canGoOnline(profile = {}) {
  return blockedReason(profile) === "";
}

function blockedReasonForAccess(profile = {}, founder = false) {
  return founder ? "" : blockedReason(profile);
}

function canReceiveDispatch({profile = {}, presence = {}, now = Date.now()}) {
  if (!canGoOnline(profile)) return false;
  if (presence.isOnline !== true) return false;
  if (presence.availabilityStatus !== "available") return false;
  if (presence.busy === true) return false;
  const heartbeat = Number(presence.lastHeartbeatAt || 0);
  if (!heartbeat) return false;
  if (now - heartbeat > STALE_HEARTBEAT_MS) return false;
  return gpsHealthy({presence, now});
}

function timestampMillis(value) {
  if (!value) return 0;
  if (typeof value === "number") return value;
  if (value instanceof Date) return value.getTime();
  if (typeof value.toMillis === "function") return value.toMillis();
  if (typeof value.seconds === "number") {
    return value.seconds * 1000 + Math.floor((value.nanoseconds || 0) / 1000000);
  }
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function gpsHealthy({presence = {}, now = Date.now()}) {
  const blockedStatuses = new Set([
    "disabled",
    "denied",
    "restricted",
    "unavailable",
    "stale",
    "mocked",
    "suspect",
    "pooraccuracy",
    "poorgpsaccuracy",
    "permissionrequired",
    "locationservicesdisabled",
  ]);
  const gpsStatus = lower(presence.gpsStatus || presence.locationStatus || presence.trackingStatus);
  if (blockedStatuses.has(gpsStatus)) return false;
  const location = presence.currentLocation || presence.location || presence.riderLiveLocation || {};
  if (location.mocked === true || location.isMocked === true || presence.mockedLocation === true) return false;
  const latitude = Number(location.latitude);
  const longitude = Number(location.longitude);
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) return false;
  const accuracy = Number(location.accuracyMeters ?? location.accuracy);
  if (!Number.isFinite(accuracy) || accuracy <= 0 || accuracy > MAX_DISPATCH_ACCURACY_METERS) return false;
  const updatedAt = timestampMillis(location.updatedAt || location.clientRecordedAt || presence.lastLocationAt);
  if (!updatedAt) return false;
  return now - updatedAt <= STALE_LOCATION_MS;
}

function nextPresenceOnDelivery({before = {}, after = {}, riderId}) {
  const beforeRider = text(before.riderId || before.assignedRiderId || before.driverId || before.assignedDriverId);
  const afterRider = text(after.riderId || after.assignedRiderId || after.driverId || after.assignedDriverId);
  if (!riderId || riderId !== afterRider && riderId !== beforeRider) return null;

  const beforeStatus = lower(before.status || before.state || before.deliveryStage);
  const afterStatus = lower(after.status || after.state || after.deliveryStage);
  if (afterRider === riderId && beforeStatus !== "accepted" && afterStatus === "accepted") {
    return "busy";
  }
  if (afterRider === riderId && [
    "delivered", "completed", "cancelled", "canceled", "cancelled_admin",
    "admin_removed_stale", "archived_stale", "archived_expired", "expired",
  ].includes(afterStatus)) {
    return "available";
  }
  if (beforeRider === riderId && afterStatus.startsWith("cancel")) {
    return "available";
  }
  return null;
}

module.exports = {
  MAX_DISPATCH_ACCURACY_METERS,
  STALE_LOCATION_MS,
  STALE_HEARTBEAT_MS,
  blockedReason,
  blockedReasonForAccess,
  canGoOnline,
  canReceiveDispatch,
  founderDispatchOverride,
  gpsHealthy,
  nextPresenceOnDelivery,
  riderApproved,
  vehicleVerified,
};
