#!/usr/bin/env node
/* eslint-disable no-console */
"use strict";

const childProcess = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");

const DEFAULT_ROOT = path.resolve(__dirname, "..");
const FUNCTIONS_PREFIX = "server/functions/";
const GLOBAL_RUNTIME_FILES = new Set([
  "server/functions/package.json",
  "server/functions/package-lock.json",
]);

function normalizePath(value) {
  return `${value || ""}`.replaceAll("\\", "/").replace(/^\.\//, "");
}

function isTestOnly(file) {
  const normalized = normalizePath(file);
  return normalized.endsWith(".test.js") ||
    normalized.includes("/__tests__/") ||
    normalized.startsWith("test/") ||
    normalized.startsWith("docs/") ||
    normalized.endsWith(".md");
}

function isRuntimeFunctionFile(file) {
  const normalized = normalizePath(file);
  return normalized.startsWith(FUNCTIONS_PREFIX) &&
    normalized.endsWith(".js") &&
    !isTestOnly(normalized);
}

function readText(file) {
  return fs.readFileSync(file, "utf8");
}

function resolveLocalModule(root, fromFile, request) {
  if (!request.startsWith(".")) return null;
  const base = path.resolve(path.dirname(fromFile), request);
  const candidates = [base, `${base}.js`, path.join(base, "index.js")];
  const match = candidates.find((candidate) => fs.existsSync(candidate) &&
    fs.statSync(candidate).isFile());
  return match ? normalizePath(path.relative(root, match)) : null;
}

function localRequires(root, relativeFile, source = null) {
  const absolute = path.join(root, relativeFile);
  const text = source == null ? readText(absolute) : source;
  const dependencies = new Set();
  for (const match of text.matchAll(/\brequire\(\s*["']([^"']+)["']\s*\)/g)) {
    const resolved = resolveLocalModule(root, absolute, match[1]);
    if (resolved) dependencies.add(resolved);
  }
  return dependencies;
}

function requireBindings(root, indexFile, source) {
  const bindings = new Map();
  const absolute = path.join(root, indexFile);
  const direct = /\b(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*require\(\s*["']([^"']+)["']\s*\)/g;
  for (const match of source.matchAll(direct)) {
    const resolved = resolveLocalModule(root, absolute, match[2]);
    if (resolved) bindings.set(match[1], resolved);
  }
  const destructured = /\b(?:const|let|var)\s*\{([^}]+)\}\s*=\s*require\(\s*["']([^"']+)["']\s*\)/g;
  for (const match of source.matchAll(destructured)) {
    const resolved = resolveLocalModule(root, absolute, match[2]);
    if (!resolved) continue;
    for (const item of match[1].split(",")) {
      const parts = item.trim().split(/\s*:\s*/);
      const localName = parts[1] || parts[0];
      if (/^[A-Za-z_$][\w$]*$/.test(localName)) bindings.set(localName, resolved);
    }
  }
  return bindings;
}

function assignmentEnd(source, start) {
  let round = 0;
  let square = 0;
  let curly = 0;
  let quote = null;
  let escaped = false;
  let lineComment = false;
  let blockComment = false;
  for (let index = start; index < source.length; index += 1) {
    const char = source[index];
    const next = source[index + 1];
    if (lineComment) {
      if (char === "\n") lineComment = false;
      continue;
    }
    if (blockComment) {
      if (char === "*" && next === "/") {
        blockComment = false;
        index += 1;
      }
      continue;
    }
    if (quote) {
      if (escaped) escaped = false;
      else if (char === "\\") escaped = true;
      else if (char === quote) quote = null;
      continue;
    }
    if (char === "/" && next === "/") {
      lineComment = true;
      index += 1;
      continue;
    }
    if (char === "/" && next === "*") {
      blockComment = true;
      index += 1;
      continue;
    }
    if (char === "\"" || char === "'" || char === "`") quote = char;
    else if (char === "(") round += 1;
    else if (char === ")") round -= 1;
    else if (char === "[") square += 1;
    else if (char === "]") square -= 1;
    else if (char === "{") curly += 1;
    else if (char === "}") curly -= 1;
    else if (char === ";" && round === 0 && square === 0 && curly === 0) return index + 1;
  }
  throw new Error("Could not parse an exports assignment in server/functions/index.js.");
}

function exportAssignments(source) {
  const assignments = new Map();
  const pattern = /\bexports\.([A-Za-z0-9_]+)\s*=/g;
  for (const match of source.matchAll(pattern)) {
    const start = match.index;
    const expressionStart = start + match[0].length;
    const end = assignmentEnd(source, expressionStart);
    const name = match[1];
    if (assignments.has(name)) throw new Error(`Duplicate Function export: ${name}`);
    assignments.set(name, {
      name,
      expression: source.slice(expressionStart, end - 1).trim(),
      start,
      end,
    });
  }
  if (assignments.size === 0) throw new Error("No Cloud Function exports found in server/functions/index.js.");
  return assignments;
}

function withoutExportAssignmentsAndRequires(source, assignments) {
  const characters = [...source];
  for (const assignment of assignments.values()) {
    characters.fill(" ", assignment.start, assignment.end);
  }
  const requireDeclaration = /\b(?:const|let|var)\s+(?:[A-Za-z_$][\w$]*|\{[^}]+\})\s*=\s*require\(\s*["'][^"']+["']\s*\)\s*;?/g;
  for (const match of source.matchAll(requireDeclaration)) {
    characters.fill(" ", match.index, match.index + match[0].length);
  }
  return characters.join("").replace(/\s+/g, " ").trim();
}

function setsEqual(left, right) {
  return left.size === right.size && [...left].every((value) => right.has(value));
}

function exportRoots(root, indexFile, source) {
  const assignments = exportAssignments(source);
  const bindings = requireBindings(root, indexFile, source);
  const roots = new Map();
  for (const [name, assignment] of assignments) {
    const dependencies = new Set();
    for (const identifier of assignment.expression.match(/[A-Za-z_$][\w$]*/g) || []) {
      if (bindings.has(identifier)) dependencies.add(bindings.get(identifier));
    }
    roots.set(name, dependencies);
  }
  return {assignments, roots};
}

function moduleClosure(root, moduleFile, memo, visiting = new Set()) {
  if (memo.has(moduleFile)) return memo.get(moduleFile);
  if (visiting.has(moduleFile)) return new Set([moduleFile]);
  visiting.add(moduleFile);
  const closure = new Set([moduleFile]);
  for (const dependency of localRequires(root, moduleFile)) {
    for (const nested of moduleClosure(root, dependency, memo, visiting)) closure.add(nested);
  }
  visiting.delete(moduleFile);
  memo.set(moduleFile, closure);
  return closure;
}

function buildDependencyGraph(root = DEFAULT_ROOT) {
  const indexFile = "server/functions/index.js";
  const indexSource = readText(path.join(root, indexFile));
  const {assignments, roots} = exportRoots(root, indexFile, indexSource);
  const memo = new Map();
  const exportDependencies = new Map();
  for (const [name, modules] of roots) {
    const dependencies = new Set();
    for (const moduleFile of modules) {
      for (const dependency of moduleClosure(root, moduleFile, memo)) dependencies.add(dependency);
    }
    exportDependencies.set(name, dependencies);
  }
  return {indexFile, indexSource, assignments, roots, exportDependencies};
}

function normalizeChangedFiles(changedFiles) {
  return [...new Set(changedFiles.map(normalizePath).filter(Boolean))].sort();
}

function calculateScope({
  root = DEFAULT_ROOT,
  changedFiles,
  baseIndexSource = null,
  renamedFiles = [],
  deletedFiles = [],
}) {
  const graph = buildDependencyGraph(root);
  const files = normalizeChangedFiles(changedFiles);
  const runtimeFiles = files.filter(isRuntimeFunctionFile);
  const globalFiles = files.filter((file) => GLOBAL_RUNTIME_FILES.has(file));
  const removedRuntime = deletedFiles.map(normalizePath).filter(isRuntimeFunctionFile);
  const renamedRuntime = renamedFiles.filter((entry) =>
    isRuntimeFunctionFile(entry.from) || isRuntimeFunctionFile(entry.to));
  if (removedRuntime.length) {
    throw new Error(`Removed runtime files require explicit deletion governance: ${removedRuntime.join(", ")}`);
  }
  if (renamedRuntime.length) {
    throw new Error(`Renamed runtime files require explicit scope review: ${renamedRuntime.map((item) => `${item.from} -> ${item.to}`).join(", ")}`);
  }

  const selected = new Map();
  let mode = "narrow";
  let broadReason = null;
  const removedExports = [];

  if (globalFiles.length) {
    mode = "broad";
    broadReason = `Global Functions dependency changed: ${globalFiles.join(", ")}`;
  }

  if (runtimeFiles.includes(graph.indexFile)) {
    if (baseIndexSource == null) {
      mode = "broad";
      broadReason = "server/functions/index.js changed without a comparable base; fail-closed broad scope";
    } else {
      const base = exportRoots(root, graph.indexFile, baseIndexSource);
      const currentNonExports = withoutExportAssignmentsAndRequires(graph.indexSource, graph.assignments);
      const baseNonExports = withoutExportAssignmentsAndRequires(baseIndexSource, base.assignments);
      if (currentNonExports !== baseNonExports) {
        mode = "broad";
        broadReason = "server/functions/index.js bootstrap/runtime code changed";
      } else {
        for (const [name, assignment] of graph.assignments) {
          const previous = base.assignments.get(name);
          const rootsChanged = previous && !setsEqual(
              graph.roots.get(name) || new Set(),
              base.roots.get(name) || new Set(),
          );
          if (!previous || rootsChanged || previous.expression.replace(/\s+/g, " ") !== assignment.expression.replace(/\s+/g, " ")) {
            selected.set(name, [previous ? "export wiring changed" : "new Function export"]);
          }
        }
        for (const name of base.assignments.keys()) {
          if (!graph.assignments.has(name)) removedExports.push(name);
        }
      }
    }
  }

  if (mode === "broad") {
    for (const name of graph.assignments.keys()) selected.set(name, [broadReason]);
  } else {
    for (const changedFile of runtimeFiles.filter((file) => file !== graph.indexFile)) {
      let matched = false;
      for (const [name, dependencies] of graph.exportDependencies) {
        if (!dependencies.has(changedFile)) continue;
        matched = true;
        const reasons = selected.get(name) || [];
        reasons.push(`${changedFile} is a runtime dependency`);
        selected.set(name, reasons);
      }
      if (!matched) {
        throw new Error(`Cannot determine a deployed export for changed runtime file: ${changedFile}`);
      }
    }
  }

  if (selected.size === 0) mode = "none";
  const selectedExports = [...selected.entries()]
      .sort(([left], [right]) => left.localeCompare(right))
      .map(([name, reasons]) => ({name, reasons: [...new Set(reasons)]}));
  return {
    schemaVersion: 1,
    mode,
    broadReason,
    changedFiles: files,
    selectedExports,
    removedExports: removedExports.sort(),
    targets: selectedExports.map(({name}) => `functions:${name}`),
    totalSourceExports: graph.assignments.size,
    untouchedExportCount: graph.assignments.size - selectedExports.length,
  };
}

function gitText(root, ref, file) {
  return childProcess.execFileSync("git", ["show", `${ref}:${file}`], {
    cwd: root,
    encoding: "utf8",
  });
}

function gitChanges(root, base, head) {
  const output = childProcess.execFileSync("git", ["diff", "--name-status", "-M", base, head], {
    cwd: root,
    encoding: "utf8",
  });
  const changedFiles = [];
  const deletedFiles = [];
  const renamedFiles = [];
  for (const line of output.split("\n").filter(Boolean)) {
    const [status, first, second] = line.split("\t");
    if (status.startsWith("R")) {
      renamedFiles.push({from: normalizePath(first), to: normalizePath(second)});
      changedFiles.push(second);
    } else {
      changedFiles.push(first);
      if (status === "D") deletedFiles.push(first);
    }
  }
  return {changedFiles, deletedFiles, renamedFiles};
}

function option(args, name, fallback = null) {
  const index = args.indexOf(name);
  return index >= 0 && args[index + 1] ? args[index + 1] : fallback;
}

function options(args) {
  const values = [];
  for (let index = 0; index < args.length; index += 1) {
    if (args[index] === "--changed-file" && args[index + 1]) values.push(args[index + 1]);
  }
  return values;
}

function runCli(args = process.argv.slice(2), root = DEFAULT_ROOT) {
  const base = option(args, "--base", "HEAD^");
  const head = option(args, "--head", "HEAD");
  const explicitFiles = options(args);
  const changes = explicitFiles.length ? {
    changedFiles: explicitFiles,
    deletedFiles: [],
    renamedFiles: [],
  } : gitChanges(root, base, head);
  let baseIndexSource = null;
  if (changes.changedFiles.map(normalizePath).includes("server/functions/index.js")) {
    baseIndexSource = gitText(root, base, "server/functions/index.js");
  }
  const manifest = {
    ...calculateScope({...changes, root, baseIndexSource}),
    base,
    head,
  };
  const manifestPath = option(args, "--manifest");
  if (manifestPath) {
    fs.writeFileSync(path.resolve(root, manifestPath), `${JSON.stringify(manifest, null, 2)}\n`);
  }
  const githubOutput = option(args, "--github-output");
  if (githubOutput) {
    fs.appendFileSync(githubOutput, [
      `has_functions=${manifest.targets.length > 0}`,
      `targets=${manifest.targets.join(",")}`,
      `selected_exports=${manifest.selectedExports.map(({name}) => name).join(",")}`,
      `scope_mode=${manifest.mode}`,
    ].join("\n") + "\n");
  }
  if (args.includes("--json")) console.log(JSON.stringify(manifest, null, 2));
  else if (args.includes("--count")) console.log(manifest.selectedExports.length);
  else if (args.includes("--names")) console.log(manifest.selectedExports.map(({name}) => name).join("\n"));
  else console.log(manifest.targets.join(","));
  return manifest;
}

if (require.main === module) {
  try {
    runCli();
  } catch (error) {
    console.error(`Functions deployment scope blocked: ${error.message}`);
    process.exit(1);
  }
}

module.exports = {
  buildDependencyGraph,
  calculateScope,
  exportAssignments,
  isRuntimeFunctionFile,
  isTestOnly,
  runCli,
};
