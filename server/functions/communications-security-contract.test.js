const assert = require("node:assert/strict");
const fs = require("node:fs");
const test = require("node:test");

const read = (file) => fs.readFileSync(file, "utf8");

test("payment metadata and product modules cannot select arbitrary push tokens", () => {
  const index = read("index.js");
  const adjustments = read("delivery-adjustments.js");
  const gifts = read("gift-story-automation.js");
  const riderUpdate = read("send-rider-update.js");

  assert.doesNotMatch(index, /metadata\.pushToken|getMessaging\(\)\.send/);
  assert.doesNotMatch(adjustments, /getMessaging|data\.token|fcmToken/);
  assert.doesNotMatch(gifts, /getMessaging|profile\.data\(\)\.code/);
  assert.match(riderUpdate, /recipientId = owner/);
  assert.match(riderUpdate, /recipientId = assigned/);
  assert.match(riderUpdate, /Caller-supplied notification token is not authorized/);
});

test("Business notification recipients come from server-owned workspace membership", () => {
  const source = read("business-access.js");
  assert.match(source, /collection\("businessMemberships"\)/);
  assert.match(source, /where\("businessId", "==", businessId\)/);
  assert.match(source, /where\("status", "==", "active"\)/);
  assert.match(source, /BUSINESS_ADMIN_ROLES\.has/);
  assert.doesNotMatch(source, /business\.managerIds|teamMemberIds/);
  assert.match(source, /recipientId: request\.userId/);
  assert.doesNotMatch(source, /recipientId:\s*email/);
  assert.doesNotMatch(source, /collection\("notifications"\)\.doc\(\)/);
});

test("Health and Gift public notifications omit private domain payloads", () => {
  const gifts = read("gift-story-automation.js");
  const health = read("health-plus.js");
  const publicGiftNotification = gifts.slice(
      gifts.indexOf("async function queueSenderStoryAppNotification"),
      gifts.indexOf("async function processStoryNotification"),
  );
  assert.doesNotMatch(publicGiftNotification, /data:\s*\{[^}]*secureStoryUrl/);
  assert.match(publicGiftNotification, /data: \{giftId, destination:/);
  assert.match(health, /body: "Your prescription pickup has been scheduled\."/);
  assert.doesNotMatch(health, /healthPlusNotifications[\s\S]{0,500}(?:medication|diagnosis|patientPhone)/i);
});

test("communication collections are backend-authored in Firestore rules", () => {
  const rules = read("../../firestore.rules");
  for (const collection of [
    "supportTickets",
    "notifications",
    "chats",
    "healthPlusNotifications",
    "healthPlusUsageEvents",
  ]) {
    assert.match(rules, new RegExp(`match /${collection}/`));
  }
  assert.match(rules, /match \/notifications\/\{notificationId\}[\s\S]*?allow create, update: if false;/);
  assert.match(rules, /match \/chats\/\{chatId\}[\s\S]*?allow create, update: if false;/);
});
