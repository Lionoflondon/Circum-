#!/usr/bin/env node
/* eslint-disable no-console */
const fs = require('node:fs');
const path = require('node:path');
const cp = require('node:child_process');

const root = path.resolve(__dirname, '..');
const manifest = JSON.parse(fs.readFileSync(path.join(root, 'deploy-manifest.json'), 'utf8'));
const pubspec = fs.readFileSync(path.join(root, 'pubspec.yaml'), 'utf8');
const packageName = pubspec.match(/^name:\s*([A-Za-z0-9_]+)/m)?.[1] || 'circum';

function git(args) {
  return cp.execFileSync('git', args, {
    cwd: root,
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
  }).trim();
}

function listFiles() {
  const tracked = git(['ls-files']).split('\n').filter(Boolean);
  const untracked = git(['ls-files', '--others', '--exclude-standard'])
    .split('\n')
    .filter(Boolean)
    .filter((file) => file !== '.firebase/' && !file.startsWith('.firebase/'));
  return [...new Set([...tracked, ...untracked])]
    .filter((file) => fs.existsSync(path.join(root, file)))
    .sort();
}

function startsWithAny(file, prefixes = []) {
  return prefixes.some((prefix) => file === prefix || file.startsWith(prefix));
}

function ownersFor(file) {
  return Object.entries(manifest.products || {})
    .filter(([, product]) => startsWithAny(file, product.ownedPrefixes || []))
    .map(([name]) => name);
}

function category(file) {
  if (file.startsWith('assets/')) return 'assets';
  if (file.startsWith('scripts/')) return 'scripts';
  if (file.startsWith('test/')) return 'tests';
  if (file.startsWith('web/') || file.endsWith('manifest.json') || file.includes('Manifest')) {
    return 'manifests';
  }
  if (file.endsWith('firebase.json') || file.endsWith('.firebaserc') ||
      file.endsWith('pubspec.yaml') || file.endsWith('pubspec.lock') ||
      file.endsWith('analysis_options.yaml')) {
    return 'configs';
  }
  if (file.includes('service_worker')) return 'serviceWorkers';
  return 'projectFiles';
}

function read(file) {
  return fs.readFileSync(path.join(root, file), 'utf8');
}

function resolveImport(fromFile, specifier) {
  const packagePrefix = `package:${packageName}/`;
  if (specifier.startsWith(packagePrefix)) {
    const resolved = `lib/${specifier.slice(packagePrefix.length)}`;
    return fs.existsSync(path.join(root, resolved)) ? resolved : null;
  }
  if (!specifier.includes(':')) {
    const resolved = path.normalize(path.join(path.dirname(fromFile), specifier));
    return fs.existsSync(path.join(root, resolved)) ? resolved : null;
  }
  return null;
}

function dartImports(file) {
  if (!file.endsWith('.dart') || !fs.existsSync(path.join(root, file))) return [];
  const source = read(file);
  const imports = [];
  const pattern = /^\s*(?:import|export|part)\s+['"]([^'"]+)['"][^;]*;/gm;
  let match = pattern.exec(source);
  while (match) {
    const resolved = resolveImport(file, match[1]);
    if (resolved) imports.push(resolved);
    match = pattern.exec(source);
  }
  return imports;
}

function dependencyGraph(productName) {
  const product = manifest.products[productName];
  const pending = [...(product.entrypoints || [])];
  const seen = new Set();
  while (pending.length > 0) {
    const file = pending.pop();
    if (!file || seen.has(file) || !fs.existsSync(path.join(root, file))) continue;
    seen.add(file);
    for (const imported of dartImports(file)) {
      if (!seen.has(imported)) pending.push(imported);
    }
  }
  return seen;
}

function pairwiseIntersections(graphs) {
  const allowed = new Set((manifest.allowedDependencyIntersections || [])
    .flatMap((entry) => {
      const products = [...(entry.products || [])].sort().join('|');
      return (entry.files || []).map((file) => `${products}:${file}`);
    }));
  const entries = Object.entries(graphs);
  const intersections = [];
  for (let i = 0; i < entries.length; i += 1) {
    for (let j = i + 1; j < entries.length; j += 1) {
      const [leftName, leftFiles] = entries[i];
      const [rightName, rightFiles] = entries[j];
      const products = [leftName, rightName].sort().join('|');
      const overlap = [...leftFiles]
        .filter((file) => rightFiles.has(file))
        .filter((file) => !allowed.has(`${products}:${file}`))
        .sort();
      if (overlap.length > 0) {
        intersections.push({ products: [leftName, rightName], files: overlap });
      }
    }
  }
  return intersections;
}

const files = listFiles();
const ignored = manifest.ignoredPrefixes || [];
const sharedFiles = manifest.sharedFiles || [];
const ownership = {
  sharedFiles,
  unowned: [],
  multiOwned: [],
  ignoredProjectFiles: [],
};

for (const file of files) {
  const owners = ownersFor(file);
  if (owners.length === 0 && !startsWithAny(file, ignored)) ownership.unowned.push(file);
  if (owners.length > 1) ownership.multiOwned.push({ file, owners });
  if (startsWithAny(file, ignored)) ownership.ignoredProjectFiles.push(file);
}

const graphs = {};
for (const productName of Object.keys(manifest.products || {})) {
  graphs[productName] = dependencyGraph(productName);
}

const graphIntersections = pairwiseIntersections(graphs);
const sharedByCategory = {
  projectFiles: 0,
  assets: 0,
  scripts: 0,
  configs: 0,
  tests: 0,
  manifests: 0,
  serviceWorkers: 0,
};
for (const file of [
  ...sharedFiles,
  ...ownership.multiOwned.map((entry) => entry.file),
  ...ownership.ignoredProjectFiles,
]) {
  sharedByCategory[category(file)] += 1;
}

const report = {
  ok: sharedFiles.length === 0 &&
    ownership.unowned.length === 0 &&
    ownership.multiOwned.length === 0 &&
    ownership.ignoredProjectFiles.length === 0 &&
    graphIntersections.length === 0,
  products: Object.keys(manifest.products || {}),
  dependencyGraph: Object.fromEntries(
    Object.entries(graphs).map(([name, graph]) => [name, [...graph].sort()]),
  ),
  dependencyGraphIntersections: graphIntersections,
  intersectionCount: graphIntersections.reduce((count, entry) => count + entry.files.length, 0),
  sharedFileCount: sharedFiles.length + ownership.multiOwned.length + ownership.ignoredProjectFiles.length,
  sharedByCategory,
  ownership,
};

console.log(JSON.stringify(report, null, 2));
if (!report.ok) process.exit(1);
