#!/usr/bin/env node
/* eslint-disable no-console */
"use strict";

const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(__dirname, "..");
const indexPath = path.join(root, "server/functions/index.js");
const source = fs.readFileSync(indexPath, "utf8");

function backendFiles() {
  return fs.readdirSync(path.join(root, "server/functions"), {withFileTypes: true})
      .filter((entry) => entry.isFile() && entry.name.endsWith(".js"))
      .map((entry) => `server/functions/${entry.name}`);
}

function resolveRequire(fromFile, request) {
  if (!request.startsWith(".")) return null;
  const base = path.resolve(root, path.dirname(fromFile), request);
  const candidates = [base, `${base}.js`, path.join(base, "index.js")];
  const match = candidates.find((candidate) => fs.existsSync(candidate) && fs.statSync(candidate).isFile());
  return match ? path.relative(root, match) : null;
}

function importsFor(file) {
  const text = fs.readFileSync(path.join(root, file), "utf8");
  const imports = new Set();
  const dynamic = [...text.matchAll(/require\(([^)]*)\)/g)]
      .filter((match) => !/^\s*["'][^"']+["']\s*$/.test(match[1]));
  if (dynamic.length) {
    throw new Error(`Dynamic require prevents safe scope resolution in ${file}`);
  }
  for (const match of text.matchAll(/require\(\s*["']([^"']+)["']\s*\)/g)) {
    const resolved = resolveRequire(file, match[1]);
    if (resolved) imports.add(resolved);
  }
  return imports;
}

function dependencyGraph() {
  const reverse = new Map();
  for (const file of backendFiles()) {
    for (const imported of importsFor(file)) {
      if (!reverse.has(imported)) reverse.set(imported, new Set());
      reverse.get(imported).add(file);
    }
  }
  return reverse;
}

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
    const resolved = resolveRequire("server/functions/index.js", `./${match[2]}`);
    if (resolved) aliases.set(resolved, match[1]);
  }
  const mapping = new Map();
  for (const match of source.matchAll(/exports\.([A-Za-z0-9_]+)\s*=\s*([A-Za-z0-9_]+)\.([A-Za-z0-9_]+)/g)) {
    const modulePath = [...aliases.entries()].find(([, alias]) => alias === match[2]);
    if (modulePath) mapping.set(modulePath[0], [...(mapping.get(modulePath[0]) || []), match[1]]);
  }
  for (const match of source.matchAll(/exports\.([A-Za-z0-9_]+)\s*=\s*([A-Za-z0-9_]+)\s*;/g)) {
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
const allowEmpty = process.argv.includes("--allow-empty");
if (changed.length && changed.every((file) => !file.startsWith("server/functions/"))) {
  process.exit(0);
}
if (changed.length === 0) {
  if (!allowEmpty) {
    console.error("No backend changes found; refusing an empty Functions deployment scope.");
    process.exit(3);
  }
  process.exit(0);
}
const base = argValue("--base") || "HEAD^";

const mapping = moduleExportMap();
const affected = new Set();
const runtimeDeclarationChanged = changed.includes("server/functions/package.json") ||
    changed.includes("server/functions/package-lock.json");
if (runtimeDeclarationChanged) {
  // A Functions runtime declaration applies to every exported Function.
  for (const name of unique) affected.add(name);
}
const reverse = dependencyGraph();
const impacted = new Set(changed);
const queue = [...changed];
while (queue.length) {
  const file = queue.shift();
  for (const importer of reverse.get(file) || []) {
    if (!impacted.has(importer)) {
      impacted.add(importer);
      queue.push(importer);
    }
  }
}
for (const file of impacted) {
  for (const name of mapping.get(file) || []) affected.add(name);
}

// For export wiring changes, deploy only newly/changed added exports. An
// index-only change with no explicit export line is intentionally blocked.
if (changed.includes("server/functions/index.js")) {
  for (const name of addedIndexExports(base)) affected.add(name);
}

if (affected.size === 0) {
  if (!allowEmpty) {
    console.error("Backend changes do not map to exported Functions; refusing deployment.");
    process.exit(3);
  }
  process.exit(0);
}

if (process.argv.includes("--count")) {
  console.log(affected.size);
} else if (process.argv.includes("--names")) {
  console.log([...affected].join("\n"));
} else {
  console.log([...affected].map((name) => `functions:${name}`).join(","));
}
