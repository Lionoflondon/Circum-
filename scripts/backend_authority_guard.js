#!/usr/bin/env node
/* eslint-disable no-console */
const fs = require('node:fs');
const path = require('node:path');
const cp = require('node:child_process');

const root = path.resolve(__dirname, '..');

const operationalCollections = new Set([
  'adminAuditLogs',
  'adminUsers',
  'businessAccounts',
  'businessAuditLogs',
  'businessInvoices',
  'businessJoinRequests',
  'businessMemberships',
  'businessNotifications',
  'businessPayments',
  'businessSubscriptions',
  'business_wallets',
  'chats',
  'deliveryAdjustments',
  'deliveryRequests',
  'deliveries',
  'driverPerformanceMetrics',
  'driverRatings',
  'giftCampaigns',
  'giftDeliveries',
  'giftOrders',
  'giftRequests',
  'giftStories',
  'healthPlusBookings',
  'healthPlusCheckouts',
  'healthPlusCustodyArchive',
  'healthPlusNotifications',
  'healthPlusProfiles',
  'healthPlusUsageEvents',
  'history',
  'irisLearning',
  'irisReviews',
  'iris_learning',
  'notifications',
  'payments',
  'prescriptionPickups',
  'rateLimits',
  'recognition',
  'recurringPickupSchedules',
  'riderApplications',
  'riderDocuments',
  'riderEarnings',
  'riderProfiles',
  'riders',
  'rothLedger',
  'supportConversations',
  'supportTickets',
  'users',
  'wallet',
  'walletLedger',
  'walletTransactions',
  'wallets',
  'websiteVisitors',
]);

const clientRoots = [
  'lib/app/',
  'lib/website/',
  'lib/main.dart',
  'lib/main_public_web.dart',
  'lib/main_admin_web.dart',
];

const clientOwnedCollections = new Set([]);

function usage() {
  console.error(
    'Usage: node scripts/backend_authority_guard.js [--base <ref> | --all | --files <file...>]',
  );
  process.exit(64);
}

function git(args, options = {}) {
  return cp.execFileSync('git', args, {
    cwd: root,
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
    ...options,
  }).trim();
}

function hasRef(ref) {
  try {
    git(['rev-parse', '--verify', ref], { stdio: ['ignore', 'ignore', 'ignore'] });
    return true;
  } catch (_) {
    return false;
  }
}

function defaultBase() {
  if (process.env.GITHUB_BASE_REF) return `origin/${process.env.GITHUB_BASE_REF}`;
  if (hasRef('HEAD~1')) return 'HEAD~1';
  return 'HEAD';
}

function changedFiles(base) {
  let diff = '';
  try {
    diff = git(['diff', '--name-only', `${base}...HEAD`]);
  } catch (_) {
    diff = git(['diff', '--name-only', base, 'HEAD']);
  }

  const working = git(['status', '--porcelain=v1', '--untracked-files=all'])
    .split('\n')
    .filter(Boolean)
    .flatMap((line) => {
      const file = line.replace(/^[ MADRCU?!]{1,2}\s+/, '').trim();
      if (file.includes(' -> ')) return file.split(' -> ').map((part) => part.trim());
      return [file];
    });

  return [...new Set([...diff.split('\n').filter(Boolean), ...working])];
}

function isClientDartFile(file) {
  return file.endsWith('.dart') &&
    clientRoots.some((prefix) => file === prefix || file.startsWith(prefix));
}

function trackedClientFiles() {
  return git(['ls-files', 'lib'])
    .split('\n')
    .filter(Boolean)
    .filter(isClientDartFile);
}

function parseArgs() {
  const args = process.argv.slice(2);
  const all = args.includes('--all');
  const filesIndex = args.indexOf('--files');
  const baseIndex = args.indexOf('--base');
  const baseArg = args.find((arg) => arg.startsWith('--base='));

  if (all && filesIndex !== -1) usage();
  if (filesIndex !== -1 && (baseIndex !== -1 || baseArg)) usage();

  if (filesIndex !== -1) {
    const files = args.slice(filesIndex + 1);
    if (files.length === 0) usage();
    return {mode: 'files', files};
  }

  if (all) return {mode: 'all', files: trackedClientFiles()};

  const base = baseArg ? baseArg.split('=')[1] : (baseIndex === -1 ? defaultBase() : args[baseIndex + 1]);
  if (!base) usage();
  return {mode: 'changed', base, files: changedFiles(base)};
}

function collectionName(line) {
  const match = line.match(/\.collection\s*\(\s*['"`]([^'"`]+)['"`]\s*\)/);
  return match ? match[1] : null;
}

function statementFrom(lines, startIndex) {
  const statement = [];
  for (let index = startIndex; index < Math.min(lines.length, startIndex + 32); index += 1) {
    statement.push(lines[index]);
    if (lines[index].includes(';')) break;
  }
  return statement.join('\n');
}

function hasWriteCall(lines, startIndex) {
  return /\.(set|update|add|delete)\s*\(/.test(statementFrom(lines, startIndex));
}

function hasAllowComment(lines, startIndex) {
  const window = lines
    .slice(Math.max(0, startIndex - 3), Math.min(lines.length, startIndex + 3))
    .join('\n');
  return /backend-authority:\s*client-owned/.test(window);
}

function inspectFile(file) {
  if (!isClientDartFile(file)) return [];

  const absolute = path.join(root, file);
  if (!fs.existsSync(absolute)) return [];

  const text = fs.readFileSync(absolute, 'utf8');
  const lines = text.split(/\r?\n/);
  const findings = [];

  for (let index = 0; index < lines.length; index += 1) {
    const collection = collectionName(lines[index]);
    if (!collection || clientOwnedCollections.has(collection)) continue;
    if (!operationalCollections.has(collection)) continue;
    if (!hasWriteCall(lines, index)) continue;
    if (hasAllowComment(lines, index)) continue;

    findings.push({
      file,
      line: index + 1,
      collection,
      text: lines[index].trim(),
    });
  }

  return findings;
}

const {mode, base, files} = parseArgs();
const findings = files.flatMap(inspectFile);

if (findings.length > 0) {
  console.error('BACKEND AUTHORITY GUARD FAILED');
  console.error('Client code is introducing direct operational Firestore writes.');
  console.error('Move the mutation to a callable or server trigger, then keep the client as a realtime read surface.');
  for (const finding of findings) {
    console.error(`- ${finding.file}:${finding.line} collection=${finding.collection} ${finding.text}`);
  }
  process.exit(1);
}

console.log(JSON.stringify({
  ok: true,
  mode,
  base,
  checkedFiles: files.filter(isClientDartFile),
}, null, 2));
