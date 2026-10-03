"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {accountClosedEmail, verifyAccountClosed} = require("./account-closed-email");
const record = accountClosedEmail({uid: "closure-test", email: "Owner@Example.com", accountType: "sender"});
const closure = {uid: "closure-test", accountType: "sender", status: "ready_for_auth_deletion"};
const dbFor = (value) => ({collection: () => ({doc: () => ({get: async () => ({exists: Boolean(value), data: () => value})})})});
test("closure email uses approved wordmark and final copy with stable ID", () => {
  assert.equal(record.to, "owner@example.com");
  assert.equal(record.notificationId, "account_closed_closure-test");
  assert.match(record.html, /circum_wordmark.png/);
  assert.match(record.text, /No further action is needed/);
  assert.doesNotMatch(record.text + record.html, /Thoughtfully|contact you|next steps/i);
  assert.equal(accountClosedEmail({uid: "u", email: "", accountType: "sender"}), null);
});
test("an existing identity never receives a premature closure confirmation", async () => {
  assert.deepEqual(await verifyAccountClosed({db: dbFor(closure), record, auth: {getUser: async () => ({uid: closure.uid})}}),
      {status: "not_ready", reason: "account_identity_deletion_pending"});
});
test("only authoritative deleted identity makes closure email eligible", async () => {
  const auth = {getUser: async () => {
 throw Object.assign(new Error("gone"), {code: "auth/user-not-found"});
}};
  assert.equal((await verifyAccountClosed({db: dbFor(closure), record, auth})).status, "valid");
  assert.equal((await verifyAccountClosed({db: dbFor(null), record, auth})).status, "suppressed");
  assert.equal((await verifyAccountClosed({db: dbFor(closure), record: {...record, recipientId: "another"}, auth})).status, "suppressed");
});
test("Auth outage retries without sending or treating failure as deletion", async () => {
  const auth = {getUser: async () => {
 throw Object.assign(new Error("unavailable"), {code: "auth/internal-error"});
}};
  assert.equal((await verifyAccountClosed({db: dbFor(closure), record, auth})).status, "not_ready");
});
