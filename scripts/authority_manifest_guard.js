#!/usr/bin/env node
/* eslint-disable no-console */
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const manifestPath = path.join(root, 'authority-manifest.json');
const indexPath = path.join(root, 'server/functions/index.js');

function fail(message, details = []) {
  console.error('AUTHORITY MANIFEST GUARD FAILED');
  console.error(message);
  for (const detail of details) console.error(`- ${detail}`);
  process.exit(1);
}

function exists(relativePath) {
  return fs.existsSync(path.join(root, relativePath));
}

const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
const indexSource = fs.readFileSync(indexPath, 'utf8');
const domains = manifest.domains || [];
const requiredDomainNames = [
  'Identity',
  'Recognition',
  'Address',
  'Route',
  'ETA',
  'IRIS',
  'Vanguard',
  'Quote',
  'Roth',
  'Payment',
  'Delivery creation',
  'Dispatch',
  'Tracking',
  'Lifecycle',
  'Adjudication',
  'Evidence',
  'Completion',
  'Earnings',
  'TP/rank',
  'Business',
  'Gifts',
  'Health+',
  'Chats',
  'Notifications',
  'Support',
  'Activity',
  'Receipts',
  'Cancellation',
  'Refunds',
  'Admin',
];

const findings = [];
if (manifest.version !== 1) findings.push('manifest.version must be 1');
if (!Array.isArray(manifest.allowedClientAuthority) || manifest.allowedClientAuthority.length < 4) {
  findings.push('allowedClientAuthority must explicitly preserve pure UI ownership');
}

const seen = new Set();
for (const domain of domains) {
  if (!domain.domain) findings.push('domain entry missing domain name');
  if (seen.has(domain.domain)) findings.push(`duplicate domain ${domain.domain}`);
  seen.add(domain.domain);

  for (const field of ['backendOwner', 'clientConsumers', 'requiredSecurity', 'requiredTests', 'clientAuthorityRemaining', 'status']) {
    if (domain[field] === undefined) findings.push(`${domain.domain || 'unknown'} missing ${field}`);
  }
  if (domain.clientAuthorityRemaining !== 'NONE') {
    findings.push(`${domain.domain} leaves material client authority: ${domain.clientAuthorityRemaining}`);
  }
  if (domain.status !== 'canonical') findings.push(`${domain.domain} status is not canonical`);
  if (!Array.isArray(domain.requiredSecurity) || domain.requiredSecurity.length === 0) {
    findings.push(`${domain.domain} must list required security`);
  }
  if (!Array.isArray(domain.requiredTests) || domain.requiredTests.length === 0) {
    findings.push(`${domain.domain} must list required tests`);
  }

  const owners = String(domain.backendOwner || '')
    .split(',')
    .map((owner) => owner.trim())
    .filter(Boolean);
  for (const owner of owners) {
    if (owner.endsWith('.js') && !exists(owner)) findings.push(`${domain.domain} backend owner missing: ${owner}`);
  }

  for (const callable of domain.requiredCallables || []) {
    const pattern = new RegExp(`exports\\.${callable}\\s*=`);
    if (!pattern.test(indexSource)) findings.push(`${domain.domain} required callable/export missing from index.js: ${callable}`);
  }
  for (const exportName of domain.requiredExports || []) {
    const pattern = new RegExp(`exports\\.${exportName}\\s*=`);
    if (!pattern.test(indexSource)) findings.push(`${domain.domain} required export missing from index.js: ${exportName}`);
  }

  for (const testName of domain.requiredTests || []) {
    const candidates = [
      `server/functions/${testName}`,
      `test/${testName}`,
      testName,
    ];
    if (!candidates.some(exists)) findings.push(`${domain.domain} required test missing: ${testName}`);
  }
}

for (const required of requiredDomainNames) {
  if (!seen.has(required)) findings.push(`required domain missing: ${required}`);
}

if (findings.length > 0) fail('Manifest contract is incomplete.', findings);

console.log(JSON.stringify({
  ok: true,
  version: manifest.version,
  domains: domains.length,
}, null, 2));
