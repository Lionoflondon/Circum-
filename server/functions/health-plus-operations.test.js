/* eslint-disable max-len */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const source = fs.readFileSync(path.join(__dirname, "health-plus-operations.js"), "utf8");
const indexSource = fs.readFileSync(path.join(__dirname, "index.js"), "utf8");

test("Health+ reminder processor is exported and scheduled in London", () => {
  assert.match(indexSource, /exports\.processHealthPlusReminders\s*=\s*healthPlusOperations\.processHealthPlusReminders/);
  assert.match(source, /exports\.processHealthPlusReminders\s*=\s*functions\.pubsub/);
  assert.match(source, /\.schedule\("every 30 minutes"\)/);
  assert.match(source, /\.timeZone\("Europe\/London"\)/);
});

test("Health+ reminders notify admin one day before actual pickup", () => {
  assert.match(source, /const scheduledAt = asDate\(pickup\.scheduledAt \|\| pickup\.preferredPickupAt \|\| pickup\.scheduledPickupDate\)/);
  assert.match(source, /if \(msUntil <= DAY_MS && msUntil > 23 \* HOUR_MS\)/);
  assert.match(source, /await queueHealthAdminNotification\(db, pickup, "pickup_tomorrow", "Health\+ pickup tomorrow"/);
  assert.match(source, /notificationId = `health_admin_\$\{pickup\.id\}_\$\{type\}`/);
  assert.match(source, /recipientRole: "admin"/);
  assert.match(source, /destination: \{[\s\S]*?route: "admin_health_plus"[\s\S]*?healthPickupId: pickup\.id/);
  assert.match(source, /healthPlusUsageEvents"\)\.doc\(notificationId\)\.set/);
});

test("Health+ reminders remain backend-owned and idempotent", () => {
  assert.match(source, /db\.collection\("notifications"\)\.doc\(notificationId\)\.set\(/);
  assert.match(source, /\}, \{merge: true\}\);/);
  assert.doesNotMatch(source, /context\.auth/);
});

test("Health+ monthly usage reset batches active schedules", () => {
  assert.match(source, /exports\.resetHealthPlusMonthlyUsage\s*=\s*functions\.pubsub/);
  assert.match(source, /\.where\("status", "==", "active"\)[\s\S]*?\.orderBy\("__name__"\)[\s\S]*?\.limit\(450\)/);
  assert.match(source, /query\.startAfter\(cursor\)/);
  assert.match(source, /processed \+= snapshot\.size/);
  assert.match(source, /return \{processed\}/);
});
