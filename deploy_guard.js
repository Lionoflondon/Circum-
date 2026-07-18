#!/usr/bin/env node
/* eslint-disable no-console */
const fs = require('node:fs');
const path = require('node:path');
const cp = require('node:child_process');

const root = __dirname;
const manifest = JSON.parse(
  fs.readFileSync(path.join(root, 'deploy-manifest.json'), 'utf8'),
);

function fail(message, details = []) {
  console.error('DEPLOYMENT BLOCKED');
  console.error(message);
  for (const detail of details) console.error(`- ${detail}`);
  process.exit(1);
}

function usage() {
  console.error('Usage: node deploy_guard.js --product <website|sender-app|admin|backend> [--base <ref>]');
  process.exit(64);
}

const args = process.argv.slice(2);
const productIndex = args.indexOf('--product');
const baseIndex = args.indexOf('--base');
if (productIndex === -1 || !args[productIndex + 1]) usage();

const productName = args[productIndex + 1];
const product = manifest.products[productName];
if (!product) fail(`Unknown product: ${productName}`);

const base = baseIndex === -1 ? 'HEAD' : args[baseIndex + 1];
if (!base) usage();

function git(args) {
  return cp.execFileSync('git', args, {
    cwd: root,
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
  }).trim();
}

function changedFiles() {
  const diff = git(['diff', '--name-only', `${base}...HEAD`]);
  const working = git(['status', '--porcelain=v1', '--untracked-files=all'])
    .split('\n')
    .filter(Boolean)
    .flatMap((line) => {
      const file = line.replace(/^[ MADRCU?!]{1,2}\s+/, '').trim();
      if (file.includes(' -> ')) return file.split(' -> ').map((part) => part.trim());
      return [file];
    })
    .filter((file) => file !== '.firebase/' && !file.startsWith('.firebase/'));
  return [...new Set([...diff.split('\n').filter(Boolean), ...working])];
}

function startsWithAny(file, prefixes) {
  return prefixes.some((prefix) => file === prefix || file.startsWith(prefix));
}

const changed = changedFiles();
const offenders = changed.filter((file) => {
  if (startsWithAny(file, product.forbiddenPrefixes)) return true;
  return !startsWithAny(file, product.ownedPrefixes) &&
    !['pubspec.yaml', 'pubspec.lock', 'README.md', 'deploy_guard.js', 'deploy-manifest.json'].includes(file);
});

if (offenders.length > 0) {
  fail('Cross-application contamination detected.', offenders);
}

const sourceFiles = git(['ls-files', 'lib']).split('\n').filter(Boolean);
if (productName === 'sender-app') {
  const websiteImports = sourceFiles
    .filter((file) => file === 'lib/main.dart' || file.startsWith('lib/app/sender_mobile/'))
    .filter((file) => fs.readFileSync(path.join(root, file), 'utf8').includes('website/'));
  if (websiteImports.length > 0) {
    fail('Sender App imports Website code.', websiteImports);
  }
}

if (productName === 'website') {
  const mobileImports = sourceFiles
    .filter((file) => file.startsWith('lib/website/') || file === 'lib/main_public_web.dart')
    .filter((file) => fs.readFileSync(path.join(root, file), 'utf8').includes('app/sender_mobile/'));
  if (mobileImports.length > 0) {
    fail('Website imports Sender mobile code.', mobileImports);
  }
}

console.log(JSON.stringify({
  ok: true,
  product: productName,
  changedFiles: changed,
}, null, 2));
