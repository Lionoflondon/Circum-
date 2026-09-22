"use strict";

const path = require("node:path");

const verifiedBindings = Object.freeze({
  submitRiderApplication: {
    file: "cloud-run-account-bootstrap.js",
    pattern: /submitRiderApplication\s*:\s*\{\s*handler:\s*riderAccount\.submitRiderApplication,\s*appCheckRequired:\s*true\s*\}/,
  },
});

function findCloudRunReplacements(name, files, textByFile) {
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
  return scannedCallers;
}

module.exports = {findCloudRunReplacements, productionCallers};
