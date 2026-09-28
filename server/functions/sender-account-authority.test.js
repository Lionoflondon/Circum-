/* eslint-disable max-len */
const fs = require("fs");
const test = require("node:test");
const assert = require("node:assert/strict");

const source = fs.readFileSync("sender-account.js", "utf8");

test("ensureSenderAccount emits lifecycle diagnostics around the transaction", () => {
  assert.match(source, /function senderProfileLog\(event, payload = \{\}\)/);
  assert.match(source, /subsystem: "sender_profile"/);
  assert.match(source, /senderProfileLog\("ensure_begin"/);
  assert.match(source, /senderProfileLog\("ensure_transaction_read"/);
  assert.match(source, /senderProfileLog\("ensure_complete"/);
  assert.match(source, /userExists: userSnap\.exists/);
  assert.match(source, /riderExists: riderSnap\.exists/);
  assert.match(source, /adminExists: adminSnap\.exists/);
});

test("ensureSenderAccount returns explicit outcomes through the Cloud Run handler", () => {
  assert.match(source, /async function ensureSenderAccountHandler/);
  assert.match(source, /cloudRunSenderProfileHandlers/);
  assert.match(source, /action: "existing_sender_role_allowed"/);
  assert.match(source, /action: "blocked_conflicting_role"/);
  assert.match(source, /action: userSnap\.exists \? "merged_sender_role" : "created_sender_profile"/);
  assert.match(source, /return \{ok: true, \.\.\.result\}/);
});

test("new Sender profiles mark and grant the 5 Roth starter credit once", () => {
  assert.match(source, /const rothLedger = require\("\.\/roth-ledger"\);/);
  assert.match(source, /function starterRothPending\(existing = \{\}\)/);
  assert.match(source, /function welcomeEmailPending\(existing = \{\}\)/);
  assert.match(source, /async function grantAndMarkSenderStarterRoth/);
  assert.match(source, /senderWelcomeEmail\.queueSenderWelcomeEmail/);
  assert.match(source, /patch\.starterRothGrantStatus = "pending"/);
  assert.match(source, /patch\.starterRothAmount = rothLedger\.SENDER_WELCOME_ROTH_AMOUNT/);
  assert.match(source, /starterRothEligible,?/);
  assert.match(source, /starterRothGrantStatus: "pending"/);
  assert.match(source, /starterRothGranted = true/);
  assert.match(source, /delete result\.starterRothEligible/);
});


test("existing profiles require a pending grant regardless of legacy Sender role representation", () => {
  assert.match(source, /const grantPending = !userSnap\.exists \|\| starterRothPending\(existing\);/);
  assert.match(source, /const starterRothEligible = grantPending \|\| welcomeEmailPending\(existing\);/);
});

test("Sender preferences are server-owned and validated", () => {
  assert.match(source, /async function updateSenderPreferencesHandler/);
  assert.match(source, /notificationPreferences/);
  assert.match(source, /Unsupported language preference/);
  assert.match(source, /Unsupported time format preference/);
  assert.match(source, /sender_preferences_updated/);
});

test("Sender session revocation reports Firebase global scope honestly", () => {
  assert.match(source, /async function revokeSenderSessionsHandler/);
  assert.match(source, /revokeRefreshTokens\(uid\)/);
  assert.match(source, /all_sessions_including_current/);
});

test("Sender activity and export read only sender-owned records", () => {
  assert.match(source, /async function getSenderAccountActivityHandler/);
  assert.match(source, /async function exportSenderDataHandler/);
  assert.match(source, /senderOwnedQuery\("senderProfileEvents", "uid", uid/);
  assert.match(source, /senderOwnedQuery\("notifications", "recipientId", uid/);
  assert.match(source, /senderOwnedQuery\("deliveryRequests", "userId", uid/);
});
