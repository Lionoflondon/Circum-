/* eslint-disable require-jsdoc */
const functions = require("firebase-functions/v1");

const ROLE_ALIASES = Object.freeze({
  admin: "operations_admin",
  operations: "operations_admin",
  operations_admin: "operations_admin",
  support: "support_agent",
  customer_support: "support_agent",
  support_agent: "support_agent",
  finance: "finance_admin",
  finance_admin: "finance_admin",
  driver_manager: "rider_reviewer",
  rider_manager: "rider_reviewer",
  reviewer: "rider_reviewer",
  rider_reviewer: "rider_reviewer",
  risk: "risk_reviewer",
  risk_reviewer: "risk_reviewer",
  analytics: "analytics_viewer",
  analytics_viewer: "analytics_viewer",
  super_admin: "super_admin",
});

const ROLE_PERMISSIONS = Object.freeze({
  super_admin: ["*"],
  operations_admin: [
    "dashboard.read", "users.read", "riders.read", "deliveries.read",
    "deliveries.manage", "business.read", "business.manage", "gift.read",
    "gift.manage", "health.read", "health.manage", "support.read",
    "support.manage", "ratings.read", "ratings.manage", "riders.review", "audit.read",
  ],
  support_agent: [
    "dashboard.read", "users.read", "riders.read", "deliveries.read",
    "support.read", "support.manage", "ratings.read", "ratings.manage",
    "gift.read", "audit.read",
  ],
  finance_admin: [
    "dashboard.read", "users.read", "riders.read", "deliveries.read",
    "finance.read", "finance.manage", "payments.read", "refunds.manage",
    "payouts.read", "payouts.manage", "business.read", "audit.read",
  ],
  rider_reviewer: [
    "dashboard.read", "riders.read", "riders.review", "deliveries.read",
    "audit.read",
  ],
  risk_reviewer: [
    "dashboard.read", "users.read", "riders.read", "deliveries.read",
    "risk.read", "risk.manage", "ratings.read", "audit.read",
  ],
  analytics_viewer: ["dashboard.read", "analytics.read"],
});

function lower(value) {
  return `${value || ""}`.trim().toLowerCase();
}

function normalizeRole(value) {
  return ROLE_ALIASES[lower(value)] || null;
}

function tokenRoles(token = {}) {
  const raw = [token.role, token.adminRole,
    ...(Array.isArray(token.roles) ? token.roles : [])];
  if (token.admin === true) raw.push("admin");
  if (token.superAdmin === true || token.super_admin === true) raw.push("super_admin");
  return [...new Set(raw.map(normalizeRole).filter(Boolean))];
}

function permissionsForRoles(roles = []) {
  const permissions = new Set();
  for (const role of roles.map(normalizeRole).filter(Boolean)) {
    for (const permission of ROLE_PERMISSIONS[role] || []) permissions.add(permission);
  }
  return [...permissions];
}

function hasPermission(roles, permission) {
  const permissions = permissionsForRoles(roles);
  return permissions.includes("*") || permissions.includes(permission);
}

function requirePermission(actor, permission, message = "Admin permission is required.") {
  if (!hasPermission(actor && actor.roles || [], permission)) {
    throw new functions.https.HttpsError("permission-denied", message);
  }
  return actor;
}

function requireAppCheck(context) {
  if (!context || !context.app || !context.app.appId) {
    throw new functions.https.HttpsError(
        "failed-precondition",
        "Circum security verification is required.",
    );
  }
  return context.app.appId;
}

function adminCallable(handler, options = {}) {
  return functions.runWith({enforceAppCheck: true, timeoutSeconds: 30, ...options})
      .https.onCall((data, context) => {
        requireAppCheck(context);
        return handler(data, context);
      });
}

module.exports = {
  ROLE_ALIASES,
  ROLE_PERMISSIONS,
  normalizeRole,
  tokenRoles,
  permissionsForRoles,
  hasPermission,
  requirePermission,
  requireAppCheck,
  adminCallable,
};
