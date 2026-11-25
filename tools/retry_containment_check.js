#!/usr/bin/env node
"use strict";
// Offline only: this checker never calls Google APIs or changes resources.
const fs = require("node:fs");
const SERVICE = "circum-notification-retries";
const STAGED = "circum-notification-retries-cost579-20261009";
const CAP_SERVICES = ["services/152E-C115-5142", "services/29E7-DA93-CA13"];
function check(snapshot) {
  const failures = [];
  const rearmBlockers = [];
  const fail = (message) => failures.push(message);
  const budgets = snapshot.budgets?.budgets;
  if (!Array.isArray(budgets)) fail("Budget inventory missing");
  for (const id of CAP_SERVICES) {
    const matching = (budgets || []).filter(b => b.budgetFilter?.services?.includes(id) && b.budgetFilter?.projects?.includes("projects/516426305461"));
    if (matching.length !== 1) { fail(`Expected one project cap for ${id}`); continue; }
    const b = matching[0];
    const a = b.amount?.specifiedAmount;
    if (a?.currencyCode !== "GBP" || String(a.units) !== "5" || Number(a.nanos || 0) !== 0 || b.budgetFilter?.calendarPeriod !== "MONTH" || b.spendCap?.outputState !== "ENFORCED") fail(`Cap changed or unenforced: ${id}`);
  }
  const retry = snapshot.retry;
  if (retry?.metadata?.name !== SERVICE) fail("Wrong or missing retry service");
  const annotations = retry?.metadata?.annotations || {};
  if (annotations["run.googleapis.com/scalingMode"] !== "manual" || annotations["run.googleapis.com/manualInstanceCount"] !== "0") fail("Retry must remain manual zero");
  const revisions = snapshot.revisions;
  if (!Array.isArray(revisions)) fail("Revision inventory missing");
  const byName = new Map((revisions || []).filter(r => r.metadata?.labels?.["serving.knative.dev/service"] === SERVICE).map(r => [r.metadata.name, r]));
  if (!byName.has(STAGED)) fail("Staged #579 revision missing");
  for (const field of ["spec", "status"]) {
    const traffic = retry?.[field]?.traffic;
    if (!Array.isArray(traffic) || !traffic.length) { fail(`${field} traffic inventory missing`); continue; }
    if (traffic.reduce((n, t) => n + Number(t.percent || 0), 0) !== 100) fail(`${field} traffic percentages invalid`);
    for (const t of traffic) {
      if (!t.revisionName || !byName.has(t.revisionName)) { fail(`${field} traffic references unknown revision`); continue; }
      if (t.revisionName === STAGED && (Number(t.percent || 0) !== 0 || t.tag)) fail(`#579 must remain untagged at zero traffic (${field})`);
      if (t.tag) fail(`Remove retry tag before containment certification: ${t.tag}`);
      const minimum = Number(byName.get(t.revisionName).metadata?.annotations?.["autoscaling.knative.dev/minScale"] || 0);
      if (!Number.isFinite(minimum) || minimum < 0) fail("Invalid revision minimum");
      if (minimum > 0 && (Number(t.percent || 0) > 0 || t.tag)) rearmBlockers.push(`${t.revisionName}: min ${minimum}, referenced by ${field} traffic; automatic scaling prohibited`);
    }
  }
  const baseline = snapshot.heldSubscriptionNames;
  const subscriptions = snapshot.subscriptions;
  if (!Array.isArray(baseline) || baseline.length !== 25 || new Set(baseline).size !== 25 || baseline.some(n => typeof n !== "string" || !n.startsWith("projects/circum-2797c/subscriptions/"))) fail("Expected the exact reviewed 25 unique held subscription names");
  if (!Array.isArray(subscriptions)) fail("Subscription inventory missing");
  for (const name of baseline || []) {
    const matches = (subscriptions || []).filter(s => s.name === name);
    if (matches.length !== 1 || Object.keys(matches[0].pushConfig || {}).length !== 0) fail(`Held subscription missing or rearmed: ${name}`);
  }
  return {containmentPassed: failures.length === 0, failures, rearmBlockers: [...new Set(rearmBlockers)], restorationCertified: false};
}
if (require.main === module) {
  try {
    if (process.argv.length !== 3) throw new Error("Usage: node tools/retry_containment_check.js SNAPSHOT.json");
    const result = check(JSON.parse(fs.readFileSync(process.argv[2], "utf8")));
    console.log(JSON.stringify(result, null, 2));
    process.exitCode = result.containmentPassed ? 0 : 1;
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
module.exports = {check};
