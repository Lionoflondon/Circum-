#!/usr/bin/env node
"use strict";

const fs = require("fs");
const path = require("path");

const root = path.resolve(__dirname, "..");
const healthSource = fs.readFileSync(path.join(root, "server/functions/operations-health-centre.js"), "utf8");
const indexSource = fs.readFileSync(path.join(root, "server/functions/index.js"), "utf8");
const adminSource = fs.readFileSync(path.join(root, "lib/app/admin/admin_phase1_shell.dart"), "utf8");

const required = [
  ["operationsHealthScan callable", /exports\.operationsHealthScan\s*=\s*operationsHealthCentre\.operationsHealthScan\(\)/],
  ["operationsHealthRepair callable", /exports\.operationsHealthRepair\s*=\s*operationsHealthCentre\.operationsHealthRepair\(\)/],
  ["liveDeliveryDiagnostics callable", /exports\.liveDeliveryDiagnostics\s*=\s*operationsHealthCentre\.liveDeliveryDiagnostics\(\)/],
  ["critical deployment services", /criticalServices\s*=\s*new Set\(\[/],
  ["deployment not certified state", /NOT_CERTIFIED/],
  ["no financial mutation promise", /financialRecordsMutated:\s*0/],
  ["admin health scan button", /Operations Health Scan/],
  ["admin health repair button", /Health Repair/],
  ["admin delivery diagnostics", /Live Delivery Diagnostics/],
  ["pipeline reset retained", /httpsCallable\('pipelineHealthReset'\)/],
];

const failures = [];
for (const [label, pattern] of required) {
  const source = label.startsWith("admin") || label.includes("pipeline") ?
    adminSource : label.startsWith("operations") || label.startsWith("live") ?
      indexSource : healthSource;
  if (!pattern.test(source)) failures.push(label);
}

if (failures.length) {
  console.error("Operations Health deployment gate failed:");
  failures.forEach((failure) => console.error(`- ${failure}`));
  process.exit(1);
}

console.log("Operations Health deployment gate passed.");
