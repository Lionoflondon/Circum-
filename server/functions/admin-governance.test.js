const fs = require("fs");
const path = require("path");
const test = require("node:test");
const assert = require("node:assert/strict");

const source = fs.readFileSync(
    path.join(__dirname, "admin-governance.js"), "utf8",
);
const indexSource = fs.readFileSync(
    path.join(__dirname, "index.js"), "utf8",
);

test("Admin governance actions are callable and exported", () => {
  assert.match(
      source,
      /exports\.adminGovernanceAction = functions\.https\.onCall/,
  );
  assert.match(
      indexSource,
      /exports\.adminGovernanceAction = adminGovernance\.adminGovernanceAction/,
  );
});

test("Admin governance requires Super Admin reason and audit", () => {
  assert.match(source, /requireAdmin\(context/);
  assert.match(source, /Super Admin recovery access is required/);
  assert.match(source, /roles\.has\("super_admin"\)/);
  assert.match(source, /A recovery reason is required/);
  assert.match(source, /adminAuditLogs/);
  assert.match(source, /before/);
  assert.match(source, /after/);
});

test("Admin governance skips saved cards and ephemeral chat state", () => {
  assert.doesNotMatch(source, /paymentMethods/);
  assert.doesNotMatch(source, /setDefaultSenderPaymentMethod/);
  assert.doesNotMatch(source, /typing/);
  assert.doesNotMatch(source, /readReceipt|read receipts/i);
});

test("Admin governance covers every recovery authority group", () => {
  for (const action of [
    "recover_delivery_lifecycle",
    "recover_cancelled_delivery",
    "resolve_duplicate_delivery",
    "recover_orphan_delivery",
    "reassign_rider",
    "force_rider_online",
    "reset_rider_dispatch_state",
    "recover_rider_verification",
    "restore_suspended_rider",
    "recover_sender_booking",
    "recover_sender_wallet_state",
    "recover_business_invoice",
    "recover_business_subscription",
    "recover_health_schedule",
    "recover_gift_matching",
    "recover_gift_story",
    "override_iris_review",
    "resolve_iris_weight_dispute",
    "recover_chat_conversation",
    "place_chat_legal_hold",
    "replay_notification",
    "rebuild_notification_queue",
    "retry_payment_webhook",
    "reconcile_ledger",
    "force_logout",
    "lock_account",
    "reset_mfa",
  ]) {
    assert.match(source, new RegExp(`"${action}"`));
  }
});

test("Admin governance enforces Tier 2 approvals and timeline", () => {
  for (const action of [
    "force_complete_delivery",
    "reopen_delivery",
    "reconcile_ledger",
    "manual_financial_adjustment",
    "override_iris_review",
    "place_chat_legal_hold",
    "lock_account",
    "unlock_account",
    "reassign_rider",
  ]) {
    assert.match(source, new RegExp(`"${action}"`));
  }
  assert.match(source, /TIER_TWO_ACTIONS/);
  assert.match(source, /secondaryApproverId/);
  assert.match(source, /elevatedRoleApproved/);
  assert.match(source, /recoveryTimeline/);
  assert.match(source, /sourceIp/);
  assert.match(source, /sessionId/);
});
