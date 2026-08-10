/* eslint-disable max-len */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const source = fs.readFileSync(path.join(__dirname, "health-plus-operations.js"), "utf8");
const indexSource = fs.readFileSync(path.join(__dirname, "index.js"), "utf8");
const operations = require("./health-plus-operations");

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

test("Health+ reminder and recurring processors paginate every bounded batch", () => {
  assert.match(source, /processHealthPlusReminders[\s\S]*?orderBy\(FieldPath\.documentId\(\)\)[\s\S]*?limit\(300\)[\s\S]*?startAfter\(cursor\)/);
  assert.match(source, /generateHealthPlusRecurringBookings[\s\S]*?orderBy\(FieldPath\.documentId\(\)\)[\s\S]*?limit\(300\)[\s\S]*?startAfter\(cursor\)/);
});

test("Health+ recurring instances preserve canonical authority", () => {
  assert.match(source, /pharmacyAddressCanonical: schedule\.pharmacyAddressCanonical/);
  assert.match(source, /deliveryAddressCanonical: schedule\.deliveryAddressCanonical/);
  assert.match(source, /authoritativeRouteFacts: revalidated\.routeFacts/);
  assert.match(source, /authoritativePricing: revalidated\.pricing/);
  assert.match(source, /roadCharges: revalidated\.roadCharges/);
});

test("Health+ recurring generation refreshes route, charges and pricing", async () => {
  const result = await operations._private.revalidateRecurringSchedule({
    pharmacyAddressCanonical: {coordinates: {latitude: 51.5, longitude: -0.1}},
    deliveryAddressCanonical: {coordinates: {latitude: 51.51, longitude: -0.12}},
    medicationWeightKg: 2,
    subscriptionPlan: "core",
    frequency: "monthly",
  }, new Date("2030-01-10T10:00:00Z"), {
    getRouteFacts: async () => ({distanceMiles: 4, routeFactsVersion: "fresh"}),
    evaluateRoadCharges: () => ({customerAmount: 9, components: [{type: "ccz"}]}),
    calculatePricing: (input) => ({amountPence: 2000, distanceMiles: input.distanceMiles}),
  });
  assert.equal(result.eligible, true);
  assert.equal(result.routeFacts.routeFactsVersion, "fresh");
  assert.equal(result.roadCharges.customerAmount, 9);
  assert.equal(result.pricing.amountPence, 2000);
});

test("Health+ recurring generation fails closed for current serviceability review", async () => {
  const result = await operations._private.revalidateRecurringSchedule({
    pharmacyAddressCanonical: {coordinates: {latitude: 51.5, longitude: -0.1}},
    deliveryAddressCanonical: {coordinates: {latitude: 51.51, longitude: -0.12}},
    medicationWeightKg: 2,
    iris: {compliance: {status: "allowed"}, serviceability: {status: "manual_review"}},
  }, new Date("2030-01-10T10:00:00Z"));
  assert.deepEqual(result, {eligible: false, reason: "health_serviceability_review_required"});
});

test("Health+ monthly recurrence uses calendar boundaries instead of 31 days", () => {
  assert.match(source, /function nextCalendarMonth/);
  assert.match(source, /Math\.min\(originalDay, lastDay\)/);
  assert.doesNotMatch(source, /Date\.now\(\) \+ 31 \* 24/);
});
