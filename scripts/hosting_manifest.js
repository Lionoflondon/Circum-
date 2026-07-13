#!/usr/bin/env node

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const childProcess = require('child_process');

const PROJECT = 'circum-2797c';
const CONFIGS = Object.freeze({
  admin: Object.freeze({
    product: 'Circum Admin Portal',
    buildIdentity: 'CIRCUM_BUILD_ID=admin',
    targetAlias: 'admin',
    siteId: 'circum-admin-2797c',
    outputDirectory: 'build/web_admin',
    requiredBundleMarkers: [
      'CIRCUM_ADMIN_PORTAL_CANONICAL_V1',
      'Employee access only. Sign in with an account that has a Circum admin role.',
    ],
    forbiddenBundleMarkers: [
      'CIRCUM_BUILD_ID=public-sender',
      'Send anything across town',
      'sender-root',
    ],
  }),
  public: Object.freeze({
    product: 'Circum Public Sender Website',
    buildIdentity: 'CIRCUM_BUILD_ID=public-sender',
    targetAlias: 'public',
    siteId: 'circum-2797c',
    outputDirectory: 'build/web_main',
    requiredBundleMarkers: ['Send anything across town'],
    forbiddenBundleMarkers: [
      'CIRCUM_BUILD_ID=admin',
      'CIRCUM_ADMIN_PORTAL_CANONICAL_V1',
      'Employee access only. Sign in with an account that has a Circum admin role.',
      'admin-root',
    ],
  }),
  sender: Object.freeze({
    product: 'Circum Sender App',
    buildIdentity: 'CIRCUM_BUILD_ID=sender-app',
    targetAlias: 'sender',
    siteId: 'circum-app-2797c',
    outputDirectory: 'build/web_sender',
    requiredBundleMarkers: [
      'sender-root',
    ],
    forbiddenBundleMarkers: [
      'CIRCUM_BUILD_ID=admin',
      'CIRCUM_ADMIN_PORTAL_CANONICAL_V1',
      'Employee access only. Sign in with an account that has a Circum admin role.',
      'admin-root',
    ],
  }),
  rider: Object.freeze({
    product: 'Circum Rider Web',
    buildIdentity: 'CIRCUM_BUILD_ID=rider-web',
    targetAlias: 'rider',
    siteId: 'circum-rider-2797c',
    outputDirectory: 'build/web_rider',
    requiredBundleMarkers: [
      'rider-web-root',
      'Earn as a Rider',
      'Rider details',
    ],
    forbiddenBundleMarkers: [
      'CIRCUM_BUILD_ID=admin',
      'CIRCUM_ADMIN_PORTAL_CANONICAL_V1',
      'Employee access only. Sign in with an account that has a Circum admin role.',
      'admin-root',
    ],
  }),
});

function fail(message) {
  throw new Error(`Hosting deployment blocked: ${message}`);
}

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

function sha256Files(files) {
  const hash = crypto.createHash('sha256');
  for (const file of files) {
    hash.update(path.basename(file));
    hash.update(fs.readFileSync(file));
  }
  return hash.digest('hex');
}

function gitValue(args) {
  return childProcess.execFileSync('git', args, { encoding: 'utf8' }).trim();
}

function validateFirebaseConfiguration(root = process.cwd()) {
  const firebaserc = readJson(path.join(root, '.firebaserc'));
  const firebase = readJson(path.join(root, 'firebase.json'));
  if (firebaserc.projects?.default !== PROJECT) {
    fail(`default Firebase project must be ${PROJECT}`);
  }
  const targetMap = firebaserc.targets?.[PROJECT]?.hosting;
  if (!targetMap) fail('hosting target aliases are missing from .firebaserc');

  for (const config of Object.values(CONFIGS)) {
    const sites = targetMap[config.targetAlias];
    if (!Array.isArray(sites) || sites.length !== 1 || sites[0] !== config.siteId) {
      fail(`hosting:${config.targetAlias} must map only to ${config.siteId}`);
    }
  }
  const values = Object.values(CONFIGS);
  const adminConfig = CONFIGS.admin;
  for (const config of values) {
    if (config !== adminConfig && adminConfig.siteId === config.siteId) {
      fail('Admin and customer-facing site IDs must differ');
    }
    if (config !== adminConfig &&
        adminConfig.outputDirectory === config.outputDirectory) {
      fail('Admin and customer-facing output directories must differ');
    }
  }
  if (CONFIGS.public.siteId === CONFIGS.sender.siteId) {
    fail('Public and Sender app site IDs must differ');
  }
  if (CONFIGS.public.outputDirectory === CONFIGS.sender.outputDirectory) {
    fail('Public and Sender app output directories must differ');
  }
  if (CONFIGS.rider.siteId === CONFIGS.sender.siteId ||
      CONFIGS.rider.siteId === CONFIGS.public.siteId ||
      CONFIGS.rider.siteId === CONFIGS.admin.siteId) {
    fail('Rider Web site ID must be isolated');
  }
  if (CONFIGS.rider.outputDirectory === CONFIGS.sender.outputDirectory ||
      CONFIGS.rider.outputDirectory === CONFIGS.public.outputDirectory ||
      CONFIGS.rider.outputDirectory === CONFIGS.admin.outputDirectory) {
    fail('Rider Web output directory must be isolated');
  }

  const hosting = firebase.hosting;
  if (!Array.isArray(hosting) || hosting.some((entry) => !entry.target)) {
    fail('every Firebase Hosting block must have an explicit target');
  }
  for (const config of Object.values(CONFIGS)) {
    const blocks = hosting.filter((entry) => entry.target === config.targetAlias);
    if (blocks.length !== 1 || blocks[0].public !== config.outputDirectory) {
      fail(`hosting:${config.targetAlias} must use ${config.outputDirectory}`);
    }
  }
  return true;
}

function validateRepositoryCommands(root = process.cwd()) {
  for (const location of ['scripts', '.github']) {
    const absolute = path.join(root, location);
    if (!fs.existsSync(absolute)) continue;
    const files = [];
    const visit = (directory) => {
      for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
        const candidate = path.join(directory, entry.name);
        if (entry.isDirectory()) visit(candidate);
        else files.push(candidate);
      }
    };
    visit(absolute);
    for (const file of files) {
      const source = fs.readFileSync(file, 'utf8');
      if (/firebase\s+deploy\s+--only\s+hosting(?:\s|$)/.test(source)) {
        fail(`forbidden untargeted Hosting deployment in ${path.relative(root, file)}`);
      }
    }
  }
  return true;
}

function artifactFiles(root, config) {
  const output = path.join(root, config.outputDirectory);
  return {
    output,
    index: path.join(output, 'index.html'),
    bundle: path.join(output, 'main.dart.js'),
    identity: path.join(output, 'circum-build-identity.txt'),
    manifest: path.join(output, 'deployment-manifest.json'),
  };
}

function validateBundle(config, bundleSource) {
  for (const marker of config.requiredBundleMarkers) {
    if (!bundleSource.includes(marker)) fail(`required marker is missing: ${marker}`);
  }
  for (const marker of config.forbiddenBundleMarkers) {
    if (bundleSource.includes(marker)) fail(`forbidden marker is present: ${marker}`);
  }
  return true;
}

function validateIdentity(config, identity) {
  if (identity.trim() !== config.buildIdentity) {
    fail('build identity does not match target');
  }
  return true;
}

function validateManifest(config, manifest, expected, now, checksum) {
  for (const [key, value] of Object.entries(expected)) {
    if (manifest[key] !== value) fail(`manifest ${key} does not match target`);
  }
  const age = now.getTime() - Date.parse(manifest.buildTimestamp);
  if (!Number.isFinite(age) || age < 0 || age > 2 * 60 * 60 * 1000) {
    fail('deployment manifest is stale');
  }
  if (manifest.buildChecksum !== checksum) fail('deployment manifest checksum mismatch');
  return true;
}

function prepare(mode, root = process.cwd(), now = new Date()) {
  const config = CONFIGS[mode];
  if (!config) fail(`unknown product ${mode}`);
  validateFirebaseConfiguration(root);
  validateRepositoryCommands(root);
  const files = artifactFiles(root, config);
  if (!fs.existsSync(files.index) || !fs.existsSync(files.bundle)) {
    fail(`${config.outputDirectory} is not a complete web build`);
  }
  validateBundle(config, fs.readFileSync(files.bundle, 'utf8'));
  fs.writeFileSync(files.identity, `${config.buildIdentity}\n`);
  const manifest = {
    product: config.product,
    buildIdentity: config.buildIdentity,
    gitCommit: gitValue(['rev-parse', 'HEAD']),
    branch: gitValue(['branch', '--show-current']),
    firebaseProject: PROJECT,
    hostingSiteId: config.siteId,
    targetAlias: config.targetAlias,
    outputDirectory: config.outputDirectory,
    buildTimestamp: now.toISOString(),
    buildChecksum: sha256Files([files.index, files.bundle, files.identity]),
  };
  fs.writeFileSync(files.manifest, `${JSON.stringify(manifest, null, 2)}\n`);
  return manifest;
}

function verify(mode, root = process.cwd(), now = new Date()) {
  const config = CONFIGS[mode];
  if (!config) fail(`unknown product ${mode}`);
  validateFirebaseConfiguration(root);
  validateRepositoryCommands(root);
  const files = artifactFiles(root, config);
  for (const file of [files.index, files.bundle, files.identity, files.manifest]) {
    if (!fs.existsSync(file)) fail(`required artifact is missing: ${file}`);
  }
  validateIdentity(config, fs.readFileSync(files.identity, 'utf8'));
  validateBundle(config, fs.readFileSync(files.bundle, 'utf8'));
  const manifest = readJson(files.manifest);
  const expected = {
    product: config.product,
    buildIdentity: config.buildIdentity,
    gitCommit: gitValue(['rev-parse', 'HEAD']),
    branch: gitValue(['branch', '--show-current']),
    firebaseProject: PROJECT,
    hostingSiteId: config.siteId,
    targetAlias: config.targetAlias,
    outputDirectory: config.outputDirectory,
  };
  const checksum = sha256Files([files.index, files.bundle, files.identity]);
  validateManifest(config, manifest, expected, now, checksum);
  return manifest;
}

if (require.main === module) {
  try {
    const [command, mode] = process.argv.slice(2);
    const result = command === 'prepare'
      ? prepare(mode)
      : command === 'verify'
        ? verify(mode)
        : fail('use prepare|verify admin|public|sender|rider');
    process.stdout.write(`${JSON.stringify(result)}\n`);
  } catch (error) {
    process.stderr.write(`${error.message}\n`);
    process.exit(1);
  }
}

module.exports = {
  CONFIGS,
  prepare,
  verify,
  validateBundle,
  validateFirebaseConfiguration,
  validateIdentity,
  validateManifest,
  validateRepositoryCommands,
};
