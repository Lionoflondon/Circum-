#!/usr/bin/env node
"use strict";

const assert = require("node:assert/strict");
const cp = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");

const root = path.resolve(__dirname, "..");
const script = path.join(root, "scripts/functions_release_provenance.js");

function run(args) {
  return cp.execFileSync(process.execPath, [script, ...args], {
    cwd: root,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  });
}

test("duration provenance guard requires canonical route duration contract", () => {
  const result = JSON.parse(run(["guard"]));
  assert.equal(result.ok, true);
  assert.equal(result.guardedSource, "server/functions/sender-booking.js");
  assert.equal(result.canonicalDurationContract, "routeFacts.durationSeconds");
  assert.equal(result.canonicalDurationPresent, true);
  assert.equal(result.legacyHardcodedDurationPresent, false);
});

test("release provenance manifest fingerprints the Functions source package", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "circum-provenance-"));
  const out = path.join(dir, "manifest.json");
  run(["prepare", "--allow-dirty", "--out", out]);
  const manifest = JSON.parse(fs.readFileSync(out, "utf8"));
  assert.equal(manifest.project, "circum-2797c");
  assert.equal(manifest.region, "us-central1");
  assert.equal(manifest.runtime, "nodejs22");
  assert.match(manifest.git.commitSha, /^[a-f0-9]{40}$/);
  assert.equal(manifest.sourceFingerprint.algorithm, "sha256");
  assert.match(manifest.sourceFingerprint.digest, /^[a-f0-9]{64}$/);
  assert.ok(manifest.sourceFingerprint.fileCount > 100);
  for (const name of ["createSenderBookingQuote", "createSenderPaidDelivery"]) {
    assert.equal(
        manifest.functions[name].sourceFingerprint,
        manifest.sourceFingerprint.digest,
    );
    assert.equal(
        manifest.functions[name].canonicalDurationContract,
        "routeFacts.durationSeconds",
    );
  }
  assert.match(manifest.releaseManifestHash, /^[a-f0-9]{64}$/);
});
