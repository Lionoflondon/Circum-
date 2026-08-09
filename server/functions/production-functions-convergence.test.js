"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const root = path.resolve(__dirname, "../..");
const manifest = require(path.join(root, "docs/releases/production-functions-manifest.json"));
const indexSource = fs.readFileSync(path.join(__dirname, "index.js"), "utf8");
const targetSources = Object.freeze({
  completeDelivery: "delivery-tracking.js",
  founderRiderOperationalPreflight: "founder-authority.js",
  onDeliveryCompletedEvent: "delivery-completed-event.js",
  onDeliveryEvidencePhotoFinalized: "delivery-evidence-media.js",
  recordDeliveryEvidence: "delivery-evidence.js",
  recoverIneligibleSenderDelivery: "sender-booking.js",
});

test("production Function inventory is completely represented by source", () => {
  assert.equal(manifest.inventory.productionFunctions, 253);
  assert.equal(manifest.inventory.applicationFunctions, 247);
  assert.equal(manifest.inventory.extensionFunctions, 6);
  assert.equal(manifest.inventory.sourceExports, 247);
  assert.equal(manifest.applicationFunctions.length, 247);
  assert.equal(
      manifest.extensions.reduce((count, extension) => count + extension.functions.length, 0),
      6,
  );
  assert.equal(manifest.applicationFunctions.some((entry) => !entry.source), false);
  assert.equal(manifest.applicationFunctions.some((entry) => entry.releaseSha !== "SELF"), false);
  const manifestNames = manifest.applicationFunctions.map((entry) => entry.name).sort();
  const sourceExports = [...indexSource.matchAll(/exports\.([A-Za-z0-9_]+)/g)]
      .map((match) => match[1])
      .sort();
  assert.deepEqual(manifestNames, sourceExports);
  assert.equal(new Set(manifestNames).size, manifestNames.length);
  for (const entry of manifest.applicationFunctions) {
    const sourcePath = entry.source.split("#")[0];
    assert.equal(
        fs.existsSync(path.join(root, sourcePath)),
        true,
        `Missing source file for ${entry.name}: ${sourcePath}`,
    );
  }
});

test("all six recovered critical Functions have exports and canonical source modules", () => {
  for (const [name, sourceFile] of Object.entries(targetSources)) {
    const entry = manifest.applicationFunctions.find((item) => item.name === name);
    assert.ok(entry, `Missing manifest entry for ${name}`);
    assert.equal(entry.state, "ACTIVE");
    assert.equal(entry.runtime, "nodejs20");
    assert.ok(entry.criticalTarget);
    assert.match(indexSource, new RegExp(`exports\\.${name}\\s*=`));
    assert.equal(fs.existsSync(path.join(__dirname, sourceFile)), true);
    assert.equal(entry.source, `server/functions/${sourceFile}#${name}`);
  }
});

test("Firebase Extensions remain separately inventoried", () => {
  assert.deepEqual(
      manifest.extensions.map((entry) => entry.instanceId).sort(),
      ["export-user-data", "mailchimp-firebase-sync"],
  );
  for (const extension of manifest.extensions) {
    assert.equal(extension.state, "ACTIVE");
    assert.ok(extension.version);
    assert.equal(extension.functions.every((entry) => entry.name.startsWith("ext-")), true);
  }
});
