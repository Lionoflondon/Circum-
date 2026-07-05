/* eslint-disable max-len */
const test = require("node:test");
const assert = require("node:assert/strict");
const {
  REFERRAL_STATUSES,
  REFERRAL_REWARD_SOURCE,
  REFERRAL_REWARD_TYPE,
  normalizeReferralStatus,
  referralRewardFinanceMetadata,
} = require("./referral-core");

test("referral lifecycle maps legacy and finance statuses", () => {
  assert.equal(normalizeReferralStatus("pending"), REFERRAL_STATUSES.invited);
  assert.equal(normalizeReferralStatus("SIGNED_UP"), REFERRAL_STATUSES.signedUp);
  assert.equal(normalizeReferralStatus("activated"), REFERRAL_STATUSES.firstQualifyingDeliveryCompleted);
  assert.equal(normalizeReferralStatus("rewarded"), REFERRAL_STATUSES.rothAwarded);
});

test("referral reward metadata is canonical finance transaction metadata", () => {
  const metadata = referralRewardFinanceMetadata({
    referralCode: " jason5 ",
    inviterUserId: "sender_1",
    referredUserId: "sender_2",
    rewardAmount: 5,
    rewardStatus: "rewarded",
    activityType: "sender_completed_paid_booking",
    activityId: "delivery_123",
    role: "inviter",
  });

  assert.equal(metadata.source, REFERRAL_REWARD_SOURCE);
  assert.equal(metadata.transactionType, REFERRAL_REWARD_TYPE);
  assert.equal(metadata.referralCode, "JASON5");
  assert.equal(metadata.inviterUserId, "sender_1");
  assert.equal(metadata.referredUserId, "sender_2");
  assert.equal(metadata.rewardAmount, 5);
  assert.equal(metadata.rewardCurrency, "ROTH");
  assert.equal(metadata.rewardStatus, REFERRAL_STATUSES.rothAwarded);
  assert.equal(metadata.qualifyingDeliveryId, "delivery_123");
});

test("referrals remain finance metadata, not a separate wallet or ledger", () => {
  const metadata = referralRewardFinanceMetadata({
    referralCode: "CIRCUM5",
    inviterUserId: "user_a",
    referredUserId: "user_b",
  });

  assert.equal(metadata.source, "Referral");
  assert.equal(metadata.transactionType, "ReferralReward");
  assert.equal(Object.hasOwn(metadata, "referralWallet"), false);
  assert.equal(Object.hasOwn(metadata, "referralLedger"), false);
  assert.equal(Object.hasOwn(metadata, "referralBalance"), false);
});
