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
  console.error('DEPLOYMENT BLOCKED');
  console.error(message);
  for (const detail of details) console.error(`- ${detail}`);
  process.exit(1);
}

function usage() {
  console.error('Usage: node scripts/deploy_guard.js --product|--target <website|sender-app|rider-app|admin|backend> [--base <ref>] [--head <ref>] [--ci]');
  process.exit(64);
}

const args = process.argv.slice(2);
let productIndex = args.indexOf('--product');
if (productIndex === -1) productIndex = args.indexOf('--target');
const baseIndex = args.indexOf('--base');
const headIndex = args.indexOf('--head');
const productArg = args.find((arg) => arg.startsWith('--product=') || arg.startsWith('--target='));
const baseArg = args.find((arg) => arg.startsWith('--base='));
const headArg = args.find((arg) => arg.startsWith('--head='));
const ciMode = args.includes('--ci');
if (productIndex === -1 && !productArg) usage();

const productName = productArg ? productArg.split('=')[1] : args[productIndex + 1];
const product = manifest.products[productName];
if (!product) fail(`Unknown product: ${productName}`);

const base = baseArg ? baseArg.split('=')[1] :
  (baseIndex === -1 ? (process.env.GUARD_BASE_SHA || 'HEAD') : args[baseIndex + 1]);
const head = headArg ? headArg.split('=')[1] :
  (headIndex === -1 ? (process.env.GUARD_HEAD_SHA || 'HEAD') : args[headIndex + 1]);
if (!base || !head) usage();

function git(args) {
  return cp.execFileSync('git', args, {
    cwd: root,
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
  }).trim();
}

function changedFiles() {
  return git(['diff', '--name-only', '--diff-filter=ACDMRTUXB', `${base}...${head}`])
    .split('\n')
    .filter(Boolean)
    .filter((file) => file !== '.firebase/' && !file.startsWith('.firebase/'));
}

function startsWithAny(file, prefixes) {
  return prefixes.some((prefix) => file === prefix || file.startsWith(prefix));
}

const changed = changedFiles();
const ownedForCi = changed.filter((file) => productName === 'backend' &&
  (file === 'firebase.json' ||
    file === '.github/workflows/rc1_release_build.yml' ||
    file === 'scripts/deploy_guard.js') ? false : true);
if (ciMode && !ownedForCi.some((file) => startsWithAny(file, product.ownedPrefixes))) {
  console.log(JSON.stringify({
    ok: true,
    skipped: true,
    product: productName,
    changedFiles: changed,
  }, null, 2));
  process.exit(0);
}
const blocked = changed.filter((file) => startsWithAny(file, manifest.blockedPrefixes || []));
if (blocked.length > 0) {
  fail('Blocked legacy deployment path changed.', blocked);
}

const offenders = changed.filter((file) => {
  if (startsWithAny(file, manifest.ignoredPrefixes || [])) return false;
  // firebase.json contains all Hosting targets; public-site redirect changes
  // are validated by the website deployment workflow and remain website-only.
  if (productName === 'website' && file === 'firebase.json') return false;
  // The guard itself may be maintained alongside a website-owned Hosting
  // change; protected architecture review remains the approval boundary.
  if (productName === 'website' && file === 'scripts/deploy_guard.js') return false;
  // The RC1 release workflow contains Sender Android AAB release steps
  // alongside repository orchestration; protected architecture review remains
  // the approval boundary for this narrow shared release-pipeline file.
  if (productName === 'sender-app' && file === '.github/workflows/rc1_release_build.yml') return false;
  if (productName === 'sender-app' && file === 'scripts/deploy_guard.js') return false;
  if (productName === 'backend' && file === 'firebase.json') return false;
  if (startsWithAny(file, product.forbiddenPrefixes)) return true;
  return !startsWithAny(file, product.ownedPrefixes) &&
    !manifest.sharedFiles.includes(file);
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
