"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {issueCentralReferralRewards, MAX_STAGING_REWARD_PENCE} = require("./roth-referral-issuer");
const {referralEventConfig} = require("./roth-referral-runtime-config");

test("central referral issuance uses stable per-recipient references and integer pence", async () => {
  const calls = [];
  const client = {issueReward: async (reward) => {
    calls.push(reward);
    return {journalId: `journal-${reward.rewardId}`};
  }};
  const args = {
    client,
    referral: {referrerUserId: "inviter-1", referralCode: "FRIEND"},
    referredUserId: "customer-2",
    rewardAmount: 5,
  };
  const first = await issueCentralReferralRewards(args);
  await issueCentralReferralRewards(args);
  assert.equal(calls.length, 4);
  assert.deepEqual(calls.slice(0, 2), calls.slice(2));
  assert.deepEqual(calls.map(({externalId, rewardId, amountPence}) => ({externalId, rewardId, amountPence})), [
    {externalId: "inviter-1", rewardId: "circum-referral-customer-2-inviter", amountPence: 500},
    {externalId: "customer-2", rewardId: "circum-referral-customer-2-referred", amountPence: 500},
    {externalId: "inviter-1", rewardId: "circum-referral-customer-2-inviter", amountPence: 500},
    {externalId: "customer-2", rewardId: "circum-referral-customer-2-referred", amountPence: 500},
  ]);
  assert.deepEqual(first, {
    amountPence: 500,
    inviterRewardId: "circum-referral-customer-2-inviter",
    referredRewardId: "circum-referral-customer-2-referred",
    inviterJournalId: "journal-circum-referral-customer-2-inviter",
    referredJournalId: "journal-circum-referral-customer-2-referred",
  });
});

test("central referral issuance fails closed for missing identities and out-of-policy synthetic rewards", async () => {
  const client = {issueReward: async () => assert.fail("must not call API")};
  await assert.rejects(issueCentralReferralRewards({client, referral: {referrerUserId: "inviter"}, referredUserId: "customer", rewardAmount: 10.01}), /approved synthetic reward limit/);
  await assert.rejects(issueCentralReferralRewards({client, referral: {referrerUserId: "inviter"}, referredUserId: "customer", rewardAmount: MAX_STAGING_REWARD_PENCE / 100 + 1}), /approved synthetic reward limit/);
  await assert.rejects(issueCentralReferralRewards({client, referral: {}, referredUserId: "customer", rewardAmount: 5}), /identities are invalid/);
});

test("CIRCUM referral event remains production-pinned unless staging is explicitly project-matched", () => {
  assert.deepEqual(referralEventConfig({GCLOUD_PROJECT: "circum-2797c", ROTH_CENTRAL_MODE: "disabled"}), {sourceProject: "circum-2797c", centralStaging: false});
  assert.deepEqual(referralEventConfig({GCLOUD_PROJECT: "circum-stg-71", ROTH_COMPANY_STAGING_PROJECT: "circum-stg-71", ROTH_CENTRAL_MODE: "staging"}), {sourceProject: "circum-stg-71", centralStaging: true});
  assert.throws(() => referralEventConfig({GCLOUD_PROJECT: "circum-2797c", ROTH_COMPANY_STAGING_PROJECT: "circum-2797c", ROTH_CENTRAL_MODE: "staging"}), /isolated staging project/);
  assert.throws(() => referralEventConfig({GCLOUD_PROJECT: "circum-stg-71", ROTH_COMPANY_STAGING_PROJECT: "circum-other-stg", ROTH_CENTRAL_MODE: "staging"}), /isolated staging project/);
});
