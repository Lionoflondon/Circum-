"use strict";
const {test} = require("node:test");
const assert = require("node:assert/strict");
const {check} = require("./retry_containment_check");
function fixture() {
  const old = "circum-notification-retries-00019-vit";
  const staged = "circum-notification-retries-cost579-20261009";
  const names = Array.from({length: 25}, (_, i) => `projects/circum-2797c/subscriptions/held-${i}`);
  return {
    budgets: {budgets: ["services/152E-C115-5142", "services/29E7-DA93-CA13"].map(service => ({budgetFilter: {projects: ["projects/516426305461"], services: [service], calendarPeriod: "MONTH"}, amount: {specifiedAmount: {currencyCode: "GBP", units: "5"}}, spendCap: {outputState: "ENFORCED"}}))},
    retry: {metadata: {name: "circum-notification-retries", annotations: {"run.googleapis.com/scalingMode": "manual", "run.googleapis.com/manualInstanceCount": "0"}}, spec: {traffic: [{revisionName: old, percent: 100}]}, status: {traffic: [{revisionName: old, percent: 100}]}},
    revisions: [old, staged].map(name => ({metadata: {name, labels: {"serving.knative.dev/service": "circum-notification-retries"}, annotations: {"autoscaling.knative.dev/minScale": name === old ? "1" : "0"}}})),
    heldSubscriptionNames: names, subscriptions: names.map(name => ({name, pushConfig: {}})),
  };
}
test("manual-zero containment never certifies rearm or restoration", () => {
  const result = check(fixture());
  assert.equal(result.containmentPassed, true);
  assert.equal(result.restorationCertified, false);
  assert.equal(result.rearmBlockers.length, 2);
});
for (const [name, mutate] of [
  ["automatic scaling", s => {s.retry.metadata.annotations["run.googleapis.com/scalingMode"] = "automatic";}],
  ["positive manual instances", s => {s.retry.metadata.annotations["run.googleapis.com/manualInstanceCount"] = "1";}],
  ["tag-only minimum bypass", s => {s.retry.spec.traffic.push({revisionName: s.revisions[0].metadata.name, tag: "old"});}],
  ["staged traffic", s => {s.retry.status.traffic = [{revisionName: s.revisions[1].metadata.name, percent: 100}];}],
  ["cap reset", s => {s.budgets.budgets[0].spendCap.outputState = "CONFIGURED";}],
  ["cap lift", s => {s.budgets.budgets[0].amount.specifiedAmount.units = "15";}],
  ["wrong project cap", s => {s.budgets.budgets[0].budgetFilter.projects = ["projects/another"]; }],
  ["missing held queue", s => {s.subscriptions.pop();}],
  ["push rearm", s => {s.subscriptions[0].pushConfig = {pushEndpoint: "https://example.invalid"};}],
  ["incomplete baseline", s => {s.heldSubscriptionNames.pop();}],
  ["missing revision evidence", s => {delete s.revisions;}],
  ["unknown traffic revision", s => {s.retry.spec.traffic[0].revisionName = "unknown";}],
]) test(`rejects ${name}`, () => {const s = fixture(); mutate(s); assert.equal(check(s).containmentPassed, false);});
test("missing inventories fail closed", () => assert.equal(check({}).containmentPassed, false));
