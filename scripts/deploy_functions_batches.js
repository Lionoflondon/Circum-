#!/usr/bin/env node
/* eslint-disable no-console */
"use strict";

const {spawnSync} = require("node:child_process");

const DEFAULT_BATCH_SIZE = 10;
const args = process.argv.slice(2);
const projectIndex = args.indexOf("--project");
const project = projectIndex >= 0 ? args[projectIndex + 1] : "circum-2797c";
const batchIndex = args.indexOf("--batch-size");
const batchSize = Number(batchIndex >= 0 ? args[batchIndex + 1] : DEFAULT_BATCH_SIZE);
const retryFailed = !args.includes("--no-retry");
const dryRun = args.includes("--dry-run");

if (!project || !Number.isInteger(batchSize) || batchSize < 1) {
  console.error("Usage: deploy_functions_batches.js [--project PROJECT] [--batch-size N]");
  process.exit(2);
}

function functionNames() {
  const result = spawnSync(process.execPath, [
    require.resolve("./scoped_functions_deploy_list.js"),
    "--names",
  ], {encoding: "utf8"});
  if (result.status !== 0) {
    process.stderr.write(result.stderr || "Unable to build function list.\n");
    process.exit(result.status || 1);
  }
  return result.stdout.trim().split(/\r?\n/).filter(Boolean);
}

function deploy(batch, batchNumber, attempt) {
  const targets = batch.map((name) => `functions:${name}`).join(",");
  const startedAt = Date.now();
  console.log(`Deploying batch ${batchNumber} (${batch.length} functions), attempt ${attempt}`);
  console.log(`Targets: ${targets}`);
  if (dryRun) return true;
  const result = spawnSync("firebase", ["deploy", "--only", targets, "--project", project], {
    stdio: "inherit",
  });
  console.log(`Batch ${batchNumber} attempt ${attempt} ${result.status === 0 ? "succeeded" : "failed"} after ${((Date.now() - startedAt) / 1000).toFixed(1)}s.`);
  return result.status === 0;
}

const names = functionNames();
const batches = [];
for (let index = 0; index < names.length; index += batchSize) {
  batches.push(names.slice(index, index + batchSize));
}

console.log(`Preparing ${names.length} functions in ${batches.length} deterministic batches of at most ${batchSize}.`);
for (let index = 0; index < batches.length; index++) {
  const batchNumber = index + 1;
  if (deploy(batches[index], batchNumber, 1)) continue;
  console.error(`Batch ${batchNumber} failed.`);
  if (!retryFailed || !deploy(batches[index], batchNumber, 2)) {
    console.error(`Stopping after failed batch ${batchNumber}; later batches were not attempted.`);
    process.exit(1);
  }
  console.log(`Batch ${batchNumber} retry succeeded.`);
}

console.log("All function deployment batches completed successfully.");
