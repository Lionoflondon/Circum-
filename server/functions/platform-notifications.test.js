/* eslint-disable max-len */
const test = require("node:test");
const assert = require("node:assert/strict");
const {
  giftNotificationRecord,
  giftNotificationRecordsForTransition,
  _private,
} = require("./platform-notifications");
const fs = require("node:fs");
const path = require("node:path");

test("Gifts in-app notification record is always created", () => {
  const record = giftNotificationRecord({
    userId: "sender-1",
    email: "sender@example.com",
    giftId: "gift-1",
    giftType: "send_to_someone",
    eventType: "payment_succeeded",
    title: "Payment confirmed",
    body: "Your gift is secured.",
    channel: "in_app",
    createdAt: "now",
  });
  assert.equal(record.notificationId, "gift-1_payment_succeeded_in_app");
  assert.equal(record.deliveryStatus, "pending");
  assert.equal(record.channel, "in_app");
});

test("Gifts email and push mark skipped when providers are not configured", () => {
  const email = giftNotificationRecord({
    userId: "sender-1",
    email: "sender@example.com",
    giftId: "gift-1",
    giftType: "campaign",
    eventType: "campaign_match_found",
    title: "Match found",
    body: "A policy-safe match has been found.",
    channel: "email",
  });
  const push = giftNotificationRecord({
    userId: "sender-1",
    email: "sender@example.com",
    giftId: "gift-1",
    giftType: "campaign",
    eventType: "campaign_match_found",
    title: "Match found",
    body: "A policy-safe match has been found.",
    channel: "push",
  });
  assert.equal(email.deliveryStatus, "skipped");
  assert.equal(email.failureReason, "email_not_configured");
  assert.equal(push.deliveryStatus, "skipped");
  assert.equal(push.failureReason, "push_not_configured");
});

test("Gifts transition creates all channel records without private data", () => {
  const records = giftNotificationRecordsForTransition({
    userId: "sender-1",
    email: "sender@example.com",
    giftId: "gift-1",
    giftType: "anonymous",
    eventType: "story_unlocked",
    title: "Gift Story unlocked",
    body: "Your Gift Story is ready.",
    createdAt: "now",
  });
  assert.equal(records.length, 3);
  assert.deepEqual(records.map((record) => record.channel), ["in_app", "email", "push"]);
  assert.equal(records.some((record) => "matchedParticipantBudget" in record), false);
  assert.equal(records.some((record) => "internalNotes" in record), false);
});

test("Gift request statuses map to backend-owned notification events", () => {
  assert.deepEqual(
      _private.giftStatusNotification("submitted_for_review"),
      ["gift_submitted", "Gift submitted", "Your gift request has been sent to the Circum team."],
  );
  assert.deepEqual(
      _private.giftStatusNotification("paid_waiting_for_match"),
      ["campaign_waiting_for_match", "Gift match requested", "We are looking for a compatible gift match."],
  );
  assert.equal(_private.giftStatusNotification("draft"), null);
});

test("unclaimed delivery reminder reuses the rider profile snapshot per run", () => {
  const source = fs.readFileSync(path.join(__dirname, "platform-notifications.js"), "utf8");
  assert.match(source, /let riderProfileDocs = null;/);
  assert.match(source, /if \(!riderProfileDocs\) \{/);
  assert.match(source, /riderProfileDocs = await onlineCandidateRiderRecords\(db\);/);
  assert.match(source, /dispatchCandidateDecision\(record, delivery\)/);
});

test("unclaimed delivery escalation retries dispatch for unassigned open deliveries", () => {
  const source = fs.readFileSync(path.join(__dirname, "platform-notifications.js"), "utf8");
  assert.match(source, /dispatchDeliveryRequest\(\{/);
  assert.match(source, /source: "escalateUnclaimedDeliveries"/);
  assert.match(source, /if \(!assignedRiderId\(delivery\) && stage >= 1\)/);
});

test("delivery creation notifies merged online rider candidates", () => {
  const source = fs.readFileSync(path.join(__dirname, "platform-notifications.js"), "utf8");
  assert.match(source, /async function onlineCandidateRiderRecords\(db\)/);
  assert.match(source, /collection\("riderPresence"\)/);
  assert.match(source, /where\("isOnline", "==", true\)/);
  assert.match(source, /collection\("riders"\)/);
  assert.match(source, /collection\("riderProfiles"\)/);
  assert.match(source, /where\("status", "in", \["online", "available"\]\)/);
  assert.match(source, /where\("availabilityStatus", "in", \["online", "available"\]\)/);
  assert.match(source, /const riders = await onlineCandidateRiderRecords\(db\);/);
  assert.match(source, /collection\("dispatchInspections"\)/);
  assert.doesNotMatch(source, /const riders = await getFirestore\(\)\.collection\("riderProfiles"\)\.get\(\);/);
});

test("dispatch candidate decision rejects offline presence even when profile is stale online", () => {
  const decision = _private.dispatchCandidateDecision({
    id: "rider-1",
    profile: {
      approvalStatus: "approved",
      vehicleStatus: "approved",
      status: "online",
      availabilityStatus: "available",
    },
    rider: {},
    presence: {
      isOnline: false,
      availabilityStatus: "offline",
      busy: false,
    },
  }, {iris: {recommendedVehicle: "motorbike"}});
  assert.equal(decision.eligible, false);
  assert.equal(decision.reason, "offline");
});

test("dispatch candidate decision honours an active founder test waiver", () => {
  const now = Date.now();
  const decision = _private.dispatchCandidateDecision({
    id: "founder-rider",
    profile: {
      approvalStatus: "submitted",
      vehicleStatus: "pending",
      founderTestAccount: {
        active: true,
        accountType: "internal_tester",
        waivers: ["dispatch_eligibility"],
      },
    },
    rider: {vehicleType: "bike"},
    presence: {
      isOnline: true,
      availabilityStatus: "available",
      busy: false,
      lastHeartbeatAt: now,
      gpsStatus: "active",
      currentLocation: {
        latitude: 51.5072,
        longitude: -0.1276,
        accuracyMeters: 20,
        updatedAt: now,
      },
    },
  }, {vehicleType: "bike"}, now);
  assert.equal(decision.eligible, true);
  assert.equal(decision.reason, "eligible");
});
