const fs = require('fs');
const cp = require('child_process');
const output = 'build/web_public';
const manifest = {
  product: 'circum-public-web',
  firebaseProject: 'circum-2797c',
  hostingTarget: 'public',
  baselineCommit: '3a5232e634c6d66dce277d9b785e43b13905e1b7',
  sourceCommit: cp.execFileSync('git', ['rev-parse', 'HEAD'], {encoding: 'utf8'}).trim(),
  buildType: 'public-zero-sharing',
  builtAt: new Date().toISOString()
};
fs.writeFileSync(`${output}/deployment-manifest.json`, `${JSON.stringify(manifest, null, 2)}\n`);
fs.writeFileSync(`${output}/circum-build-identity.txt`, 'CIRCUM_BUILD_ID=circum-public-web\n');
