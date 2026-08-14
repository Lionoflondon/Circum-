"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const functionsDir = __dirname;

function productionSources() {
  return fs.readdirSync(functionsDir)
      .filter((file) => file.endsWith(".js") && !file.endsWith(".test.js"))
      .map((file) => ({
        file,
        source: fs.readFileSync(path.join(functionsDir, file), "utf8"),
      }));
}

function appCheckRuntimeNames(source) {
  const names = new Set();
  const pattern =
    /(?:const|let|var)\s+([A-Za-z0-9_]+)\s*=\s*functions\.runWith\(\{[^}]*enforceAppCheck:\s*true[^}]*\}\)/g;
  let match;
  while ((match = pattern.exec(source)) !== null) {
    names.add(match[1]);
  }
  return names;
}

function lineNumber(source, index) {
  return source.slice(0, index).split("\n").length;
}

test("all production callable functions enforce App Check", () => {
  const failures = [];
  for (const {file, source} of productionSources()) {
    const runtimes = appCheckRuntimeNames(source);
    const callables = /(?:functions|[A-Za-z0-9_]+)\.https\.onCall/g;
    let match;
    while ((match = callables.exec(source)) !== null) {
      const callee = match[0].split(".")[0];
      const nearby = source.slice(Math.max(0, match.index - 140), match.index);
      const direct =
        /functions\.runWith\(\{[^}]*enforceAppCheck:\s*true[^}]*\}\)[\s\S]{0,80}$/
            .test(nearby);
      const wrapped = callee !== "functions" && runtimes.has(callee);
      if (!direct && !wrapped) {
        failures.push(`${file}:${lineNumber(source, match.index)} ${match[0]}`);
      }
    }
  }

  assert.deepEqual(failures, []);
});
