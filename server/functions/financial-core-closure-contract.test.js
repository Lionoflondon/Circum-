/* eslint-disable max-len */
"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const test = require("node:test");

const referrals = fs.readFileSync("referrals.js", "utf8");
const roth = fs.readFileSync("roth-ledger.js", "utf8");
const pricing = fs.readFileSync("sender-booking.js", "utf8");
const policy = fs.readFileSync("delivery-policy.js", "utf8");
const rules = fs.readFileSync("../../firestore.rules", "utf8");

test("referral rewards require App Check and canonical qualifying events", () => {
  for (const callable of ["ensureReferralCode", "attachReferralCode", "activateReferral", "getReferralDashboard"]) {
    assert.match(referrals, new RegExp(`exports\\.${callable} = functions\\.runWith\\(\\{enforceAppCheck: true\\}\\)`));
  }
  assert.match(referrals, /Referral rewards are issued automatically after a verified qualifying activity/);
  assert.match(referrals, /APPROVED_QUALIFYING_EVENTS\.has\(activityType\)/);
  assert.match(referrals, /paymentStatus[\s\S]*?paid[\s\S]*?health_plus_completed/);
  assert.match(referrals, /transactionId: `referral_reward_\$\{rewardIdentity\}_referrer`/);
  assert.match(referrals, /transactionId: `referral_reward_\$\{rewardIdentity\}_referred`/);
});

test("Roth mutation identities reject conflicting replays", () => {
  assert.match(roth, /sameMovement[\s\S]*?Idempotency key is already bound to another Roth movement/);
  assert.match(roth, /const idempotencyKey = `\$\{data\.idempotencyKey \|\| ""\}`\.trim\(\);[\s\S]*?admin_roth_debit_\$\{idempotencyKey\}/);
  assert.match(roth, /adminAuditLogs"\)\.doc\(`roth_\$\{ledgerRef\.id\}`\)/);
});

test("quotes expire and exclude road-charge pass-through from percentage payout", () => {
  assert.match(pricing, /const QUOTE_VALIDITY_MINUTES = 10/);
  assert.match(pricing, /expiresAt: Timestamp\.fromMillis\(Date\.now\(\) \+ QUOTE_VALIDITY_MINUTES/);
  assert.match(pricing, /quoteExpiresAt <= Date\.now\(\)/);
  assert.match(pricing, /riderEligibleFare = money\(Math\.max\(0, subtotal \+ speed - roadChargeAmount\)\)/);
  assert.match(pricing, /roadChargePassThrough: roadChargeAmount/);
  assert.match(pricing, /requiredVehicle = minimumVehicleForWeight\(weightKg\)/);
});

test("no-show collection uses explicit authority before deterministic settlement", () => {
  assert.match(policy, /pendingFinancial\(deliveryId, uid\)/);
  assert.match(policy, /operationsIncidents"\)\.doc\(`no_show_settlement_\$\{deliveryId\}`\)/);
  assert.doesNotMatch(policy, /paymentIntents\.create|applyWalletDebit/);
});

test("financial collections cannot be directly mutated even by generic admin fallback", () => {
  for (const collection of ["wallets", "walletTransactions", "referrals", "referralCodes", "senderBookingQuotes", "senderPaymentSessions", "riderEarningTransactions", "noShowSettlements", "platformSettlementTransactions"]) {
    assert.match(rules, new RegExp(`match /${collection}/\\{[^}]+\\} \\{[\\s\\S]*?allow create, update, delete: if false;`));
  }
  for (const collection of ["riderEarningTransactions", "noShowSettlements", "platformSettlementTransactions"]) {
    assert.match(rules, new RegExp(`'${collection}'`));
  }
});
