#!/usr/bin/env node
/* eslint-disable no-console */
"use strict";

const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(__dirname, "..");
const index = fs.readFileSync(path.join(root, "server/functions/index.js"), "utf8");
const exported = new Set([...index.matchAll(/exports\.([A-Za-z0-9_]+)/g)].map((match) => match[1]));
const input = process.argv[2] || "";
const names = input.split(",").map((value) => value.trim()).filter(Boolean);

if (!names.length || names.some((name) => !/^functions:[A-Za-z0-9_]+$/.test(name))) {
  console.error("Manual Functions scope must contain one or more functions:<export> targets.");
  process.exit(1);
}

const unknown = names.map((name) => name.slice("functions:".length))
    .filter((name) => !exported.has(name));
if (unknown.length) {
  console.error(`Unknown Function export(s): ${unknown.join(", ")}`);
  process.exit(1);
}

if (new Set(names).size !== names.length) {
  console.error("Manual Functions scope contains duplicates.");
  process.exit(1);
}

process.stdout.write(names.join(","));
