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
const onlyIndex = process.argv.indexOf("--only");
const requested = onlyIndex >= 0 ? `${process.argv[onlyIndex + 1] || ""}`.split(",").filter(Boolean) : [];

if (unique.length !== names.length) {
  const duplicates = names.filter((name, index) => names.indexOf(name) !== index);
  console.error(`Duplicate function exports: ${[...new Set(duplicates)].join(", ")}`);
  process.exit(1);
}

if (unique.length === 0) {
  console.error("No Cloud Function exports found in server/functions/index.js.");
  process.exit(1);
}

if (requested.length) {
  const unknown = requested.filter((name) => !unique.includes(name));
  if (unknown.length) {
    console.error(`Unknown function exports: ${unknown.join(", ")}`);
    process.exit(1);
  }
  console.log(requested.map((name) => `functions:${name}`).join(","));
} else if (process.argv.includes("--count")) {
  console.log(unique.length);
} else if (process.argv.includes("--names")) {
  console.log(unique.join("\n"));
} else {
  console.log(unique.map((name) => `functions:${name}`).join(","));
}
