/* eslint-disable max-len, require-jsdoc */
"use strict";

const REFERRAL_STATUSES = Object.freeze({
  invited: "INVITED",
  signedUp: "SIGNED_UP",
  firstQualifyingDeliveryCompleted: "FIRST_QUALIFYING_DELIVERY_COMPLETED",
  rothAwarded: "ROTH_AWARDED",
  rejected: "REJECTED",
  review: "REVIEW",
});

const REFERRAL_REWARD_SOURCE = "Referral";
const REFERRAL_REWARD_TYPE = "ReferralReward";
const DEFAULT_REFERRAL_REWARD_ROTH = 5;

function normalizeReferralStatus(value) {
  const raw = `${value || ""}`.trim().toLowerCase();
  if (raw === "invited" || raw === "pending") return REFERRAL_STATUSES.invited;
  if (raw === "signed_up" || raw === "signedup") return REFERRAL_STATUSES.signedUp;
  if (raw === "activated" || raw === "completed" || raw === "first_qualifying_delivery_completed") {
    return REFERRAL_STATUSES.firstQualifyingDeliveryCompleted;
  }
  if (raw === "rewarded" || raw === "roth_awarded") return REFERRAL_STATUSES.rothAwarded;
  if (raw === "rejected") return REFERRAL_STATUSES.rejected;
  if (raw === "review") return REFERRAL_STATUSES.review;
  return REFERRAL_STATUSES.invited;
}

function referralRewardFinanceMetadata({
  referralCode,
  inviterUserId,
  referredUserId,
  rewardAmount = DEFAULT_REFERRAL_REWARD_ROTH,
  rewardCurrency = "ROTH",
  rewardStatus,
  qualifyingDeliveryId = null,
  activityType = null,
  activityId = null,
  role = "inviter",
}) {
  const finalStatus = normalizeReferralStatus(rewardStatus);
  return {
    source: REFERRAL_REWARD_SOURCE,
    transactionType: REFERRAL_REWARD_TYPE,
    referralCode: `${referralCode || ""}`.trim().toUpperCase(),
    inviterUserId,
    referredUserId,
    rewardAmount,
    rewardCurrency,
    rewardStatus: finalStatus,
    qualifyingDeliveryId: qualifyingDeliveryId || activityId || null,
    activityType,
    activityId,
    role,
  };
}

module.exports = {
  REFERRAL_STATUSES,
  REFERRAL_REWARD_SOURCE,
  REFERRAL_REWARD_TYPE,
  DEFAULT_REFERRAL_REWARD_ROTH,
  normalizeReferralStatus,
  referralRewardFinanceMetadata,
};
