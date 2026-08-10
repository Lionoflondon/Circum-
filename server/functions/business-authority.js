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
  "deliveries.notes.modify",
  "deliveries.status", "deliveries.rider_progress", "deliveries.evidence",
  "deliveries.support", "finance.invoices.view", "finance.invoices.download",
  "finance.payments.view", "finance.payments.initiate", "finance.roth.use",
  "finance.reports.export",
  "team.invite", "team.remove", "team.roles.assign", "reports.view",
  "reports.export", "operations.active_deliveries", "operations.incidents",
  "operations.incidents.acknowledge", "operations.support",
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
  return "";
}

function businessAuthority(account = {}, {uid, email, customPermissions = []} = {}) {
  const role = canonicalMemberRole(account, uid, email);
  const member = Boolean(role);
  const permissions = normalizedPermissions(customPermissions);
  const custom = Boolean(role === "custom" && permissions.length);
  const has = (permission) => permissions.includes(permission);
  return {
    member,
    role,
    permissions,
    deliveryAuthorized: Boolean((role && OPERATIONS_ROLES.has(role)) ||
      (custom && ["deliveries.view", "deliveries.status", "operations.active_deliveries"].some(has))),
    reportingAuthorized: Boolean((role && REPORTING_ROLES.has(role)) || (custom && has("reports.view"))),
    financialAuthorized: Boolean((role && FINANCIAL_ROLES.has(role)) ||
      (custom && ["finance.invoices.view", "finance.payments.view"].some(has))),
    ownerOrAdmin: Boolean(role && ["owner", "admin", "manager"].includes(role)),
    legacyOnly: false,
  };
}

function canonicalMember(account = {}, uid, email) {
  const members = Array.isArray(account.teamMembers) ? account.teamMembers : [];
  return members.find((item) => identityMatches(item || {}, uid, email) &&
    !["removed", "rejected", "suspended"].includes(normalized(item.status))) || null;
}

async function resolveBusinessAuthority(db, account = {}, businessId, identity = {}) {
  const uid = normalized(identity.uid);
  let membership = null;
  if (uid) {
    const snap = await db.collection("businessMemberships").doc(`${businessId}_${uid}`).get();
    if (snap.exists && normalized(snap.data().businessId) === normalized(businessId)) membership = snap.data();
  }
  if (!membership && identity.email) {
    const emailSnap = await db.collection("businessMemberships")
        .where("businessId", "==", businessId)
        .where("email", "==", normalized(identity.email))
        .limit(1).get();
    if (!emailSnap.empty) membership = emailSnap.docs[0].data();
  }
  const member = membership && !["removed", "rejected", "suspended"].includes(normalized(membership.status)) ? membership : null;
  let customPermissions = [];
  if (member && normalized(member.role) === "custom" && `${member.customRoleId || ""}`.trim()) {
    const role = await db.collection("businessCustomRoles").doc(`${member.customRoleId}`.trim()).get();
    if (role.exists && normalized(role.data().businessId) === normalized(businessId)) {
      customPermissions = role.data().permissions;
    }
  }
  return businessAuthority({...account, teamMembers: member ? [member] : []}, {...identity, customPermissions});
}

function hasBusinessPermission(authority, permission, systemRoles = []) {
  if (!authority || !authority.member) return false;
  if (systemRoles.includes(authority.role)) return true;
  return authority.role === "custom" && authority.permissions.includes(permission);
}

module.exports = {
  businessAuthority,
  canonicalMemberRole,
  FINANCIAL_ROLES,
  OPERATIONS_ROLES,
  REPORTING_ROLES,
  BUSINESS_PERMISSION_KEYS,
  normalizedPermissions,
  canonicalMember,
  resolveBusinessAuthority,
  hasBusinessPermission,
};
