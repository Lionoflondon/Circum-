#!/usr/bin/env node
/* eslint-disable no-console */
"use strict";

const crypto = require("node:crypto");
const cp = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const root = path.resolve(__dirname, "..");
const project = process.env.FIREBASE_PROJECT || "circum-2797c";
const region = process.env.FIREBASE_FUNCTIONS_REGION || "us-central1";
const runtime = "nodejs22";
const targetFunctions = [
  "createSenderBookingQuote",
  "createSenderPaidDelivery",
];
const contract = "routeFacts.durationSeconds";
const guardedSource = "server/functions/sender-booking.js";
const legacyDurationPattern = /estimatedDurationMinutes\s*:\s*28\b/;

function fail(message) {
  console.error(message);
  process.exit(1);
}

function usage() {
  fail([
    "Usage:",
    "  node scripts/functions_release_provenance.js guard",
    "  node scripts/functions_release_provenance.js prepare --out <file>",
    "  node scripts/functions_release_provenance.js postdeploy --manifest <file> --out <file>",
  ].join("\n"));
}

function exec(command, args, options = {}) {
  return cp.execFileSync(command, args, {
    cwd: root,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
    ...options,
  }).trim();
}

function git(args) {
  return exec("git", args);
}

function argValue(name) {
  const args = process.argv.slice(3);
  const equal = args.find((arg) => arg.startsWith(`${name}=`));
  if (equal) return equal.slice(name.length + 1);
  const index = args.indexOf(name);
  return index === -1 ? "" : args[index + 1] || "";
}

function assertCleanWorktree() {
  if (process.argv.includes("--allow-dirty")) return;
  const status = git(["status", "--porcelain=v1", "--untracked-files=all"]);
  if (status) {
    fail("Release provenance requires a clean worktree.");
  }
}

function sha256(buffer) {
  return crypto.createHash("sha256").update(buffer).digest("hex");
}

function trackedFunctionsFiles() {
  return git(["ls-files", "server/functions"])
      .split("\n")
      .map((file) => file.trim())
      .filter(Boolean)
      .filter((file) => !file.includes("/node_modules/"));
}

function sourcePackageFingerprint() {
  const files = trackedFunctionsFiles();
  const hash = crypto.createHash("sha256");
  for (const file of files) {
    const absolute = path.join(root, file);
    hash.update(`${file}\0`);
    hash.update(fs.readFileSync(absolute));
    hash.update("\0");
  }
  return {
    algorithm: "sha256",
    scope: "git-tracked server/functions package excluding node_modules",
    fileCount: files.length,
    digest: hash.digest("hex"),
  };
}

function durationContractGuard() {
  const sourcePath = path.join(root, guardedSource);
  const source = fs.readFileSync(sourcePath, "utf8");
  const hasCanonicalDuration = source.includes(contract);
  const hasLegacyHardcodedDuration = legacyDurationPattern.test(source);
  if (!hasCanonicalDuration || hasLegacyHardcodedDuration) {
    fail(JSON.stringify({
      ok: false,
      guardedSource,
      canonicalDurationPresent: hasCanonicalDuration,
      legacyHardcodedDurationPresent: hasLegacyHardcodedDuration,
    }, null, 2));
  }
  return {
    ok: true,
    guardedSource,
    canonicalDurationContract: contract,
    canonicalDurationPresent: true,
    legacyHardcodedDurationPresent: false,
  };
}

function baseManifest() {
  const generatedAt = new Date().toISOString();
  const commitSha = git(["rev-parse", "HEAD"]);
  const branch = process.env.GITHUB_REF_NAME || git(["branch", "--show-current"]) || "detached";
  const sourceFingerprint = sourcePackageFingerprint();
  const guard = durationContractGuard();
  return {
    schemaVersion: 1,
    releaseKind: "firebase-functions",
    project,
    region,
    runtime,
    generatedAt,
    workflow: {
      provider: process.env.GITHUB_ACTIONS === "true" ? "github_actions" : "local",
      runId: process.env.GITHUB_RUN_ID || null,
      runAttempt: process.env.GITHUB_RUN_ATTEMPT || null,
      workflow: process.env.GITHUB_WORKFLOW || null,
    },
    git: {
      commitSha,
      branch,
    },
    sourceFingerprint,
    durationContractGuard: guard,
    functions: Object.fromEntries(targetFunctions.map((name) => [name, {
      sourceFingerprint: sourceFingerprint.digest,
      canonicalDurationContract: contract,
    }])),
  };
}

function writeJson(file, value) {
  if (!file) usage();
  fs.mkdirSync(path.dirname(path.resolve(file)), {recursive: true});
  fs.writeFileSync(file, `${JSON.stringify(value, null, 2)}\n`);
}

function stableStringify(value) {
  if (Array.isArray(value)) {
    return `[${value.map((item) => stableStringify(item)).join(",")}]`;
  }
  if (value && typeof value === "object") {
    return `{${Object.keys(value).sort().map((key) =>
      `${JSON.stringify(key)}:${stableStringify(value[key])}`).join(",")}}`;
  }
  return JSON.stringify(value);
}

function manifestHash(manifest) {
  return sha256(Buffer.from(stableStringify(manifest)));
}

function describeFunction(name) {
  const raw = exec("gcloud", [
    "functions",
    "describe",
    name,
    `--region=${region}`,
    `--project=${project}`,
    "--format=json",
  ]);
  const data = JSON.parse(raw);
  return {
    name,
    state: data.state || data.status || null,
    runtime: data.buildConfig && data.buildConfig.runtime || data.runtime || null,
    updateTime: data.updateTime || null,
    serviceAccount: data.serviceConfig && data.serviceConfig.serviceAccountEmail ||
      data.serviceAccountEmail ||
      null,
    labels: data.labels || {},
    build: data.buildConfig && data.buildConfig.build || null,
    source: data.buildConfig && data.buildConfig.source || null,
    uri: data.serviceConfig && data.serviceConfig.uri || data.httpsTrigger && data.httpsTrigger.url || null,
    environment: data.environment || null,
    versionId: data.versionId || null,
  };
}

function postDeployManifest(manifestPath) {
  if (!manifestPath) usage();
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  const deployedAt = new Date().toISOString();
  manifest.postDeploy = {
    capturedAt: deployedAt,
    functions: Object.fromEntries(targetFunctions.map((name) => [name, describeFunction(name)])),
  };
  manifest.releaseManifestHash = manifestHash(manifest);
  for (const name of targetFunctions) {
    manifest.functions[name].live = manifest.postDeploy.functions[name];
    manifest.functions[name].releaseManifestHash = manifest.releaseManifestHash;
  }
  return manifest;
}

function main() {
  const command = process.argv[2];
  if (command === "guard") {
    console.log(JSON.stringify(durationContractGuard(), null, 2));
    return;
  }
  if (command === "prepare") {
    assertCleanWorktree();
    const out = argValue("--out") || path.join(os.tmpdir(), "functions-release-provenance.json");
    const manifest = baseManifest();
    manifest.releaseManifestHash = manifestHash(manifest);
    writeJson(out, manifest);
    console.log(JSON.stringify({
      ok: true,
      out,
      commitSha: manifest.git.commitSha,
      branch: manifest.git.branch,
      sourceFingerprint: manifest.sourceFingerprint.digest,
      releaseManifestHash: manifest.releaseManifestHash,
    }, null, 2));
    return;
  }
  if (command === "postdeploy") {
    const manifestPath = argValue("--manifest");
    const out = argValue("--out") || manifestPath;
    const manifest = postDeployManifest(manifestPath);
    writeJson(out, manifest);
    console.log(JSON.stringify({
      ok: true,
      out,
      releaseManifestHash: manifest.releaseManifestHash,
      functions: Object.fromEntries(targetFunctions.map((name) => [name, {
        state: manifest.functions[name].live.state,
        runtime: manifest.functions[name].live.runtime,
        updateTime: manifest.functions[name].live.updateTime,
        versionId: manifest.functions[name].live.versionId,
      }])),
    }, null, 2));
    return;
  }
  usage();
}

main();
