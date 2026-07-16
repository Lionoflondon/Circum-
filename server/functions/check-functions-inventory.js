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

console.log(JSON.stringify({
  deployed: deployed.length,
  sourceExports: exported.length,
  deployedMissingSource,
  sourceNotDeployed,
}, null, 2));

if (deployedMissingSource.length > 0) {
  console.error(
      "Function inventory mismatch: source is missing deployed functions. " +
      "Do not deploy all functions until these are recovered or intentionally retired.",
  );
  process.exit(1);
}
