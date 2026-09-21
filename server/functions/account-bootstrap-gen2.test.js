"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const source = fs.readFileSync(
    path.join(__dirname, "account-bootstrap-gen2.js"),
    "utf8",
);
const indexSource = fs.readFileSync(path.join(__dirname, "index.js"), "utf8");

test("account bootstrap uses Gen 2 callable infrastructure", () => {
  assert.match(source, /firebase-functions\/v2\/https/);
  assert.match(source, /region: REGION/);
  assert.match(source, /maxInstances: 10/);
  assert.doesNotMatch(source, /firebase-functions\/v1/);
});

test("retired managed account bootstrap exports cannot be recreated", () => {
  assert.doesNotMatch(indexSource, /accountBootstrapGen2/);
  assert.doesNotMatch(indexSource, /exports\.ensureSenderAccount/);
  assert.doesNotMatch(indexSource, /exports\.verifyRiderAccountAccess/);
  assert.doesNotMatch(indexSource, /exports\.updateRiderProfile/);
  assert.doesNotMatch(indexSource, /exports\.ensureSenderAccount = senderAccount\.ensureSenderAccount/);
  assert.doesNotMatch(indexSource, /exports\.verifyRiderAccountAccess = riderAccount\.verifyRiderAccountAccess/);
  assert.doesNotMatch(indexSource, /exports\.updateRiderProfile = riderAccount\.updateRiderProfile/);
});

test("superseded bridge retains the historical security contract for reference", () => {
  assert.match(source, /senderAccount\.ensureSenderAccount,[\s\S]*enforceAppCheck: false/);
  assert.match(source, /riderAccount\.verifyRiderAccountAccess,[\s\S]*enforceAppCheck: true/);
  assert.match(source, /riderAccount\.updateRiderProfile,[\s\S]*enforceAppCheck: true/);
  assert.match(source, /legacyCallable\.run\(request\.data \|\| \{\}, context\)/);
});
