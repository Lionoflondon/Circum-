"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");

const source = fs.readFileSync("business-mutations.js", "utf8");
const access = fs.readFileSync("business-access.js", "utf8");
const booking = fs.readFileSync("sender-booking.js", "utf8");
const cancellation = fs.readFileSync("delivery-policy.js", "utf8");
const payments = fs.readFileSync("business-payments.js", "utf8");

test("Business mutations use one server authority and exact permissions", () => {
  for (const permission of [
    "deliveries.notes.modify",
    "operations.incidents.acknowledge",
  ]) assert.match(source, new RegExp(permission.replaceAll(".", "\\.")));
  assert.match(booking, /resolveBusinessAuthority/);
  assert.match(booking, /"deliveries\.create"/);
  assert.match(cancellation, /"deliveries\.cancel"/);
  assert.match(access, /"team\.invite"/);
  assert.match(access, /"team\.remove"/);
  assert.match(payments, /"finance\.payments\.initiate"/);
});

test("Business mutations fail closed across ownership boundaries and audit changes", () => {
  assert.match(source, /businessAccountId/);
  assert.match(source, /Business delivery not found/);
  assert.match(source, /Business incident not found/);
  assert.match(source, /businessAuditLogs/);
  assert.match(source, /previousState/);
  assert.match(source, /newState/);
  assert.match(source, /actorUserId/);
  assert.match(source, /targetId/);
});

test("Business operations cannot become platform Admin operations", () => {
  assert.doesNotMatch(source, /adminAuditLogs/);
  assert.doesNotMatch(source, /resolveOperationalIncident/);
  assert.doesNotMatch(source, /AdminOverride/);
});
