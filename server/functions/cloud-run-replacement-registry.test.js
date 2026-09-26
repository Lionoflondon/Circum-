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

test("Admin collection read inventory points at the Cloud Run query route", () => {
  const files = ["server/functions/cloud-run-admin-access.js", "server/functions/cloud-run-admin-access.test.js"];
  const source = new Map(files.map((file) => [file, "adminQueryPage"]));
  assert.deepEqual(findCloudRunReplacements("adminQueryPage", files, source), [
    "cloud-run-admin-access.js",
    "cloud-run-admin-access.test.js",
  ]);
  assert.deepEqual(productionCallers("adminQueryPage", ["old-managed-caller.dart"]), ["lib/app/admin/admin_phase1_shell.dart"]);
});

test("Gift editor inventory points at the authenticated Cloud Run mutation route", () => {
  const files = ["server/functions/cloud-run-admin-access.js", "server/functions/cloud-run-admin-access.test.js"];
  const source = new Map(files.map((file) => [file, "adminSaveGiftRequestEditor"]));
  assert.deepEqual(findCloudRunReplacements("adminSaveGiftRequestEditor", files, source), [
    "cloud-run-admin-access.js",
    "cloud-run-admin-access.test.js",
  ]);
  assert.deepEqual(productionCallers("adminSaveGiftRequestEditor", ["old-managed-caller.dart"]), ["lib/app/admin/admin_phase1_shell.dart"]);
});

test("Normal Stripe webhook inventory points at the single shared Cloud Run processor", () => {
  const files = ["server/functions/cloud-run-stripe-server.js", "server/functions/cloud-run-stripe-server.test.js"];
  const source = new Map(files.map((file) => [file, "POST /stripe/webhook"]));
  assert.deepEqual(findCloudRunReplacements("StripeWebhook", files, source), [
    "cloud-run-stripe-server.js",
    "cloud-run-stripe-server.test.js",
  ]);
  assert.deepEqual(productionCallers("StripeWebhook", ["legacy-doc.md"]), ["server/functions/cloud-run-stripe-server.js"]);
});
