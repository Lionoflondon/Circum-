/* eslint-disable max-len, require-jsdoc */
const STALE_HEARTBEAT_MS = 2 * 60 * 1000;
const STALE_LOCATION_MS = 2 * 60 * 1000;
const MAX_DISPATCH_ACCURACY_METERS = 100;
const PRESENCE_STATES = Object.freeze({
  FRESH: "ONLINE_FRESH",
  STALE: "ONLINE_STALE",
  OFFLINE: "OFFLINE",
});

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

function blockedReason(profile = {}) {
  if (profile.isFrozen === true || lower(profile.riderStatus) === "frozen") return "Account frozen.";
  if (profile.isSuspended === true || lower(profile.riderStatus) === "suspended") return "Account suspended.";
  if (profile.isClosed === true || lower(profile.riderStatus) === "closed") return "Account closed.";
  if (!riderApproved(profile)) return "Rider approval required.";
  if (!vehicleVerified(profile)) return "Vehicle verification required.";
  return "";
}

function canGoOnline(profile = {}) {
  return blockedReason(profile) === "";
}

function blockedReasonForAccess(profile = {}, founder = false) {
  const terminal = lower(profile.riderStatus);
  if (profile.isFrozen === true || terminal === "frozen") return "Account frozen.";
  if (profile.isSuspended === true || terminal === "suspended") return "Account suspended.";
  if (profile.isClosed === true || terminal === "closed") return "Account closed.";
  return founder ? "" : blockedReason(profile);
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

function presenceState({presence = {}, now = Date.now()}) {
  if (presence.isOnline !== true) return PRESENCE_STATES.OFFLINE;
  const heartbeat = timestampMillis(presence.lastHeartbeatAt);
  if (!heartbeat || now - heartbeat > STALE_HEARTBEAT_MS) return PRESENCE_STATES.STALE;
  return PRESENCE_STATES.FRESH;
}

function dispatchDecision({profile = {}, presence = {}, now = Date.now()}) {
  const state = presenceState({presence, now});
  if (!canGoOnline(profile)) return {allowed: false, presenceState: state, reason: "rider_not_operational"};
  if (state === PRESENCE_STATES.OFFLINE) return {allowed: false, presenceState: state, reason: "offline"};
  if (state === PRESENCE_STATES.STALE) return {allowed: false, presenceState: state, reason: "presence_stale"};
  if (presence.availabilityStatus !== "available") return {allowed: false, presenceState: state, reason: "availability_not_available"};
  if (presence.busy === true) return {allowed: false, presenceState: state, reason: "busy"};
  if (!gpsHealthy({presence, now})) return {allowed: false, presenceState: state, reason: "gps_unhealthy"};
  return {allowed: true, presenceState: state, reason: null};
}

function canReceiveDispatch(args) {
  return dispatchDecision(args).allowed;
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
  PRESENCE_STATES,
  STALE_LOCATION_MS,
  STALE_HEARTBEAT_MS,
  blockedReason,
  blockedReasonForAccess,
  canGoOnline,
  canReceiveDispatch,
  dispatchDecision,
  gpsHealthy,
  nextPresenceOnDelivery,
  presenceState,
  riderApproved,
  vehicleVerified,
};
