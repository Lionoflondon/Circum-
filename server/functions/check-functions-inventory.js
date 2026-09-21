#!/usr/bin/env node
/* eslint-disable no-console */
"use strict";

const fs = require("fs");
const path = require("path");

function argValue(name) {
  const prefix = `${name}=`;
  const item = process.argv.slice(2).find((value) => value.startsWith(prefix));
  return item ? item.slice(prefix.length) : "";
}

const deployedPath = argValue("--deployed-json");
const deploymentScope = argValue("--scope")
    .split(",")
    .map((target) => target.trim())
    .filter(Boolean)
    .map((target) => target.replace(/^functions:/, ""));
if (!deployedPath) {
  console.error("Usage: node server/functions/check-functions-inventory.js --deployed-json=/path/to/functions-list.json");
  process.exit(2);
}

const deployedRaw = JSON.parse(fs.readFileSync(deployedPath, "utf8"));
const deployed = (deployedRaw.result || [])
    .map((item) => item.id || item.name || "")
    .filter((name) => name && !name.startsWith("ext-"))
    .sort();

const indexPath = path.join(__dirname, "index.js");
const indexSource = fs.readFileSync(indexPath, "utf8");
const exported = [...indexSource.matchAll(/exports\.([A-Za-z0-9_]+)/g)]
    .map((match) => match[1])
    .sort();

const exportedSet = new Set(exported);
const deployedSet = new Set(deployed);
const deployedMissingSource = deployed.filter((name) => !exportedSet.has(name));
const sourceNotDeployed = exported.filter((name) => !deployedSet.has(name));
const scopeNotDeployed = deploymentScope.filter((name) => !deployedSet.has(name));

console.log(JSON.stringify({
  deployed: deployed.length,
  sourceExports: exported.length,
  deployedMissingSource,
  sourceNotDeployed,
  deploymentScope,
  scopeNotDeployed,
}, null, 2));

if (deploymentScope.length > 0 && scopeNotDeployed.length > 0) {
  console.error(
      "Unsafe Functions scope: it contains source exports that are not present in " +
      "the production inventory. Review ownership before creating or restoring them.",
  );
  process.exit(1);
}

if (deploymentScope.length === 0 && deployedMissingSource.length > 0) {
  console.error(
      "Function inventory mismatch: source is missing deployed functions. " +
      "Do not deploy all functions until these are recovered or intentionally retired.",
  );
  process.exit(1);
}

if (deploymentScope.length > 0 && deployedMissingSource.length > 0) {
  console.error(
      "Function inventory mismatch remains, but the requested scope only updates " +
      "functions already present in production.",
  );
}
