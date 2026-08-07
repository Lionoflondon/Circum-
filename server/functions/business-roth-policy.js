"use strict";

const BUSINESS_ROTH_POLICY = Object.freeze({
  version: "business_roth_v1",
  minimumPurchasePence: 100,
  elevatedApprovalThresholdPence: 1000000,
  maxSinglePurchasePence: 100000000,
});

function parseGbpPence(value) {
  const raw = `${value == null ? "" : value}`.trim().replace(/,/g, "");
  if (!/^\d+(?:\.\d{1,2})?$/.test(raw)) return null;
  const [whole, fraction = ""] = raw.split(".");
  const pence = Number(whole) * 100 + Number(fraction.padEnd(2, "0"));
  if (!Number.isSafeInteger(pence)) return null;
  return pence;
}

function roleForBusiness(account = {}, uid, email = "") {
  const normalizedEmail = `${email}`.trim().toLowerCase();
  const member = (Array.isArray(account.teamMembers) ? account.teamMembers : [])
      .find((item) => {
        const sameUser = `${item.userId || ""}` === `${uid || ""}`;
        const sameEmail = normalizedEmail &&
          `${item.email || ""}`.trim().toLowerCase() === normalizedEmail;
        return (sameUser || sameEmail) &&
          !["removed", "rejected"].includes(`${item.status || ""}`);
      });
  if (member) return `${member.role || "member"}`.trim().toLowerCase();
  if (`${account.ownerUid || account.createdByUserId || ""}` === `${uid || ""}`) {
    return "owner";
  }
  return "";
}

function tierForPence(amountPence) {
  if (amountPence >= BUSINESS_ROTH_POLICY.elevatedApprovalThresholdPence) return "high_value";
  return "routine";
}

function financialAuthority(account, role) {
  const permissions = account.permissions && account.permissions[role];
  return role === "owner" || role === "finance" ||
    (Array.isArray(permissions) && permissions.includes("finance"));
}

function evaluateBusinessRothPurchase({account = {}, uid, email, amountPence}) {
  const role = roleForBusiness(account, uid, email);
  const tier = tierForPence(amountPence);
  const withinPlatformLimit = Number.isSafeInteger(amountPence) &&
    amountPence >= BUSINESS_ROTH_POLICY.minimumPurchasePence &&
    amountPence <= BUSINESS_ROTH_POLICY.maxSinglePurchasePence;
  const authorized = financialAuthority(account, role);
  const confirmationRequired = tier !== "routine";
  const accountLimit = Number.isSafeInteger(account.rothPurchaseLimitPence) ?
    account.rothPurchaseLimitPence : BUSINESS_ROTH_POLICY.maxSinglePurchasePence;
  const withinAccountLimit = amountPence <= accountLimit;
  return {
    allowed: withinPlatformLimit && authorized && withinAccountLimit,
    role,
    tier,
    confirmationRequired,
    policyVersion: BUSINESS_ROTH_POLICY.version,
    effectiveLimitPence: Math.min(
        BUSINESS_ROTH_POLICY.maxSinglePurchasePence,
        accountLimit,
    ),
  };
}

module.exports = {
  BUSINESS_ROTH_POLICY,
  evaluateBusinessRothPurchase,
  parseGbpPence,
  roleForBusiness,
  tierForPence,
};
