/* eslint-disable require-jsdoc */
const functions = require("firebase-functions/v1");

const ADMIN_ROLES = new Set([
  "admin",
  "super_admin",
  "operations_admin",
  "support_agent",
  "finance_admin",
  "driver_manager",
]);

function clean(value) {
  return `${value || ""}`.trim().toLowerCase();
}

function hasAdminClaim(token = {}) {
  const roles = Array.isArray(token.roles) ? token.roles.map(clean) : [];
  return token.admin === true || token.superAdmin === true ||
    token.super_admin === true ||
    [clean(token.adminRole), clean(token.role), ...roles]
        .some((role) => ADMIN_ROLES.has(role));
}

function requireAdmin(context, message = "Administrator access is required.") {
  if (!context || !context.auth || !context.auth.uid) {
    throw new functions.https.HttpsError("unauthenticated", "Sign in first.");
  }
  if (!hasAdminClaim(context.auth.token || {})) {
    throw new functions.https.HttpsError("permission-denied", message);
  }
  return context.auth.uid;
}

module.exports = {
  ADMIN_ROLES,
  hasAdminClaim,
  requireAdmin,
};
