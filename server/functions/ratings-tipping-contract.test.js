/* eslint-disable max-len */
"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("fs");

const source = fs.readFileSync(require.resolve("./ratings-tipping"), "utf8");
const index = fs.readFileSync(require.resolve("./index"), "utf8");

test("rating and tip documents are deterministic per delivery", () => {
  assert.match(source, /collection\("driverRatings"\)\.doc\(delivery\.id\)/);
  assert.match(source, /collection\("deliveryTips"\)\.doc\(delivery\.id\)/);
  assert.match(source, /if \(existing\.exists\).*already-exists/s);
});

test("all financial and performance updates use backend transactions", () => {
  assert.match(source, /db\.runTransaction/);
  assert.match(source, /collection\("walletTransactions"\)/);
  assert.match(source, /collection\("riderEarnings"\)/);
  assert.match(source, /collection\("driverPerformanceMetrics"\)/);
  assert.match(source, /idempotencyKey: `delivery_tip_/);
});

test("Roth, Stripe and webhook confirmation share one tip finalizer", () => {
  assert.match(source, /rothLedger\.applyWalletDebit/);
  assert.match(source, /stripe\.paymentIntents\.create/);
  assert.match(source, /stripe\.paymentIntents\.retrieve/);
  assert.match(index, /ratingsTipping\.processStripeTipIntent/);
});

test("rating and tip notifications are deterministic backend events", () => {
  assert.match(source, /collection\("notificationEvents"\)\.doc\(eventId\)/);
  assert.match(source, /rating_sender_\$\{delivery\.id\}/);
  assert.match(source, /rating_rider_\$\{delivery\.id\}/);
  assert.match(source, /tip_rider_\$\{tip\.deliveryId\}/);
});

test("rating moderation is immutable and audited", () => {
  assert.match(source, /collection\("adminAuditLogs"\)/);
  assert.doesNotMatch(source, /starRating:\s*data/);
  assert.match(source, /\["report", "investigate", "hide", "unhide"\]/);
});
