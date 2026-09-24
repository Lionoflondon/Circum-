"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {findCloudRunReplacements, productionCallers} = require("./cloud-run-replacement-registry");

test("Rider application replacement requires an App Check-protected live operation binding", () => {
  const service = "/repo/cloud-run-account-bootstrap.js";
  const files = [service];
  const liveBinding = new Map([[service, "submitRiderApplication: {handler: riderAccount.submitRiderApplication, appCheckRequired: true}"]]);
  const incidentalMention = new Map([[service, "// submitRiderApplication is planned here\nmodule.exports = {};"]]);
  const unprotectedBinding = new Map([[service, "submitRiderApplication: {handler: riderAccount.submitRiderApplication, appCheckRequired: false}"]]);

  assert.deepEqual(findCloudRunReplacements("submitRiderApplication", files, liveBinding), ["cloud-run-account-bootstrap.js"]);
  assert.deepEqual(findCloudRunReplacements("submitRiderApplication", files, incidentalMention), []);
  assert.deepEqual(findCloudRunReplacements("submitRiderApplication", files, unprotectedBinding), []);
});

test("Rider application caller inventory excludes tests and service implementation matches", () => {
  assert.deepEqual(productionCallers("submitRiderApplication", [
    "cloud-run-account-bootstrap.js",
    "server/functions/rider-account.test.js",
    "server/functions/rider-onboarding-flow.emulator.test.js",
  ]), ["lib/website/shared/circum_website_app.dart"]);
});

test("Admin access caller inventory points at the Cloud Run adapter", () => {
  assert.deepEqual(productionCallers("adminResolveAccess", [
    "lib/app/admin/admin_access_api.dart",
    "lib/app/admin/admin_phase1_shell.dart",
    "server/functions/cloud-run-admin-access.js",
    "server/functions/cloud-run-admin-access.test.js",
  ]), ["lib/app/admin/admin_access_api.dart"]);
});
