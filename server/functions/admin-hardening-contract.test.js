const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const assert = require("node:assert/strict");

const read = (name) => fs.readFileSync(path.join(__dirname, name), "utf8");

test("all Admin authority modules use the App Check callable wrapper", () => {
  for (const name of [
    "admin-governance.js",
    "admin-operations-authority.js",
    "admin-rider-authority.js",
    "admin-iris-reference-images.js",
  ]) {
    const source = read(name);
    assert.match(source, /adminCallable\(/, name);
    assert.doesNotMatch(source, /functions\.https\.onCall\(/, name);
  }
  const permissions = read("admin-permissions.js");
  assert.match(permissions, /enforceAppCheck: true/);
  assert.match(permissions, /requireAppCheck\(context\)/);
  assert.match(read("business-payments.js"), /exports\.adminCreateBusinessInvoice = adminCallable/);
  assert.match(read("sender-trust.js"), /exports\.adminUpdateSenderTrust = adminCallable/);
  const communications = read("communication-engine.js");
  for (const name of [
    "startAdminConversation",
    "updateSupportConversationStatus",
    "sendCircumAnnouncement",
    "retryNotificationDelivery",
  ]) assert.match(communications, new RegExp(`exports\\.${name} = adminCallable`), name);
});

test("Admin page queries are bounded, cursor based and permission checked", () => {
  const source = read("admin-operations-authority.js");
  assert.match(source, /exports\.adminQueryPage = adminCallable/);
  assert.match(source, /Math\.min\(Number\(data\.pageSize\) \|\| 50, 50\)/);
  assert.match(source, /query\.startAfter\(cursor\)/);
  assert.match(source, /hasPermission\(actor\.roles, permission\)/);
  assert.match(source, /\.count\(\)\.get\(\)/);
});
