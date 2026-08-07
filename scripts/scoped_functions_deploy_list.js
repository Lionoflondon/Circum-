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

const requested = process.argv.includes("--functions") ?
  process.argv[process.argv.indexOf("--functions") + 1]
      .split(",")
      .map((name) => name.trim())
      .filter(Boolean) : null;

if (unique.length !== names.length) {
  const duplicates = names.filter((name, index) => names.indexOf(name) !== index);
  console.error(`Duplicate function exports: ${[...new Set(duplicates)].join(", ")}`);
  process.exit(1);
}

if (unique.length === 0) {
  console.error("No Cloud Function exports found in server/functions/index.js.");
  process.exit(1);
}

if (requested) {
  const unknown = requested.filter((name) => !unique.includes(name));
  if (unknown.length) {
    console.error(`Unknown Cloud Function export(s): ${unknown.join(", ")}`);
    process.exit(1);
  }
}

if (process.argv.includes("--count")) {
  console.log(unique.length);
} else if (process.argv.includes("--names")) {
  console.log(unique.join("\n"));
} else {
  const selected = requested || unique;
  console.log(selected.map((name) => `functions:${name}`).join(","));
}
