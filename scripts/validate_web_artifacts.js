#!/usr/bin/env node
/* eslint-disable no-console */
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');

const surfaces = {
  public: {
    target: 'public',
    output: 'build/public_web',
    identity: 'circum-public-web',
    manifestName: 'Circum Public Web',
    must: ['circum-public-web', 'Earn as a Rider'],
    forbidden: [
      'circum-sender-web',
      'circum-rider-web',
      'Rider Application Centre',
      'Admin surface',
    ],
  },
  sender: {
    target: 'app',
    output: 'build/sender_app_web',
    identity: 'circum-sender-web',
    manifestName: 'Circum Sender App',
    must: ['circum-sender-web', 'Send a Parcel', 'Home', 'Wallet', 'Profile'],
    forbidden: [
      'circum-public-web',
      'circum-rider-web',
      'Earn as a Rider',
      'Rider Application Centre',
      'Admin surface',
    ],
  },
  admin: {
    target: 'admin',
    output: 'build/web_admin',
    identity: 'circum-admin-web',
    manifestName: 'Circum Admin',
    must: ['Admin surface'],
    forbidden: ['circum-public-web', 'circum-sender-web', 'circum-rider-web'],
  },
};

function fail(message) {
  console.error(`WEB ARTIFACT GATE FAILED: ${message}`);
  process.exit(1);
}

function readJson(relativePath) {
  return JSON.parse(fs.readFileSync(path.join(root, relativePath), 'utf8'));
}

function readIfExists(filePath) {
  return fs.existsSync(filePath) ? fs.readFileSync(filePath, 'utf8') : '';
}

function hostingEntries() {
  const config = readJson('firebase.json');
  return Array.isArray(config.hosting) ? config.hosting : [config.hosting];
}

function assertUniqueHostingOutputs() {
  const seen = new Map();
  for (const entry of hostingEntries()) {
    const output = entry.public;
    if (!output) fail(`hosting target ${entry.target || entry.site} has no public directory`);
    if (seen.has(output)) {
      fail(`hosting targets ${seen.get(output)} and ${entry.target || entry.site} share ${output}`);
    }
    seen.set(output, entry.target || entry.site);
  }
}

function assertFirebaseMapping(surface) {
  const entries = hostingEntries();
  for (const [name, spec] of Object.entries(surfaces)) {
    const entry = entries.find((item) => item.target === spec.target);
    if (!entry) fail(`missing Firebase hosting target ${spec.target}`);
    if (entry.public !== spec.output) {
      fail(`${name} target ${spec.target} points at ${entry.public}, expected ${spec.output}`);
    }
  }
  if (surface) {
    const spec = surfaces[surface];
    const entry = entries.find((item) => item.target === spec.target);
    if (entry.public !== spec.output) fail(`${surface} output mismatch`);
  }
}

function assertScriptIsolation() {
  const deployPublic = readIfExists(path.join(root, 'scripts/deploy_public_web.sh'));
  const deploySender = readIfExists(path.join(root, 'scripts/deploy_sender_app_web.sh'));
  if (!deployPublic.includes('hosting:public') || deployPublic.includes('hosting:app')) {
    fail('Public deploy script must target only hosting:public');
  }
  if (!deploySender.includes('hosting:app') || deploySender.includes('hosting:public')) {
    fail('Sender deploy script must target only hosting:app');
  }
}

function assertArtifact(surfaceName) {
  const spec = surfaces[surfaceName];
  const outDir = path.join(root, spec.output);
  if (!fs.existsSync(outDir)) fail(`${surfaceName} output does not exist: ${spec.output}`);

  const manifestPath = path.join(outDir, 'manifest.json');
  const markerPath = path.join(outDir, 'circum-surface.json');
  const indexPath = path.join(outDir, 'index.html');
  const jsPath = path.join(outDir, 'main.dart.js');
  const manifest = JSON.parse(readIfExists(manifestPath) || '{}');
  const marker = JSON.parse(readIfExists(markerPath) || '{}');
  const haystack = [
    readIfExists(indexPath),
    readIfExists(jsPath),
    readIfExists(markerPath),
    readIfExists(manifestPath),
  ].join('\n');

  if (manifest.name !== spec.manifestName) {
    fail(`${surfaceName} manifest name ${manifest.name} != ${spec.manifestName}`);
  }
  if (manifest.scope !== '/') fail(`${surfaceName} manifest scope must be /`);
  if (manifest.start_url !== '/') fail(`${surfaceName} manifest start_url must be /`);
  if (marker.identity !== spec.identity) {
    fail(`${surfaceName} marker identity ${marker.identity} != ${spec.identity}`);
  }
  for (const token of spec.must) {
    if (!haystack.includes(token)) fail(`${surfaceName} artifact missing marker ${token}`);
  }
  for (const token of spec.forbidden) {
    if (haystack.includes(token)) fail(`${surfaceName} artifact contains forbidden marker ${token}`);
  }
}

function parseArgs() {
  const surfaceArg = process.argv.find((arg) => arg.startsWith('--surface='));
  const configOnly = process.argv.includes('--config-only');
  if (!surfaceArg) return { surface: null, configOnly };
  const value = surfaceArg.split('=').slice(1).join('=');
  if (!surfaces[value]) fail(`unknown surface ${value}`);
  return { surface: value, configOnly };
}

const { surface, configOnly } = parseArgs();
assertUniqueHostingOutputs();
assertFirebaseMapping(surface);
assertScriptIsolation();
if (configOnly) {
  // Configuration-only mode intentionally skips generated build outputs.
} else if (surface) {
  assertArtifact(surface);
} else {
  for (const surfaceName of Object.keys(surfaces)) {
    if (fs.existsSync(path.join(root, surfaces[surfaceName].output))) {
      assertArtifact(surfaceName);
    }
  }
}
console.log(JSON.stringify({
  ok: true,
  checkedSurface: surface || 'configuration',
}, null, 2));
