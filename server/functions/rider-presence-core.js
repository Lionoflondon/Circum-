/* eslint-disable max-len, require-jsdoc */
const STALE_HEARTBEAT_MS = 2 * 60 * 1000;
const STALE_LOCATION_MS = 5 * 60 * 1000;

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

function canReceiveDispatch({profile = {}, presence = {}, now = Date.now()}) {
  if (!canGoOnline(profile)) return false;
  if (presence.isOnline !== true) return false;
  if (presence.availabilityStatus !== "available") return false;
  if (presence.busy === true) return false;
  if (lower(presence.connectionStatus) === "lost") return false;
  const heartbeat = Number(presence.lastHeartbeatAt || 0);
  if (!heartbeat) return false;
  if (now - heartbeat > STALE_HEARTBEAT_MS) return false;
  const location = presence.currentLocation || {};
  const locationUpdatedAt = Number(location.updatedAt || presence.lastLocationAt || 0);
  if (!locationUpdatedAt || now - locationUpdatedAt > STALE_LOCATION_MS) return false;
  if (!Number.isFinite(Number(location.latitude)) || !Number.isFinite(Number(location.longitude))) return false;
  return true;
}

function connectionStatusForPresence({presence = {}, now = Date.now()}) {
  if (presence.isOnline !== true || presence.availabilityStatus === "offline") return "offline";
  const heartbeat = Number(presence.lastHeartbeatAt || 0);
  if (!heartbeat || now - heartbeat > STALE_HEARTBEAT_MS) return "lost";
  return "connected";
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
  if (afterRider === riderId && ["delivered", "completed"].includes(afterStatus)) {
    return "available";
  }
  if (beforeRider === riderId && afterStatus.startsWith("cancel")) {
    return "available";
  }
  return null;
}

module.exports = {
  STALE_HEARTBEAT_MS,
  STALE_LOCATION_MS,
  blockedReason,
  canGoOnline,
  canReceiveDispatch,
  connectionStatusForPresence,
  nextPresenceOnDelivery,
  riderApproved,
  vehicleVerified,
};
