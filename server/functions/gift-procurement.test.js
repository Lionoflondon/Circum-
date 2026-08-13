"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const {assertTransition, isProcurementCommitted, moneyMinor, procurementEventId, verifyPurchaseEvidence} = require("./gift-procurement")._private;

test("Gift procurement follows the approved bounded state machine", () => {
  assert.doesNotThrow(() => assertTransition("submitted_for_review", "procurement_review"));
  assert.doesNotThrow(() => assertTransition("sourcing", "substitution_required"));
  assert.doesNotThrow(() => assertTransition("purchased", "ready_for_collection"));
  assert.throws(() => assertTransition("submitted_for_review", "purchased"));
  assert.throws(() => assertTransition("delivered", "sourcing"));
});

test("Gift procurement amounts fail closed and event IDs are deterministic", () => {
  assert.equal(moneyMinor(4200), 4200);
  assert.throws(() => moneyMinor(2.5));
  assert.throws(() => moneyMinor(-1));
  assert.equal(procurementEventId("sourcing", "request 1"), "sourcing_request_1");
});

test("Gift procurement remains Admin-owned, App Check protected and budget bounded", () => {
  const source = fs.readFileSync("gift-procurement.js", "utf8");
  assert.match(source, /updateGiftProcurement = functions\.runWith\(\{enforceAppCheck: true\}\)/);
  assert.match(source, /requireAdmin\(context/);
  assert.match(source, /actualPriceMinor > paidBudgetMinor/);
  assert.match(source, /budgetPenceFromGbp/);
  assert.match(source, /paidBudgetMinor < 5000/);
  assert.match(source, /purchase cost exceeds the paid Gift budget/i);
  assert.doesNotMatch(source, /riderEarnings|issueRothCredit|selfCredit/);
});

test("Gift substitution requires explicit Sender ownership and decision", () => {
  const source = fs.readFileSync("gift-procurement.js", "utf8");
  assert.match(source, /gift\.senderId !== senderId/);
  assert.match(source, /pending_sender/);
  assert.match(source, /approved \? "item_confirmed" : "sourcing"/);
  assert.doesNotMatch(source, /approved \? "item_confirmed" : "cancelled"/);
});

test("procurement commitment is the server-authored sourcing boundary", () => {
  assert.equal(isProcurementCommitted({}, "procurement_review"), false);
  assert.equal(isProcurementCommitted({}, "sourcing"), true);
  assert.equal(isProcurementCommitted({procurementCommitted: true}, "procurement_review"), true);
  assert.doesNotThrow(() => assertTransition("procurement_review", "cancelled", false));
  assert.throws(() => assertTransition("sourcing", "cancelled", true), /cannot be cancelled/i);
  assert.throws(() => assertTransition("unavailable", "refunded", true), /cannot be cancelled/i);
});

test("committed Gift recovery cannot use automatic refunds or Rider procurement", () => {
  const source = fs.readFileSync("gift-procurement.js", "utf8");
  const adminSource = fs.readFileSync("admin-operations-authority.js", "utf8");
  const adminClient = fs.readFileSync("../../lib/app/admin/admin_phase1_shell.dart", "utf8");
  const senderClient = fs.readFileSync("../../lib/app/sender_mobile/sender_activity.dart", "utf8");
  assert.match(source, /procurementCommittedAt: FieldValue\.serverTimestamp\(\)/);
  assert.match(source, /eventType: "ProcurementCommitted"/);
  assert.match(source, /SubstitutionRejected/);
  assert.doesNotMatch(source, /scheduled-road-charge-refunds|settleEntitlement|stripe\.refunds|riderEarnings|reimbursement/i);
  const editor = adminSource.slice(adminSource.indexOf("function giftRequestEditorPatch"), adminSource.indexOf("exports.adminSaveGiftRequestEditor"));
  assert.doesNotMatch(editor, /"status"|procurementActualCost/);
  assert.match(adminClient, /httpsCallable\('updateGiftProcurement'\)/);
  assert.match(senderClient, /httpsCallable\('decideGiftSubstitution'\)/);
  assert.match(senderClient, /Ask the Gifts Team to keep sourcing/);
  assert.doesNotMatch(senderClient, /automatic Gift refund|Cancel committed Gift/);
});

test("Gift purchase evidence is verified against immutable Storage metadata", async () => {
  const metadata = {contentType: "image/jpeg", size: "1024", generation: "7", md5Hash: "hash", metadata: {giftId: "gift-1", procurementId: "proc-1", uploadedBy: "admin-1"}};
  const bucket = {file: () => ({exists: async () => [true], getMetadata: async () => [metadata]})};
  const result = await verifyPurchaseEvidence({bucket, giftId: "gift-1", procurementId: "proc-1", storagePath: "giftAssets/gift-1/procurement/proc-1/receipt.jpg", purchaserId: "admin-1"});
  assert.equal(result.generation, "7");
  assert.equal(result.checksum, "hash");
  assert.equal(result.context.giftId, "gift-1");
  await assert.rejects(() => verifyPurchaseEvidence({bucket, giftId: "gift-2", procurementId: "proc-1", storagePath: "giftAssets/gift-1/procurement/proc-1/receipt.jpg", purchaserId: "admin-1"}));
});

test("Gift operations expose workflow age without inventing an SLA", () => {
  const adminClient = fs.readFileSync("../../lib/app/admin/admin_phase1_shell.dart", "utf8");
  assert.match(adminClient, /Time in current stage/);
  assert.match(adminClient, /_giftProcurementAge/);
  assert.doesNotMatch(adminClient, /Gift SLA|must be sourced within|refund after .*hours/i);
});
