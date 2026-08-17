const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");

const source = fs.readFileSync("referrals.js", "utf8");
const index = fs.readFileSync("index.js", "utf8");

test("direct referral activation is denied and not a reward path", () => {
  const callable = source.slice(source.indexOf("exports.activateReferral ="), source.indexOf("const QUALIFYING_TERMINAL_STATES"));
  assert.match(callable, /exports\.activateReferral = functions\.https\.onCall\(async \(_, context\) =>/);
  assert.match(callable, /Referral activation is only available from verified backend completion events/);
  assert.doesNotMatch(callable, /activateReferralForUser/);
  assert.match(index, /exports\.activateReferral = referrals\.activateReferral;/);
});

test("referral activation requires authoritative owned paid terminal activity", () => {
  assert.match(source, /const QUALIFYING_TERMINAL_STATES = new Set\(\["completed", "delivered"\]\)/);
  assert.match(source, /const PAID_STATES = new Set\(\["paid", "succeeded", "success"\]\)/);
  assert.match(source, /if \(`\$\{ownerId \|\| ""\}` !== referredUserId/);
  assert.match(source, /!QUALIFYING_TERMINAL_STATES\.has\(status\)/);
  assert.match(source, /!PAID_STATES\.has\(payment\)/);
  assert.match(source, /"refunded", "partially_refunded", "failed", "cancelled", "canceled"/);
  assert.doesNotMatch(source, /\["completed", "delivered", "active"\]/);
});

test("all completion triggers route through the same authority", () => {
  for (const trigger of [
    "activateReferralOnDeliveryCompleted",
    "activateReferralOnGiftCompleted",
    "activateReferralOnHealthPlusCompleted",
  ]) assert.match(source, new RegExp(`exports\\.${trigger}`));
  assert.match(source, /return activateReferralForUser\(/);
});
