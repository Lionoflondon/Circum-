"use strict";

const assert = require("node:assert/strict");
const childProcess = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");

const functionsDir = __dirname;
const script = path.join(functionsDir, "check-functions-inventory.js");
const indexSource = fs.readFileSync(path.join(functionsDir, "index.js"), "utf8");
const exportsList = [...indexSource.matchAll(/exports\.([A-Za-z0-9_]+)/g)]
    .map((match) => match[1]);

function runInventory(deployed, scope = "") {
  const temporaryDir = fs.mkdtempSync(path.join(os.tmpdir(), "circum-function-inventory-"));
  const deployedPath = path.join(temporaryDir, "deployed.json");
  fs.writeFileSync(deployedPath, JSON.stringify({result: deployed.map((id) => ({id}))}));
  const result = childProcess.spawnSync(process.execPath, [
    script,
    `--deployed-json=${deployedPath}`,
    ...(scope ? [`--scope=${scope}`] : []),
  ], {encoding: "utf8"});
  fs.rmSync(temporaryDir, {recursive: true, force: true});
  return result;
}

test("complete production inventory passes", () => {
  assert.equal(runInventory(exportsList).status, 0);
});

test("unscoped audit fails when deployed source is missing", () => {
  const result = runInventory([...exportsList, "orphanedProductionFunction"]);
  assert.equal(result.status, 1);
  assert.match(result.stderr, /Do not deploy all functions/);
});

test("scoped update of an existing production function remains safe", () => {
  const result = runInventory(
      [...exportsList, "orphanedProductionFunction"],
      `functions:${exportsList[0]}`,
  );
  assert.equal(result.status, 0);
  assert.match(result.stderr, /inventory mismatch remains/);
});

test("scope cannot silently recreate a source-only function", () => {
  const sourceOnly = exportsList[0];
  const result = runInventory(
      exportsList.filter((name) => name !== sourceOnly),
      `functions:${sourceOnly}`,
  );
  assert.equal(result.status, 1);
  assert.match(result.stderr, /Unsafe Functions scope/);
});
