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
const classificationPath = argValue("--classification-json");
const allowRestorableScope = process.argv.includes("--allow-restorable-scope");
const allowSourceDeploymentScope = process.argv.includes("--allow-source-deployment-scope");
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
let classification = null;
if (classificationPath) {
  classification = JSON.parse(fs.readFileSync(classificationPath, "utf8"));
}
const classifiedMissing = new Set((classification && classification.deployedMissingSource || [])
    .map((item) => item.name));
const classifiedAbsent = new Set((classification && classification.sourceNotDeployed || [])
    .map((item) => item.name));
const restorableCompatibility = new Set((classification && classification.sourceNotDeployed || [])
    .filter((item) => item.category === "RESTORABLE_COMPATIBILITY")
    .map((item) => item.name));
const approvedSourceDeployment = new Set((classification && classification.sourceNotDeployed || [])
    .filter((item) => item.category === "APPROVED_SOURCE_DEPLOYMENT")
    .map((item) => item.name));
for (const name of restorableCompatibility) {
  if (deployedSet.has(name)) classifiedAbsent.delete(name);
}
for (const name of approvedSourceDeployment) {
  if (deployedSet.has(name)) classifiedAbsent.delete(name);
}
const unexpectedDeployedMissing = classification ?
  deployedMissingSource.filter((name) => !classifiedMissing.has(name)) : [];
const staleDeployedMissing = classification ?
  [...classifiedMissing].filter((name) => !deployedMissingSource.includes(name)) : [];
const unexpectedSourceNotDeployed = classification ?
  sourceNotDeployed.filter((name) => !classifiedAbsent.has(name)) : [];
const staleSourceNotDeployed = classification ?
  [...classifiedAbsent].filter((name) => !sourceNotDeployed.includes(name)) : [];
const classificationMatches = Boolean(classification) &&
  unexpectedDeployedMissing.length === 0 && staleDeployedMissing.length === 0 &&
  unexpectedSourceNotDeployed.length === 0 && staleSourceNotDeployed.length === 0;
const exactRestorableScope = allowRestorableScope && deploymentScope.length > 0 &&
  deploymentScope.length === scopeNotDeployed.length &&
  scopeNotDeployed.every((name) => restorableCompatibility.has(name));
const exactApprovedSourceScope = allowSourceDeploymentScope && deploymentScope.length > 0 &&
  scopeNotDeployed.length > 0 &&
  scopeNotDeployed.every((name) => approvedSourceDeployment.has(name));
const unsafeScopeNotDeployed = exactRestorableScope || exactApprovedSourceScope ? [] : scopeNotDeployed;

console.log(JSON.stringify({
  deployed: deployed.length,
  sourceExports: exported.length,
  deployedMissingSource,
  sourceNotDeployed,
  deploymentScope,
  scopeNotDeployed,
  allowSourceDeploymentScope,
  classificationMatches,
  classificationDrift: {
    unexpectedDeployedMissing,
    staleDeployedMissing,
    unexpectedSourceNotDeployed,
    staleSourceNotDeployed,
  },
}, null, 2));

if (classification && !classificationMatches) {
  console.error(
      "Production Functions inventory differs from the reviewed classification. " +
      "Stop and reconcile the drift before deployment.",
  );
  process.exit(1);
}

if (deploymentScope.length > 0 && unsafeScopeNotDeployed.length > 0) {
  console.error(
      "Unsafe Functions scope: it contains source exports that are not present in " +
      "the production inventory. Review ownership before creating or restoring them.",
  );
  process.exit(1);
}

if (deploymentScope.length === 0 && deployedMissingSource.length > 0 && !classificationMatches) {
  console.error(
      "Function inventory mismatch: source is missing deployed functions. " +
      "Do not deploy all functions until these are recovered or intentionally retired.",
  );
  process.exit(1);
}

if (deploymentScope.length === 0 && classificationMatches) {
  console.error("Production Functions inventory matches the reviewed classification.");
}

if (deploymentScope.length > 0 && deployedMissingSource.length > 0) {
  console.error(
      "Function inventory mismatch remains, but the requested scope only updates " +
      "functions already present in production.",
  );
}
