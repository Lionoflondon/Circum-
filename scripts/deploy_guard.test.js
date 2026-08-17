#!/usr/bin/env node
const assert = require('node:assert/strict');
const cp = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');

const sourceGuard = path.join(__dirname, 'deploy_guard.js');
const manifest = {
  products: {
    'sender-app': {
      ownedPrefixes: ['lib/app/sender_mobile/'],
      forbiddenPrefixes: ['lib/website/'],
    },
    website: {
      ownedPrefixes: ['lib/website/', 'lib/web_platform_routing.dart'],
      forbiddenPrefixes: ['lib/app/sender_mobile/'],
    },
  },
  sharedFiles: [],
  ignoredPrefixes: [],
  blockedPrefixes: [],
};

function git(cwd, args) {
  return cp.execFileSync('git', args, { cwd, encoding: 'utf8' }).trim();
}

function fixture() {
  const cwd = fs.mkdtempSync(path.join(os.tmpdir(), 'circum-deploy-guard-'));
  fs.mkdirSync(path.join(cwd, 'scripts'));
  fs.mkdirSync(path.join(cwd, 'lib/app/sender_mobile'), { recursive: true });
  fs.mkdirSync(path.join(cwd, 'lib/website'), { recursive: true });
  fs.writeFileSync(path.join(cwd, 'scripts/deploy_guard.js'), fs.readFileSync(sourceGuard));
  fs.writeFileSync(path.join(cwd, 'deploy-manifest.json'), JSON.stringify(manifest));
  fs.writeFileSync(path.join(cwd, 'analysis_options.yaml'), 'analyzer:\n');
  fs.writeFileSync(path.join(cwd, 'pubspec.lock'), '# generated\n');
  fs.writeFileSync(path.join(cwd, 'lib/main.dart'), 'void main() {}\n');
  git(cwd, ['init', '-q']);
  git(cwd, ['config', 'user.email', 'test@example.com']);
  git(cwd, ['config', 'user.name', 'Deploy Guard Test']);
  git(cwd, ['add', '.']);
  git(cwd, ['commit', '-qm', 'base']);
  return cwd;
}

function commit(cwd, message) {
  git(cwd, ['add', '.']);
  git(cwd, ['commit', '-qm', message]);
  return git(cwd, ['rev-parse', 'HEAD']);
}

function runGuard(cwd, target, base, head, ci = false) {
  return cp.spawnSync(process.execPath, ['scripts/deploy_guard.js', `--target=${target}`, `--base=${base}`, `--head=${head}`, ...(ci ? ['--ci'] : [])], {
    cwd,
    encoding: 'utf8',
  });
}

test('Sender-only PR passes despite incidental lock/config changes', () => {
  const cwd = fixture();
  const base = git(cwd, ['rev-parse', 'HEAD']);
  fs.writeFileSync(path.join(cwd, 'lib/app/sender_mobile/home.dart'), 'sender\n');
  const head = commit(cwd, 'sender');
  fs.appendFileSync(path.join(cwd, 'pubspec.lock'), 'dirty\n');
  fs.appendFileSync(path.join(cwd, 'analysis_options.yaml'), 'dirty\n');
  assert.equal(runGuard(cwd, 'sender-app', base, head).status, 0);
});

test('Web-only PR passes', () => {
  const cwd = fixture();
  const base = git(cwd, ['rev-parse', 'HEAD']);
  fs.writeFileSync(path.join(cwd, 'lib/website/join.dart'), 'web\n');
  const head = commit(cwd, 'web');
  assert.equal(runGuard(cwd, 'website', base, head, true).status, 0);
  assert.equal(runGuard(cwd, 'sender-app', base, head, true).status, 0);
});

test('Mixed Sender and Web PR fails', () => {
  const cwd = fixture();
  const base = git(cwd, ['rev-parse', 'HEAD']);
  fs.writeFileSync(path.join(cwd, 'lib/app/sender_mobile/home.dart'), 'sender\n');
  fs.writeFileSync(path.join(cwd, 'lib/website/join.dart'), 'web\n');
  const head = commit(cwd, 'mixed');
  assert.equal(runGuard(cwd, 'sender-app', base, head, true).status, 1);
});

test('Genuine forbidden cross-surface change fails', () => {
  const cwd = fixture();
  const base = git(cwd, ['rev-parse', 'HEAD']);
  fs.writeFileSync(path.join(cwd, 'lib/app/sender_mobile/home.dart'), 'sender\n');
  fs.writeFileSync(path.join(cwd, 'lib/website/join.dart'), 'web\n');
  const head = commit(cwd, 'forbidden');
  assert.equal(runGuard(cwd, 'sender-app', base, head, true).status, 1);
});
