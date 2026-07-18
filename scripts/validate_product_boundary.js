#!/usr/bin/env node
/* eslint-disable no-console */
const { execFileSync } = require('node:child_process');
const path = require('node:path');

const root = path.resolve(__dirname, '..');

const PRODUCT_BOUNDARIES = {
  'sender-app': {
    name: 'Sender App',
    allowed: [
      'lib/app/account/',
      'lib/app/delivery/',
      'lib/app/delivery_security/',
      'lib/app/history/',
      'lib/app/send_package/',
      'lib/app/sender_mobile/',
      'lib/app/sender_profile/',
      'lib/app/support/',
      'test/sender_mobile/',
      'test/sender_profile_test.dart',
    ],
    forbidden: [
      'lib/main_public_web.dart',
      'lib/main_sender_web.dart',
      'lib/web_sender_app.dart',
      'lib/web_platform_routing.dart',
      'lib/app/admin/',
      'lib/app/business/',
      'lib/app/rider_marketplace/',
      'lib/app/rider_profiles/',
      'server/',
      'firestore.rules',
      'storage.rules',
      'firebase.json',
      '.firebaserc',
      'web/',
      'android/',
      'ios/',
      'macos/',
    ],
  },
  'sender-web': {
    name: 'Sender Web',
    allowed: [
      'lib/main_sender_web.dart',
      'lib/app/security/',
      'scripts/build_sender_app_web.sh',
      'scripts/deploy_sender_app_web.sh',
      'scripts/deploy_isolated.sh',
      'scripts/finalize_web_artifact.js',
      'scripts/firebase_tools.sh',
      'scripts/validate_product_boundary.js',
      'scripts/validate_web_artifacts.js',
      'docs/',
      'test/security/',
      'test/web_artifact_isolation_test.dart',
      'pubspec.yaml',
      'pubspec.lock',
    ],
    forbidden: [
      'lib/app/rider_marketplace/',
      'lib/app/rider_profiles/',
      'lib/app/admin/',
      'server/',
      'firestore.rules',
      'storage.rules',
      'android/',
      'ios/',
      'macos/',
    ],
  },
  'public-web': {
    name: 'Public Website',
    allowed: [
      'lib/main_public_web.dart',
      'lib/web_platform_routing.dart',
      'lib/web_sender_app.dart',
      'lib/app/security/',
      'scripts/build_public_web.sh',
      'scripts/deploy_public_web.sh',
      'scripts/deploy_isolated.sh',
      'scripts/finalize_web_artifact.js',
      'scripts/firebase_tools.sh',
      'scripts/validate_product_boundary.js',
      'scripts/validate_web_artifacts.js',
      'docs/',
      'test/security/',
      'test/web_artifact_isolation_test.dart',
      'test/web_platform_routing_test.dart',
      'pubspec.yaml',
      'pubspec.lock',
    ],
    forbidden: [
      'lib/app/sender_mobile/',
      'lib/app/sender_profile/',
      'lib/app/admin/',
      'server/',
      'firestore.rules',
      'storage.rules',
      'android/',
      'ios/',
      'macos/',
    ],
  },
  admin: {
    name: 'Admin',
    allowed: [
      'lib/main.dart',
      'lib/app/admin/',
      'lib/app/security/',
      'scripts/build_admin_web.sh',
      'scripts/deploy_admin_web.sh',
      'scripts/deploy_isolated.sh',
      'scripts/finalize_web_artifact.js',
      'scripts/firebase_tools.sh',
      'scripts/validate_product_boundary.js',
      'scripts/validate_web_artifacts.js',
      'docs/',
      'test/security/',
      'test/web_artifact_isolation_test.dart',
      'test/web_platform_routing_test.dart',
      'pubspec.yaml',
      'pubspec.lock',
    ],
    forbidden: [
      'lib/app/sender_mobile/',
      'lib/app/sender_profile/',
      'lib/app/rider_marketplace/',
      'lib/app/rider_profiles/',
      'server/',
      'firestore.rules',
      'storage.rules',
      'android/',
      'ios/',
      'macos/',
    ],
  },
  backend: {
    name: 'Cloud Functions',
    allowed: [
      'server/',
      'firestore.rules',
      'storage.rules',
    ],
    forbidden: [
      'lib/',
      'android/',
      'ios/',
      'macos/',
      'web/',
      'scripts/build_',
      'scripts/deploy_',
    ],
  },
};

function usage() {
  console.error('Usage: scripts/validate_product_boundary.js --surface=<sender-app|sender-web|public-web|admin|backend> [--base=<rev> --head=<rev>] [--files=a,b]');
}

function fail(message, files = []) {
  console.error('DEPLOYMENT BLOCKED');
  console.error('Cross-application contamination detected.');
  console.error(message);
  for (const file of files) console.error(`- ${file}`);
  process.exit(1);
}

function parseArgs() {
  const args = {};
  for (const arg of process.argv.slice(2)) {
    const [key, ...valueParts] = arg.replace(/^--/, '').split('=');
    args[key] = valueParts.join('=');
  }
  if (!args.surface || !PRODUCT_BOUNDARIES[args.surface]) {
    usage();
    fail(`Unknown or missing surface: ${args.surface || '(missing)'}`);
  }
  return args;
}

function normalize(file) {
  return file.replace(/\\/g, '/').replace(/^\.\//, '');
}

function changedFiles(args) {
  if (args.files) {
    return args.files.split(',').map(normalize).filter(Boolean);
  }
  if (args.base && args.head) {
    const output = execFileSync(
      'git',
      ['diff', '--name-only', `${args.base}..${args.head}`],
      { cwd: root, encoding: 'utf8' },
    );
    return output.split(/\r?\n/).map(normalize).filter(Boolean);
  }
  const staged = execFileSync(
    'git',
    ['diff', '--name-only', '--cached'],
    { cwd: root, encoding: 'utf8' },
  );
  const unstaged = execFileSync(
    'git',
    ['diff', '--name-only'],
    { cwd: root, encoding: 'utf8' },
  );
  return [...new Set(`${staged}\n${unstaged}`.split(/\r?\n/).map(normalize).filter(Boolean))];
}

function matches(file, prefixes) {
  return prefixes.some((prefix) => file === prefix || file.startsWith(prefix));
}

function main() {
  const args = parseArgs();
  const boundary = PRODUCT_BOUNDARIES[args.surface];
  const files = changedFiles(args);
  const forbidden = files.filter((file) => matches(file, boundary.forbidden));
  if (forbidden.length > 0) {
    fail(`${boundary.name} deployment includes explicitly forbidden files:`, forbidden);
  }
  const outside = files.filter((file) => !matches(file, boundary.allowed));
  if (outside.length > 0) {
    fail(`${boundary.name} deployment includes files outside its approved boundary:`, outside);
  }
  console.log(JSON.stringify({
    ok: true,
    surface: args.surface,
    product: boundary.name,
    checkedFiles: files,
  }, null, 2));
}

main();
