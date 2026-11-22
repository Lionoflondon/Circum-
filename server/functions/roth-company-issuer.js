"use strict";

const CIRCUM_COMPANY_ID = "CIRCUM";
const ISSUING_ROLES = new Set(["admin", "super_admin", "finance_admin", "operations_admin"]);
const MAX_STAGING_REWARD_PENCE = 1000;

/**
 * CIRCUM's adminUsers collection is tenant-local to the CIRCUM Firebase project.
 * Do not trust token role claims alone: require an active company-side record.
 */
function isAuthorizedCircumIssuer(record) {
  if (!record || String(record.status || "").toLowerCase() !== "active") return false;
  const companyId = record.companyId || record.tenantId;
  if (companyId && String(companyId).toUpperCase() !== CIRCUM_COMPANY_ID) return false;
  const roles = [record.role, record.adminRole, ...(Array.isArray(record.roles) ? record.roles : [])]
      .map((role) => String(role || "").toLowerCase());
  return roles.some((role) => ISSUING_ROLES.has(role));
}

function isValidStagingRewardAmount(amountPence) {
  return Number.isSafeInteger(amountPence) && amountPence >= 1 && amountPence <= MAX_STAGING_REWARD_PENCE;
}

module.exports = {CIRCUM_COMPANY_ID, MAX_STAGING_REWARD_PENCE, isAuthorizedCircumIssuer, isValidStagingRewardAmount};
