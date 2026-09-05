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

test("ensureSenderAccount returns explicit outcomes without changing the callable", () => {
  assert.match(source, /exports\.ensureSenderAccount = functions\.https\.onCall/);
  assert.match(source, /action: "existing_sender_role_allowed"/);
  assert.match(source, /action: "blocked_conflicting_role"/);
  assert.match(source, /action: userSnap\.exists \? "merged_sender_role" : "created_sender_profile"/);
  assert.match(source, /return \{ok: true, \.\.\.result\}/);
});

test("new Sender profiles mark and grant the 5 Roth starter credit once", () => {
  assert.match(source, /const rothLedger = require\("\.\/roth-ledger"\);/);
  assert.match(source, /function starterRothPending\(existing = \{\}\)/);
  assert.match(source, /async function grantAndMarkSenderStarterRoth/);
  assert.match(source, /patch\.starterRothGrantStatus = "pending"/);
  assert.match(source, /patch\.starterRothAmount = rothLedger\.SENDER_WELCOME_ROTH_AMOUNT/);
  assert.match(source, /starterRothEligible: starterRothPending\(existing\)/);
  assert.match(source, /starterRothGrantStatus: "pending"/);
  assert.match(source, /starterRothGranted = true/);
  assert.match(source, /delete result\.starterRothEligible/);
});


test("existing profiles require a pending grant regardless of legacy Sender role representation", () => {
  assert.match(source, /const starterRothEligible = !userSnap\.exists \|\| starterRothPending\(existing\);/);
});
