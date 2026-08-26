#!/usr/bin/env node
"use strict";

const fs = require("fs");
const path = require("path");

function argValue(name) {
  const index = process.argv.indexOf(name);
  return index === -1 ? null : process.argv[index + 1];
}

const app = process.argv[2];
const expectedPackage = argValue("--expected-package");
const minVersionCode = Number(argValue("--min-version-code"));

if (!app || !expectedPackage || !Number.isInteger(minVersionCode)) {
  console.error("Usage: android_release_guard.js <app> --expected-package <package> --min-version-code <code>");
  process.exit(1);
}

const pubspec = fs.readFileSync(path.join(process.cwd(), "pubspec.yaml"), "utf8");
const versionMatch = pubspec.match(/^version:\s*([0-9]+(?:\.[0-9]+){2})\+([0-9]+)\s*$/m);
if (!versionMatch) {
  console.error("Unable to find Flutter version in pubspec.yaml");
  process.exit(1);
}

const versionName = versionMatch[1];
const versionCode = Number(versionMatch[2]);
if (versionCode < minVersionCode) {
  console.error(`${app} versionCode ${versionCode} is below required repository floor ${minVersionCode}`);
  process.exit(1);
}

const gradle = fs.readFileSync(path.join(process.cwd(), "android", "app", "build.gradle"), "utf8");
if (!gradle.includes(`applicationId "${expectedPackage}"`)) {
  console.error(`Expected Android applicationId ${expectedPackage}`);
  process.exit(1);
}

const ledgerPath = path.join(process.cwd(), "docs", "releases", "android-release-ledger.json");
const ledger = JSON.parse(fs.readFileSync(ledgerPath, "utf8"));
if (ledger.package !== expectedPackage) {
  console.error(`Ledger package ${ledger.package} does not match ${expectedPackage}`);
  process.exit(1);
}
if (versionCode <= Number(ledger.repositoryVersionFloor.versionCode)) {
  console.error(`versionCode ${versionCode} must be greater than ledger floor ${ledger.repositoryVersionFloor.versionCode}`);
  process.exit(1);
}

console.log(`${app} Android release guard passed for ${versionName}+${versionCode}`);
