/* eslint-disable max-len */
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const profileSource = fs.readFileSync(
    path.join(__dirname, "..", "..", "lib", "app", "sender_mobile", "sender_mobile_profile.dart"),
    "utf8",
);
const trustSource = fs.readFileSync(path.join(__dirname, "sender-trust.js"), "utf8");

test("senderTrustEvents are supplementary profile history, not a profile authority", () => {
  assert.match(profileSource, /collection\('senderTrustEvents'\)/);
  assert.match(profileSource, /profile\.load\.trustEvents/);
  assert.match(profileSource, /profile\.watch\.trustEvents/);
  assert.match(
      profileSource,
      /catch \(error, stack\) \{[\s\S]*profile\.load\.trustEvents[\s\S]*The profile's embedded trust history remains the safe fallback\./,
  );
  assert.match(
      profileSource,
      /catch \(error, stack\) \{[\s\S]*profile\.watch\.trustEvents[\s\S]*The profile's embedded trust history remains the safe fallback\./,
  );
  assert.match(profileSource, /SenderMobileProfileData\.fromSources\([\s\S]*data: profileSnapshot\.data/);
});

test("senderTrustEvents ownership is userId in every backend writer", () => {
  assert.match(trustSource, /doc\(`roth_topup_\$\{stripeSessionId\}`\)[\s\S]*userId: uid/);
  assert.match(trustSource, /const eventRef = db\.collection\("senderTrustEvents"\)\.doc\(\);[\s\S]*userId: uid/);
  assert.match(trustSource, /const eventRef = db\.collection\("senderTrustEvents"\)\.doc\(\);[\s\S]*userId: request\.senderId/);
});
