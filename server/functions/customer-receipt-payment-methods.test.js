"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const source = fs.readFileSync(path.join(__dirname, "customer-delivery-trust.js"), "utf8");

test("customer receipt projects authoritative mixed-payment contributions", () => {
  assert.match(source, /rothAppliedAmount: amount\(data\.rothAppliedAmount\)/);
  assert.match(source, /externalPaidAmount: amount\(data\.remainingAmount\)/);
});
