"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");

const {calculateScope} = require("./scoped_functions_deploy_list");

function fixture(files = {}) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "circum-scope-"));
  for (const [file, source] of Object.entries(files)) {
    const target = path.join(root, file);
    fs.mkdirSync(path.dirname(target), {recursive: true});
    fs.writeFileSync(target, source);
  }
  return root;
}

function baseFixture(extra = {}) {
  return fixture({
    "server/functions/index.js": [
      'const address = require("./free-address-search");',
      'const alerts = require("./alerts");',
      "exports.searchFreeUkAddresses = address.searchFreeUkAddresses;",
      "exports.resolveUkAddressPlace = address.resolveUkAddressPlace;",
      "exports.sendAlert = alerts.sendAlert;",
    ].join("\n"),
    "server/functions/free-address-search.js": [
      'const core = require("./free-address-core");',
      "exports.searchFreeUkAddresses = core.search;",
      "exports.resolveUkAddressPlace = core.resolve;",
    ].join("\n"),
    "server/functions/free-address-core.js": "exports.search = () => []; exports.resolve = () => ({});",
    "server/functions/alerts.js": "exports.sendAlert = () => null;",
    ...extra,
  });
}

function names(scope) {
  return scope.selectedExports.map(({name}) => name);
}

test("address implementation selects only its two exports", () => {
  const root = baseFixture();
  assert.deepEqual(names(calculateScope({
    root,
    changedFiles: ["server/functions/free-address-search.js"],
  })), ["resolveUkAddressPlace", "searchFreeUkAddresses"]);
});

test("address core follows transitive dependencies", () => {
  const root = baseFixture();
  assert.deepEqual(names(calculateScope({
    root,
    changedFiles: ["server/functions/free-address-core.js"],
  })), ["resolveUkAddressPlace", "searchFreeUkAddresses"]);
});

test("test and documentation changes deploy no Functions", () => {
  const root = baseFixture();
  const scope = calculateScope({
    root,
    changedFiles: ["server/functions/free-address-core.test.js", "docs/address.md"],
  });
  assert.equal(scope.mode, "none");
  assert.deepEqual(scope.targets, []);
});

test("a single implementation selects exactly its export", () => {
  const root = baseFixture();
  assert.deepEqual(names(calculateScope({
    root,
    changedFiles: ["server/functions/alerts.js"],
  })), ["sendAlert"]);
});

test("a shared helper selects every and only dependent export", () => {
  const root = baseFixture({
    "server/functions/shared.js": "exports.value = 1;",
    "server/functions/free-address-core.js": 'require("./shared"); exports.search = () => []; exports.resolve = () => ({});',
    "server/functions/alerts.js": 'require("./shared"); exports.sendAlert = () => null;',
  });
  assert.deepEqual(names(calculateScope({
    root,
    changedFiles: ["server/functions/shared.js"],
  })), ["resolveUkAddressPlace", "searchFreeUkAddresses", "sendAlert"]);
});

test("global dependency changes are explicitly broad", () => {
  const root = baseFixture({"server/functions/package.json": "{}"});
  const scope = calculateScope({
    root,
    changedFiles: ["server/functions/package.json"],
  });
  assert.equal(scope.mode, "broad");
  assert.match(scope.broadReason, /Global Functions dependency/);
  assert.equal(scope.selectedExports.length, 3);
});

test("unknown runtime modules fail closed", () => {
  const root = baseFixture({"server/functions/orphan.js": "exports.value = true;"});
  assert.throws(() => calculateScope({
    root,
    changedFiles: ["server/functions/orphan.js"],
  }), /Cannot determine a deployed export/);
});

test("new export wiring selects the new Function without broadening", () => {
  const root = baseFixture({"server/functions/new-task.js": "exports.run = () => null;"});
  const baseIndexSource = readWithout(root, "exports.newTask");
  fs.appendFileSync(path.join(root, "server/functions/index.js"), [
    '\nconst newTask = require("./new-task");',
    "\nexports.newTask = newTask.run;\n",
  ].join(""));
  const scope = calculateScope({
    root,
    changedFiles: ["server/functions/index.js", "server/functions/new-task.js"],
    baseIndexSource,
  });
  assert.deepEqual(names(scope), ["newTask"]);
});

test("removed exports are recorded but never deleted implicitly", () => {
  const root = baseFixture();
  const current = fs.readFileSync(path.join(root, "server/functions/index.js"), "utf8");
  const baseIndexSource = `${current}\nexports.retiredTask = alerts.sendAlert;\n`;
  const scope = calculateScope({
    root,
    changedFiles: ["server/functions/index.js"],
    baseIndexSource,
  });
  assert.deepEqual(scope.targets, []);
  assert.deepEqual(scope.removedExports, ["retiredTask"]);
});

test("runtime renames require explicit review", () => {
  const root = baseFixture();
  assert.throws(() => calculateScope({
    root,
    changedFiles: ["server/functions/alerts.js"],
    renamedFiles: [{from: "server/functions/old-alerts.js", to: "server/functions/alerts.js"}],
  }), /Renamed runtime files require explicit scope review/);
});

test("index bootstrap changes are explicitly broad", () => {
  const root = baseFixture();
  const baseIndexSource = fs.readFileSync(path.join(root, "server/functions/index.js"), "utf8");
  fs.writeFileSync(path.join(root, "server/functions/index.js"), `const boot = true;\n${baseIndexSource}`);
  const scope = calculateScope({
    root,
    changedFiles: ["server/functions/index.js"],
    baseIndexSource,
  });
  assert.equal(scope.mode, "broad");
  assert.match(scope.broadReason, /bootstrap\/runtime/);
});

function readWithout(root, fragment) {
  return fs.readFileSync(path.join(root, "server/functions/index.js"), "utf8")
      .split("\n")
      .filter((line) => !line.includes(fragment))
      .join("\n");
}
