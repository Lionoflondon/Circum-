/* eslint-disable max-len */
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(__dirname, "../..");

test("Sender history loading never mutates delivery lifecycle", () => {
  const source = fs.readFileSync(path.join(
      root,
      "lib/website/shared/circum_website_app.dart",
  ), "utf8");
  assert.equal(source.includes("sender_web_booking_recovery_marked_on_load"), false);
  const loadStart = source.indexOf("Future<void> _loadSenderDeliveries");
  const loadEnd = source.indexOf("void _openSenderDeliveryTracking", loadStart);
  const loader = source.slice(loadStart, loadEnd);
  assert.equal(loader.includes("doc.reference.set("), false);
  assert.equal(loader.includes("recoveryUpdates"), false);
});

test("Admin stale cleanup uses canonical callable and backend writes audit", () => {
  const index = fs.readFileSync(path.join(__dirname, "index.js"), "utf8");
  const backend = fs.readFileSync(path.join(__dirname, "stale-delivery.js"), "utf8");
  assert.match(index, /exports\.resolveStaleDeliveryLock\s*=/);
  assert.match(backend, /stale_active_delivery_reference_repaired/);
  assert.match(backend, /adminAuditLogs/);
  assert.match(backend, /staleDeliveryQueue/);
});

test("goOffline validates the referenced delivery before blocking", () => {
  const source = fs.readFileSync(path.join(__dirname, "rider-presence.js"), "utf8");
  assert.match(source, /evaluateDeliveryLock/);
  assert.match(source, /activeDeliveryId: FieldValue\.delete\(\)/);
  assert.doesNotMatch(source, /presence\.busy === true \|\|\s*text\(presence\.activeDeliveryId\)/);
});

test("stale delivery reconciliation queries only referenced rider presence records", () => {
  const backend = fs.readFileSync(path.join(__dirname, "stale-delivery.js"), "utf8");
  assert.match(backend, /async function referencedPresenceDocs\(db\)/);
  assert.match(backend, /\.where\("activeDeliveryId", ">", ""\)\.limit\(500\)\.get\(\)/);
  assert.match(backend, /\.where\("currentDeliveryId", ">", ""\)\.limit\(500\)\.get\(\)/);
  assert.match(backend, /const presenceDocs = await referencedPresenceDocs\(db\)/);
  assert.doesNotMatch(backend, /db\.collection\("riderPresence"\)\.limit\(500\)\.get\(\)/);
});
