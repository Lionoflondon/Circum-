"use strict";

const FINANCIAL_ROLES = new Set(["owner", "admin", "manager", "finance"]);
const OPERATIONS_ROLES = new Set([
  "owner", "admin", "manager", "operations", "dispatcher", "member",
]);
const REPORTING_ROLES = new Set([
  "owner", "admin", "manager", "operations", "dispatcher", "finance", "viewer",
]);

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

function businessAuthority(account = {}, {uid, email} = {}) {
  const role = canonicalMemberRole(account, uid, email);
  const legacyIds = Array.isArray(account.teamMemberIds) ? account.teamMemberIds : [];
  const legacyMember = legacyIds.some((value) =>
    normalized(value) === normalized(uid) ||
    Boolean(email && normalized(value) === normalized(email)));
  const member = Boolean(role) || legacyMember;
  return {
    member,
    role: role || (legacyMember ? "legacy_member" : ""),
    deliveryAuthorized: Boolean(role && OPERATIONS_ROLES.has(role)),
    reportingAuthorized: Boolean(role && REPORTING_ROLES.has(role)),
    financialAuthorized: Boolean(role && FINANCIAL_ROLES.has(role)),
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
};
