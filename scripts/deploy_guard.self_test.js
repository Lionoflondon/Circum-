#!/usr/bin/env node
/* eslint-disable no-console */
const fs = require('node:fs');
const path = require('node:path');
const cp = require('node:child_process');

const root = path.resolve(__dirname, '..');
const manifest = JSON.parse(
  fs.readFileSync(path.join(root, 'deploy-manifest.json'), 'utf8'),
);

function fail(message, details = []) {
  console.error('DEPLOY GUARD SELF-TEST FAILED');
  console.error(message);
  for (const detail of details) console.error(`- ${detail}`);
  process.exit(1);
}

function startsWithAny(file, prefixes) {
  return prefixes.some((prefix) => file === prefix || file.startsWith(prefix));
}

const products = manifest.products || {};
const sharedFiles = manifest.sharedFiles || [];
const blockedPrefixes = manifest.blockedPrefixes || [];
const ignoredPrefixes = manifest.ignoredPrefixes || [];

if (sharedFiles.length !== 0) {
  fail(`sharedFiles has ${sharedFiles.length} entries; absolute product ownership requires 0`, sharedFiles);
}

const productNames = Object.keys(products);
if (productNames.length === 0) fail('manifest has no products');

const duplicatePrefixes = [];
for (let i = 0; i < productNames.length; i += 1) {
  for (let j = i + 1; j < productNames.length; j += 1) {
    const leftName = productNames[i];
    const rightName = productNames[j];
    for (const left of products[leftName].ownedPrefixes || []) {
      for (const right of products[rightName].ownedPrefixes || []) {
        if (left === right || left.startsWith(right) || right.startsWith(left)) {
          duplicatePrefixes.push(`${leftName}:${left} overlaps ${rightName}:${right}`);
        }
      }
    }
  }
}
if (duplicatePrefixes.length > 0) {
  fail('overlapping owned prefixes found', duplicatePrefixes);
}

const contradictoryPrefixes = [];
for (const [name, product] of Object.entries(products)) {
  for (const owned of product.ownedPrefixes || []) {
    for (const forbidden of product.forbiddenPrefixes || []) {
      if (owned === forbidden || owned.startsWith(forbidden) || forbidden.startsWith(owned)) {
        contradictoryPrefixes.push(`${name}:${owned} conflicts with forbidden ${forbidden}`);
      }
    }
  }
}
if (contradictoryPrefixes.length > 0) {
  fail('owned prefixes conflict with forbidden prefixes', contradictoryPrefixes);
}

const tracked = cp
  .execFileSync('git', ['ls-files'], { cwd: root, encoding: 'utf8' })
  .split('\n')
  .filter(Boolean);
const untracked = cp
  .execFileSync('git', ['ls-files', '--others', '--exclude-standard'], {
    cwd: root,
    encoding: 'utf8',
  })
  .split('\n')
  .filter(Boolean)
  .filter((file) => file !== '.firebase/' && !file.startsWith('.firebase/'));
const repositoryFiles = [...new Set([...tracked, ...untracked])];

const unowned = [];
const multiOwned = [];
for (const file of repositoryFiles) {
  if (sharedFiles.includes(file)) continue;
  if (startsWithAny(file, blockedPrefixes)) continue;
  if (startsWithAny(file, ignoredPrefixes)) continue;

  const owners = productNames.filter((name) =>
    startsWithAny(file, products[name].ownedPrefixes || []),
  );
  if (owners.length === 0) unowned.push(file);
  if (owners.length > 1) multiOwned.push(`${file}: ${owners.join(', ')}`);
}

if (unowned.length > 0) fail('tracked files without product owner', unowned);
if (multiOwned.length > 0) fail('tracked files with duplicate owners', multiOwned);

console.log(JSON.stringify({
  ok: true,
  products: productNames,
  sharedFiles,
  blockedPrefixes,
  ignoredPrefixes,
  trackedFiles: tracked.length,
  untrackedFiles: untracked.length,
}, null, 2));
