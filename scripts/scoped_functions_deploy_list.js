#!/usr/bin/env node
/* eslint-disable no-console */
"use strict";

const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(__dirname, "..");
const indexPath = path.join(root, "server/functions/index.js");
const source = fs.readFileSync(indexPath, "utf8");

const names = [...source.matchAll(/exports\.([A-Za-z0-9_]+)/g)]
    .map((match) => match[1]);
const unique = [...new Set(names)];

if (unique.length !== names.length) {
  const duplicates = names.filter((name, index) => names.indexOf(name) !== index);
  console.error(`Duplicate function exports: ${[...new Set(duplicates)].join(", ")}`);
  process.exit(1);
}

if (unique.length === 0) {
  console.error("No Cloud Function exports found in server/functions/index.js.");
  process.exit(1);
}

const onlyIndex = process.argv.indexOf("--only");
const onlyArg = process.argv.find((arg) => arg.startsWith("--only="));
const hasOnlyOption = onlyArg !== undefined || onlyIndex !== -1;
const requestedText = onlyArg ? onlyArg.slice("--only=".length) :
  (onlyIndex === -1 ? "" : process.argv[onlyIndex + 1] || "");
const requested = requestedText.split(",").map((name) => name.trim()).filter(Boolean);
if (hasOnlyOption && requested.length === 0) {
  console.error("--only requires at least one exported function name.");
  process.exit(1);
}
if (hasOnlyOption) {
  const unknown = requested.filter((name) => !unique.includes(name));
  if (unknown.length > 0) {
    console.error(`Unknown function exports: ${unknown.join(", ")}`);
    process.exit(1);
  }
  console.log([...new Set(requested)].map((name) => `functions:${name}`).join(","));
  process.exit(0);
}

if (process.argv.includes("--count")) {
  console.log(unique.length);
} else if (process.argv.includes("--names")) {
  console.log(unique.join("\n"));
} else {
  console.log(unique.map((name) => `functions:${name}`).join(","));
}
