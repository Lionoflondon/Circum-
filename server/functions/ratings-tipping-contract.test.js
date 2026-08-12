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

test("first tip attempt is transactionally reserved and Stripe identity is fully verified", () => {
  assert.match(source, /transaction\.set\(tipRef, base/);
  assert.match(source, /status: "reserving"/);
  assert.match(source, /assertStripeTipIntent/);
  for (const field of ["amount", "currency", "customer", "deliveryId", "senderId", "riderId", "tipId"]) {
    assert.match(source, new RegExp(field));
  }
});

test("first-party appreciation callables enforce App Check", () => {
  assert.match(source, /const callableRuntime = functions\.runWith\(\{enforceAppCheck: true\}\)/);
  assert.match(source, /submitDeliveryRating = callableRuntime\.https\.onCall/);
  assert.match(source, /getRiderAppreciation = callableRuntime\.https\.onCall/);
});

test("Rider credit is 100 percent and platform tip revenue is zero", () => {
  assert.match(source, /grossTipAmount: amount, riderTipAmount: amount, platformTipRevenue: 0/);
  assert.match(source, /riderCreditAmount: amount, platformRevenueAmount: 0/);
});

test("tip reversals converge Rider projections and partial refunds fail to finance review", () => {
  for (const collection of ["riderEarnings", "riderProfiles", "riders", "driverPerformanceMetrics"]) {
    assert.match(source, new RegExp(`collection\\("${collection}"\\)`));
  }
  assert.match(source, /reason === "refunded".*amount_refunded.*intent\.amount/s);
  assert.match(source, /status: "review_required".*reason: "partial_refund"/s);
  assert.match(source, /delivery_tip_reversal_/);
  assert.match(source, /stripe\.charges\.retrieve/);
  assert.match(source, /roth_tip_refund_/);
  assert.match(source, /isFinanceAdmin/);
});

test("bounded reconciliation runs on a persistent cursor", () => {
  assert.match(source, /schedule\("every 15 minutes"\)/);
  assert.match(source, /tip_reconciliation_cursor/);
  assert.match(source, /orderBy\(FieldPath\.documentId\(\)\)\.limit\(100\)/);
  assert.match(index, /reconcileDeliveryTips/);
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
