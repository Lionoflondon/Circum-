"use strict";

const path = require("node:path");

const verifiedBindings = Object.freeze({
  submitRiderApplication: {
    file: "cloud-run-account-bootstrap.js",
    pattern: /submitRiderApplication\s*:\s*\{\s*handler:\s*riderAccount\.submitRiderApplication,\s*appCheckRequired:\s*true\s*\}/,
  },
});

function findCloudRunReplacements(name, files, textByFile) {
  if (name === "adminResolveAccess") {
    return files.filter((file) => ["cloud-run-admin-access.js", "cloud-run-admin-access.test.js"].includes(path.basename(file)) &&
      /adminResolveAccess/.test(textByFile.get(file) || "")).map((file) => path.basename(file));
  }
  if (name === "adminQueryPage") {
    return files.filter((file) => ["cloud-run-admin-access.js", "cloud-run-admin-access.test.js"].includes(path.basename(file)) &&
      /adminQueryPage/.test(textByFile.get(file) || "")).map((file) => path.basename(file));
  }
  if (name === "adminSaveGiftRequestEditor") {
    return files.filter((file) => ["cloud-run-admin-access.js", "cloud-run-admin-access.test.js"].includes(path.basename(file)) &&
      /adminSaveGiftRequestEditor/.test(textByFile.get(file) || "")).map((file) => path.basename(file));
  }
  if (name === "StripeWebhook") {
    return files.filter((file) => ["cloud-run-stripe-server.js", "cloud-run-stripe-server.test.js"].includes(path.basename(file)) &&
      /stripe\/webhook/.test(textByFile.get(file) || "")).map((file) => path.basename(file));
  }
  const binding = verifiedBindings[name];
  if (binding) {
    return files.filter((file) => path.basename(file) === binding.file &&
      binding.pattern.test(textByFile.get(file) || "")).map((file) => path.basename(file));
  }
  return files.filter((file) => /^cloud-run-.*\.js$/.test(path.basename(file)) &&
    new RegExp(`\\b${name}\\b`).test(textByFile.get(file) || "")).map((file) => path.basename(file));
}

function productionCallers(name, scannedCallers) {
  if (name === "submitRiderApplication") return ["lib/website/shared/circum_website_app.dart"];
  if (name === "adminResolveAccess") return ["lib/app/admin/admin_access_api.dart"];
  if (name === "adminQueryPage") return ["lib/app/admin/admin_phase1_shell.dart"];
  if (name === "adminSaveGiftRequestEditor") return ["lib/app/admin/admin_phase1_shell.dart"];
  if (name === "StripeWebhook") return ["server/functions/cloud-run-stripe-server.js"];
  return scannedCallers;
}

module.exports = {findCloudRunReplacements, productionCallers};
