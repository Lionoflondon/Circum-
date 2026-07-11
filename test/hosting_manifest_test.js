const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');

const {
  CONFIGS,
  validateBundle,
  validateFirebaseConfiguration,
  validateIdentity,
  validateManifest,
} = require('../scripts/hosting_manifest.js');

function fixture() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'circum-hosting-'));
  fs.writeFileSync(path.join(root, '.firebaserc'), JSON.stringify({
    projects: { default: 'circum-2797c' },
    targets: {
      'circum-2797c': {
        hosting: {
          admin: ['circum-admin-2797c'],
          public: ['circum-2797c'],
        },
      },
    },
  }));
  fs.writeFileSync(path.join(root, 'firebase.json'), JSON.stringify({
    hosting: [
      { target: 'admin', public: 'build/web_admin' },
      { target: 'public', public: 'build/web_main' },
    ],
  }));
  return root;
}

test('Admin and public targets, sites and outputs are distinct', () => {
  assert.notEqual(CONFIGS.admin.targetAlias, CONFIGS.public.targetAlias);
  assert.notEqual(CONFIGS.admin.siteId, CONFIGS.public.siteId);
  assert.notEqual(CONFIGS.admin.outputDirectory, CONFIGS.public.outputDirectory);
  assert.equal(validateFirebaseConfiguration(fixture()), true);
});

test('Admin build rejects public homepage copy', () => {
  assert.throws(
    () => validateBundle(CONFIGS.admin, 'CIRCUM_ADMIN_PORTAL_CANONICAL_V1 Employee access only. Sign in with an account that has a Circum admin role. Send anything across town'),
    /forbidden marker/,
  );
});

test('public build rejects Admin authentication markers', () => {
  assert.throws(
    () => validateBundle(CONFIGS.public, 'Send anything across town Admin operations'),
    /forbidden marker/,
  );
});

test('mismatched output directory blocks deployment', () => {
  const root = fixture();
  const config = JSON.parse(fs.readFileSync(path.join(root, 'firebase.json')));
  config.hosting[0].public = 'build/web_main';
  fs.writeFileSync(path.join(root, 'firebase.json'), JSON.stringify(config));
  assert.throws(() => validateFirebaseConfiguration(root), /build\/web_admin/);
});

test('mismatched Hosting site blocks deployment', () => {
  const root = fixture();
  const rc = JSON.parse(fs.readFileSync(path.join(root, '.firebaserc')));
  rc.targets['circum-2797c'].hosting.admin = ['circum-2797c'];
  fs.writeFileSync(path.join(root, '.firebaserc'), JSON.stringify(rc));
  assert.throws(() => validateFirebaseConfiguration(root), /circum-admin-2797c/);
});

test('mismatched build identity blocks deployment', () => {
  assert.throws(
    () => validateIdentity(CONFIGS.admin, 'CIRCUM_BUILD_ID=public-sender'),
    /build identity/,
  );
});

test('mismatched or stale deployment manifest blocks deployment', () => {
  const now = new Date('2026-07-11T04:00:00.000Z');
  const expected = {
    product: CONFIGS.admin.product,
    buildIdentity: CONFIGS.admin.buildIdentity,
    gitCommit: 'abc123',
    branch: 'main',
    firebaseProject: 'circum-2797c',
    hostingSiteId: CONFIGS.admin.siteId,
    targetAlias: CONFIGS.admin.targetAlias,
    outputDirectory: CONFIGS.admin.outputDirectory,
  };
  assert.throws(
    () => validateManifest(CONFIGS.admin, {
      ...expected,
      targetAlias: 'public',
      buildTimestamp: now.toISOString(),
      buildChecksum: 'checksum',
    }, expected, now, 'checksum'),
    /targetAlias/,
  );
  assert.throws(
    () => validateManifest(CONFIGS.admin, {
      ...expected,
      buildTimestamp: '2026-07-10T00:00:00.000Z',
      buildChecksum: 'checksum',
    }, expected, now, 'checksum'),
    /stale/,
  );
});
