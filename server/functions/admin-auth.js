/* eslint-disable require-jsdoc */
const functions = require("firebase-functions/v1");
const {ROLE_ALIASES, tokenRoles} = require("./admin-permissions");
const ADMIN_ROLES = new Set(Object.keys(ROLE_ALIASES));

function hasAdminClaim(token = {}) {
  return tokenRoles(token).length > 0;
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
