/* eslint-disable max-len */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const functionsRoot = __dirname;
const forbidden = "functions." + "config(";
const failurePrefix = "Production " + forbidden + " usage found in: ";
const offenders = [];

function scan(directory) {
  for (const entry of fs.readdirSync(directory, {withFileTypes: true})) {
    if (entry.name === "node_modules") continue;
    const entryPath = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      scan(entryPath);
      continue;
    }
    if (!entry.isFile() || !entry.name.endsWith(".js") || entry.name.endsWith(".test.js")) continue;
    const source = fs.readFileSync(entryPath, "utf8");
    if (source.includes(forbidden)) {
      offenders.push(path.relative(functionsRoot, entryPath));
    }
  }
}

scan(functionsRoot);
assert.deepEqual(offenders, [], `${failurePrefix}${offenders.join(", ")}`);
