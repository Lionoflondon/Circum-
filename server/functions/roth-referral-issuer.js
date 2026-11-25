"use strict";

const MAX_STAGING_REWARD_PENCE = 1000;

/** Issues both sides of a qualifying CIRCUM referral to the central ledger.
 * Stable reward references make a retry safe if the process stops between calls.
 */
async function issueCentralReferralRewards({client, referral, referredUserId, rewardAmount}) {
  if (!client || typeof client.issueReward !== "function") throw new Error("Central ROTH referral client is unavailable.");
  const amountPence = Math.round(Number(rewardAmount) * 100);
  if (!Number.isSafeInteger(amountPence) || amountPence < 1 || amountPence > MAX_STAGING_REWARD_PENCE) {
    throw new Error("CIRCUM staging referral reward exceeds the approved synthetic reward limit.");
  }
  const inviterId = String(referral.referrerUserId || referral.inviterUserId || "");
  const recipientId = String(referredUserId || "");
  if (!/^[A-Za-z0-9_-]{1,128}$/.test(inviterId) || !/^[A-Za-z0-9_-]{1,128}$/.test(recipientId)) {
    throw new Error("CIRCUM referral identities are invalid for central ROTH linking.");
  }
  const base = `circum-referral-${recipientId}`;
  const common = {
    amountPence,
    campaignId: String(referral.referralCode || "referral").slice(0, 128),
    reason: "Verified CIRCUM referral reward after qualifying completed activity",
  };
  const inviter = await client.issueReward({
    ...common,
    externalId: inviterId,
    rewardId: `${base}-inviter`,
  });
  const referred = await client.issueReward({
    ...common,
    externalId: recipientId,
    rewardId: `${base}-referred`,
  });
  return {
    amountPence,
    inviterRewardId: `${base}-inviter`,
    referredRewardId: `${base}-referred`,
    inviterJournalId: inviter && inviter.journalId || null,
    referredJournalId: referred && referred.journalId || null,
  };
}

module.exports = {MAX_STAGING_REWARD_PENCE, issueCentralReferralRewards};
