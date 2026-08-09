"use strict";

const FINANCIAL_ROLES = new Set(["owner", "admin", "manager", "finance"]);
const OPERATIONS_ROLES = new Set([
  "owner", "admin", "manager", "operations", "dispatcher", "member",
]);
const REPORTING_ROLES = new Set([
  "owner", "admin", "manager", "operations", "dispatcher", "finance", "viewer",
]);

const BUSINESS_PERMISSION_KEYS = new Set([
  "deliveries.view", "deliveries.create", "deliveries.cancel",
  "deliveries.status", "deliveries.rider_progress", "deliveries.evidence",
  "deliveries.support", "finance.invoices.view", "finance.invoices.download",
  "finance.payments.view", "finance.roth.use", "finance.reports.export",
  "team.invite", "team.remove", "team.roles.assign", "reports.view",
  "reports.export", "operations.active_deliveries", "operations.incidents",
  "operations.support",
]);

function normalizedPermissions(values) {
  return [...new Set((Array.isArray(values) ? values : [])
      .map(normalized).filter((value) => BUSINESS_PERMISSION_KEYS.has(value)))].sort();
}

function normalized(value) {
  return `${value || ""}`.trim().toLowerCase();
}

function identityMatches(member, uid, email) {
  return normalized(member.userId) === normalized(uid) ||
    Boolean(email && normalized(member.email) === normalized(email));
}

function canonicalMemberRole(account = {}, uid, email) {
  const members = Array.isArray(account.teamMembers) ? account.teamMembers : [];
  const member = members.find((item) =>
    identityMatches(item || {}, uid, email) &&
    !["removed", "rejected", "suspended"].includes(normalized(item.status)));
  if (member) return normalized(member.role || "member");
  if (normalized(account.ownerUid) === normalized(uid) ||
      normalized(account.createdByUserId) === normalized(uid)) return "owner";
  return "";
}

function businessAuthority(account = {}, {uid, email, customPermissions = []} = {}) {
  const role = canonicalMemberRole(account, uid, email);
  const legacyIds = Array.isArray(account.teamMemberIds) ? account.teamMemberIds : [];
  const legacyMember = legacyIds.some((value) =>
    normalized(value) === normalized(uid) ||
    Boolean(email && normalized(value) === normalized(email)));
  const member = Boolean(role) || legacyMember;
  const permissions = normalizedPermissions(customPermissions);
  const custom = Boolean(role === "custom" && permissions.length);
  const has = (permission) => permissions.includes(permission);
  return {
    member,
    role: role || (legacyMember ? "legacy_member" : ""),
    permissions,
    deliveryAuthorized: Boolean((role && OPERATIONS_ROLES.has(role)) ||
      (custom && ["deliveries.view", "deliveries.status", "operations.active_deliveries"].some(has))),
    reportingAuthorized: Boolean((role && REPORTING_ROLES.has(role)) || (custom && has("reports.view"))),
    financialAuthorized: Boolean((role && FINANCIAL_ROLES.has(role)) ||
      (custom && ["finance.invoices.view", "finance.payments.view"].some(has))),
    ownerOrAdmin: Boolean(role && ["owner", "admin", "manager"].includes(role)),
    legacyOnly: !role && legacyMember,
  };
}

module.exports = {
  businessAuthority,
  canonicalMemberRole,
  FINANCIAL_ROLES,
  OPERATIONS_ROLES,
  REPORTING_ROLES,
  BUSINESS_PERMISSION_KEYS,
  normalizedPermissions,
};
