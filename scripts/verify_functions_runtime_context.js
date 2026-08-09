#!/usr/bin/env node
"use strict";

const {execFileSync} = require("node:child_process");

function needsRuntimeProjectContext(entry = {}) {
  const trigger = entry.trigger || entry.eventTrigger || {};
  return Boolean(trigger.eventType || entry.schedule || entry.scheduleTrigger);
}

function missingRuntimeProjectContext(entries = []) {
  return entries
      .filter(needsRuntimeProjectContext)
      .filter((entry) => !Object.prototype.hasOwnProperty.call(entry.environmentVariables || {}, "GCLOUD_PROJECT"))
      .map((entry) => entry.id)
      .sort();
}

function listFunctions(project) {
  const output = execFileSync(
      "firebase",
      ["functions:list", "--project", project, "--json"],
      {encoding: "utf8", stdio: ["ignore", "pipe", "inherit"]},
  );
  const parsed = JSON.parse(output);
  return parsed.result || [];
}

if (require.main === module) {
  const project = process.argv[2];
  if (!project) {
    console.error("Usage: node scripts/verify_functions_runtime_context.js <project>");
    process.exit(2);
  }
  const missing = missingRuntimeProjectContext(listFunctions(project));
  if (missing.length) {
    console.error(`Runtime project context missing from ${missing.length} Functions: ${missing.join(", ")}`);
    process.exit(1);
  }
  console.log("All scheduled and event-driven Functions expose runtime project context.");
}

module.exports = {missingRuntimeProjectContext, needsRuntimeProjectContext};
