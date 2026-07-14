const assert = require("assert");
const fs = require("fs");
const path = require("path");
const test = require("node:test");

const {
  buildContracts,
  exportedNames,
  inventory,
} = require("../../tools/callable_contracts");

const root = path.resolve(__dirname, "..", "..");
const riderRoot = path.resolve(root, "..", "Circum-Rider");

function read(file) {
  return fs.readFileSync(file, "utf8");
}

function walk(dir, files = []) {
  if (!fs.existsSync(dir)) return files;
  for (const entry of fs.readdirSync(dir, {withFileTypes: true})) {
    if (["build", ".dart_tool", "node_modules", ".firebase", ".git"].includes(entry.name)) continue;
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full, files);
    else files.push(full);
  }
  return files;
}

test("client callable references are exported by the backend", () => {
  const inv = inventory();
  assert.deepStrictEqual(inv.missing, []);
});

test("exported callables remain represented in the callable contract", () => {
  const contractNames = new Set(buildContracts().map((item) => item.callableName));
  const missingFromContract = exportedNames().filter((name) => !contractNames.has(name));
  assert.deepStrictEqual(missingFromContract, []);
});

test("callable contracts retain required interface metadata", () => {
  for (const contract of buildContracts()) {
    assert.ok(contract.callableName, "callable name is required");
    assert.ok(contract.purpose, `${contract.callableName} purpose is required`);
    assert.ok(contract.owningBackendFile, `${contract.callableName} owner is required`);
    assert.ok(Array.isArray(contract.invokedBy), `${contract.callableName} invokedBy must be an array`);
    assert.ok(contract.inputSchema, `${contract.callableName} input schema is required`);
    assert.ok(contract.outputSchema, `${contract.callableName} output schema is required`);
    assert.ok(Array.isArray(contract.errorCodes), `${contract.callableName} error codes are required`);
    assert.ok(contract.authenticationRequirements, `${contract.callableName} auth requirements are required`);
    assert.ok(
      ["Canonical", "Legacy", "Deprecated", "Internal only"].includes(contract.classification),
      `${contract.callableName} has invalid classification ${contract.classification}`,
    );
    assert.ok(contract.deprecationStatus, `${contract.callableName} deprecation status is required`);
  }
});

test("clients do not probe multiple callable names for one action", () => {
  const files = [
    ...walk(path.join(root, "lib")),
    ...walk(path.join(riderRoot, "lib")),
  ].filter((file) => /\.(dart|js|ts|tsx|jsx)$/.test(file));
  const offenders = [];
  for (const file of files) {
    const source = read(file);
    if (
      /httpsCallable\(\s*name\s*\)/.test(source) &&
      (/for\s*\(\s*final\s+name\s+in\s+names\s*\)/.test(source) ||
        /List<String>\s+names/.test(source) ||
        /firstAvailable/i.test(source))
    ) {
      offenders.push(path.relative(root, file));
    }
  }
  assert.deepStrictEqual(offenders, []);
});

test("canonical Rider app uses the correctly spelled offer callable", () => {
  const source = read(path.join(riderRoot, "lib/app/home/bloc/home_bloc.dart"));
  assert.ok(source.includes("httpsCallable('getAvailableRequests')"));
  assert.ok(!source.includes("httpsCallable('getAvaliableRequests')"));
});
