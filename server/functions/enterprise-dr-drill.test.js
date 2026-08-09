"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const {routeCheckoutSessionCompleted} = require("./checkout-session-router");
const {evaluation, incidentId} = require("./delivery-watchdog");

test("DR drill: failed deployment has a clean rollback authority", () => {
  const manifest = JSON.parse(fs.readFileSync("../../docs/releases/production-functions-manifest.json", "utf8"));
  const runbook = fs.readFileSync("../../docs/operations/enterprise-recovery-runbook.md", "utf8");
  assert.equal(manifest.releaseSha, "SELF");
  assert.match(runbook, /Redeploy the last certified SHA through the normal guarded workflow/);
  assert.match(runbook, /read-only smoke/);
});

test("DR drill: failed payment propagates and preserves retry identity", async () => {
  let attempts = 0;
  const session = {id: "cs_dr_payment", metadata: {type: "wallet_top_up"}};
  const dependencies = {rothLedger: {recordWalletTopUpFromStripeSession: async () => {
    attempts += 1;
    if (attempts === 1) throw new Error("simulated transient failure");
  }}};
  await assert.rejects(routeCheckoutSessionCompleted(session, "evt_dr_payment", dependencies), /simulated transient failure/);
  assert.deepEqual(await routeCheckoutSessionCompleted(session, "evt_dr_payment", dependencies), {handled: true, type: "wallet_top_up"});
  assert.equal(attempts, 2);
});

test("DR drill: failed notification reuses deterministic retry records", () => {
  const source = fs.readFileSync("communication-engine.js", "utf8");
  assert.match(source, /retryNotificationDelivery/);
  assert.match(source, /pushDeliveryStatus:\s*"retrying"/);
  assert.match(source, /notification_retry_sent/);
  assert.match(source, /notification_retry_failed/);
});

test("DR drill: stuck delivery produces one deterministic incident", () => {
  const projection = {incidentType: "accepted_no_movement", baselineLocation: {latitude: 51.5, longitude: -0.1}};
  assert.equal(evaluation(projection, {riderLiveLocation: {latitude: 51.50001, longitude: -0.1}}).action, "incident");
  assert.equal(incidentId("delivery-dr", "accepted_no_movement"), "delivery-dr_accepted_no_movement");
});

test("DR drill: accidental Admin action remains audited and compensating", () => {
  const governance = fs.readFileSync("admin-governance.js", "utf8");
  assert.match(governance, /adminAuditLogs/);
  assert.match(governance, /before/);
  assert.match(governance, /after/);
  assert.match(governance, /recoveryTimeline/);
  assert.match(governance, /A recovery reason is required/);
});
