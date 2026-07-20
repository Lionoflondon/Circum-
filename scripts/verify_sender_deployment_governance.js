#!/usr/bin/env node
/* eslint-disable no-console */
const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const cp = require('node:child_process');

const root = path.resolve(__dirname, '..');
const output = 'build/sender_app_web';
const outputDir = path.join(root, output);
const expectedTarget = 'app';
const expectedHostingOnly = 'hosting:app';
const expectedEntrypoint = 'lib/app/sender_mobile/sender_mobile_preview.dart';
const expectedIdentity = 'circum-sender-web';
const expectedSurface = 'sender-app';

function fail(message, details = []) {
  console.error('SENDER DEPLOYMENT GOVERNANCE FAILED');
  console.error(message);
  for (const detail of details) console.error(`- ${detail}`);
  process.exit(1);
}

function git(args, cwd = root) {
  return cp.execFileSync('git', args, {
    cwd,
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
  }).trim();
}

function run(command, args, cwd = root, env = process.env) {
  cp.execFileSync(command, args, {
    cwd,
    env,
    stdio: ['ignore', 'pipe', 'pipe'],
  });
}

function readJson(relativePath, cwd = root) {
  return JSON.parse(fs.readFileSync(path.join(cwd, relativePath), 'utf8'));
}

function readIfExists(relativePath, cwd = root) {
  const file = path.join(cwd, relativePath);
  return fs.existsSync(file) ? fs.readFileSync(file, 'utf8') : '';
}

function sha256(file) {
  return crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
}

function assertCleanTree() {
  const status = git(['status', '--porcelain=v1', '--untracked-files=all']);
  if (status) {
    fail('working tree is dirty', status.split('\n'));
  }
}

function upstreamRef() {
  try {
    return git(['rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{u}']);
  } catch (_) {
    fail('branch has no upstream');
  }
}

function assertHeadPushed() {
  const upstream = upstreamRef();
  const head = git(['rev-parse', 'HEAD']);
  const upstreamHead = git(['rev-parse', upstream]);
  if (head !== upstreamHead) {
    fail('HEAD is not pushed to its upstream', [
      `HEAD: ${head}`,
      `${upstream}: ${upstreamHead}`,
    ]);
  }
}

function assertConfig() {
  const manifest = readJson('deploy-manifest.json');
  const product = manifest.products['sender-app'];
  if (!product) fail('sender-app is missing from deploy-manifest.json');
  if (product.hostingTarget !== expectedTarget) {
    fail('Sender hosting target is not app', [`found: ${product.hostingTarget}`]);
  }
  if (product.output !== output) {
    fail('Sender build output is incorrect', [`found: ${product.output}`]);
  }

  const firebase = readJson('firebase.json');
  const hosting = Array.isArray(firebase.hosting) ? firebase.hosting : [firebase.hosting];
  const entry = hosting.find((item) => item.target === expectedTarget);
  if (!entry) fail('firebase.json is missing hosting target app');
  if (entry.public !== output) {
    fail('firebase.json app target points at the wrong output', [`found: ${entry.public}`]);
  }

  const buildScript = readIfExists('scripts/build_sender_app_web.sh');
  if (!buildScript.includes(expectedEntrypoint) || !buildScript.includes(output)) {
    fail('Sender build script does not use the canonical entrypoint/output');
  }

  const deployScript = readIfExists('scripts/deploy_sender_app_web.sh');
  if (!deployScript.includes(expectedHostingOnly) ||
      deployScript.includes('hosting:public') ||
      deployScript.includes('hosting:admin') ||
      deployScript.includes('functions') ||
      deployScript.includes('firestore') ||
      deployScript.includes('storage')) {
    fail('Sender deploy script is not restricted to hosting:app');
  }
}

function assertArtifact() {
  if (!fs.existsSync(outputDir)) fail('Sender build output does not exist', [output]);
  const markerPath = path.join(outputDir, 'circum-surface.json');
  const jsPath = path.join(outputDir, 'main.dart.js');
  const workerPath = path.join(outputDir, 'flutter_service_worker.js');
  if (!fs.existsSync(markerPath)) fail('circum-surface.json is missing from Sender artifact');
  if (!fs.existsSync(jsPath)) fail('main.dart.js is missing from Sender artifact');
  if (!fs.existsSync(workerPath)) fail('flutter_service_worker.js is missing from Sender artifact');

  const marker = JSON.parse(fs.readFileSync(markerPath, 'utf8'));
  const head = git(['rev-parse', 'HEAD']);
  const commitTimestamp = git(['show', '-s', '--format=%cI', 'HEAD']);
  if (marker.identity !== expectedIdentity) {
    fail('artifact identity is incorrect', [`found: ${marker.identity}`]);
  }
  if (marker.surface !== expectedSurface) {
    fail('artifact surface is incorrect', [`found: ${marker.surface}`]);
  }
  if (!marker.gitCommit) fail('gitCommit missing from build metadata');
  if (marker.gitCommit !== head) {
    fail('artifact commit differs from git HEAD', [
      `artifact: ${marker.gitCommit}`,
      `HEAD: ${head}`,
    ]);
  }
  if (!marker.generatedAt) fail('generatedAt missing from build metadata');
  if (!marker.flutterVersion) fail('flutterVersion missing from build metadata');
  if (new Date(marker.generatedAt).getTime() < new Date(commitTimestamp).getTime()) {
    fail('build timestamp is older than latest commit', [
      `generatedAt: ${marker.generatedAt}`,
      `commit: ${commitTimestamp}`,
    ]);
  }
  return {
    jsHash: sha256(jsPath),
    workerHash: sha256(workerPath),
  };
}

function remoteBranchName(upstream) {
  const parts = upstream.split('/');
  if (parts.length < 2) fail('upstream is not a remote branch', [`found: ${upstream}`]);
  return parts.slice(1).join('/');
}

function assertCleanCloneReproduces(referenceHashes) {
  if (!process.env.CIRCUM_WEB_RECAPTCHA_ENTERPRISE_SITE_KEY) {
    fail('CIRCUM_WEB_RECAPTCHA_ENTERPRISE_SITE_KEY is required for clean-clone reproducibility');
  }

  const remote = git(['remote', 'get-url', 'origin']);
  const upstream = upstreamRef();
  const branch = remoteBranchName(upstream);
  const head = git(['rev-parse', 'HEAD']);
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'circum-sender-repro-'));
  const cloneDir = path.join(tempRoot, 'Circum-');
  run('git', ['clone', '--branch', branch, remote, cloneDir], root);
  const cloneHead = git(['rev-parse', 'HEAD'], cloneDir);
  if (cloneHead !== head) {
    fail('clean clone HEAD differs from deployment HEAD', [
      `clone: ${cloneHead}`,
      `HEAD: ${head}`,
    ]);
  }
  const env = {
    ...process.env,
    FLUTTER_BIN: process.env.FLUTTER_BIN,
    CIRCUM_WEB_RECAPTCHA_ENTERPRISE_SITE_KEY:
      process.env.CIRCUM_WEB_RECAPTCHA_ENTERPRISE_SITE_KEY,
  };
  run('bash', ['scripts/build_sender_app_web.sh'], cloneDir, env);
  const cloneHashes = {
    jsHash: sha256(path.join(cloneDir, output, 'main.dart.js')),
    workerHash: sha256(path.join(cloneDir, output, 'flutter_service_worker.js')),
  };
  if (cloneHashes.jsHash !== referenceHashes.jsHash ||
      cloneHashes.workerHash !== referenceHashes.workerHash) {
    fail('clean-clone rebuild produced different hashes', [
      `local main.dart.js: ${referenceHashes.jsHash}`,
      `clone main.dart.js: ${cloneHashes.jsHash}`,
      `local service worker: ${referenceHashes.workerHash}`,
      `clone service worker: ${cloneHashes.workerHash}`,
      `clone: ${cloneDir}`,
    ]);
  }
  return cloneDir;
}

const args = new Set(process.argv.slice(2));
const prebuild = args.has('--prebuild');
const postbuild = args.has('--postbuild');
const cleanClone = args.has('--clean-clone');

if (!prebuild && !postbuild) {
  fail('usage: node scripts/verify_sender_deployment_governance.js --prebuild|--postbuild [--clean-clone]');
}

assertConfig();
assertCleanTree();
assertHeadPushed();

let artifact = null;
let reproducedFrom = null;
if (postbuild) {
  artifact = assertArtifact();
  if (cleanClone) reproducedFrom = assertCleanCloneReproduces(artifact);
}

console.log(JSON.stringify({
  ok: true,
  phase: prebuild ? 'prebuild' : 'postbuild',
  head: git(['rev-parse', 'HEAD']),
  upstream: upstreamRef(),
  output,
  hostingTarget: expectedHostingOnly,
  artifact,
  reproducedFrom,
}, null, 2));
