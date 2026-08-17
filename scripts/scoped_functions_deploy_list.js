#!/usr/bin/env node
/* eslint-disable no-console */
"use strict";

const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(__dirname, "..");
const indexPath = path.join(root, "server/functions/index.js");
const source = fs.readFileSync(indexPath, "utf8");

function argValue(name) {
  const index = process.argv.indexOf(name);
  return index === -1 ? "" : process.argv[index + 1] || "";
}

function changedPaths() {
  if (process.argv.includes("--files")) return argValue("--files").split(",").filter(Boolean);
  const base = argValue("--base") || "HEAD^";
  const output = require("node:child_process").execFileSync("git", [
    "diff", "--name-only", `${base}...HEAD`, "--", "server/functions",
  ], {cwd: root, encoding: "utf8"});
  return output.split(/\r?\n/).filter(Boolean);
}

function addedIndexExports(base) {
  const output = require("node:child_process").execFileSync("git", [
    "diff", "--unified=0", `${base}...HEAD`, "--", "server/functions/index.js",
  ], {cwd: root, encoding: "utf8"});
  return [...output.matchAll(/^\+\s*exports\.([A-Za-z0-9_]+)/gm)].map((match) => match[1]);
}

function moduleExportMap() {
  const aliases = new Map();
  for (const match of source.matchAll(/const ([A-Za-z0-9_]+) = require\("\.\/([^\"]+)"\);/g)) {
    aliases.set(`server/functions/${match[2]}.js`, match[1]);
  }
  const mapping = new Map();
  for (const match of source.matchAll(/exports\.([A-Za-z0-9_]+)\s*=\s*([A-Za-z0-9_]+)\.([A-Za-z0-9_]+)/g)) {
    const modulePath = [...aliases.entries()].find(([, alias]) => alias === match[2]);
    if (modulePath) mapping.set(modulePath[0], [...(mapping.get(modulePath[0]) || []), match[1]]);
  }
  return mapping;
}

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

const changed = changedPaths();
if (changed.length === 0) process.exit(0);
const base = argValue("--base") || "HEAD^";

const mapping = moduleExportMap();
const affected = new Set();
for (const file of changed) {
  for (const name of mapping.get(file) || []) affected.add(name);
}

// For export wiring changes, deploy only newly/changed added exports. An
// index-only change with no explicit export line is intentionally blocked.
if (changed.includes("server/functions/index.js")) {
  for (const name of addedIndexExports(base)) affected.add(name);
}

if (affected.size === 0) process.exit(0);

if (process.argv.includes("--count")) {
  console.log(affected.size);
} else if (process.argv.includes("--names")) {
  console.log([...affected].join("\n"));
} else {
  console.log([...affected].map((name) => `functions:${name}`).join(","));
}
