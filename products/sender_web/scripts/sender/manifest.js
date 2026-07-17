const fs = require('fs');
const cp = require('child_process');
const output = 'build/web_sender';
const manifest = {
  product: 'circum-sender-web',
  firebaseProject: 'circum-2797c',
  hostingTarget: 'sender',
  baselineCommit: '6f9c6baafcd21194c2d63591c1f96574d940598e',
  sourceCommit: cp.execFileSync('git', ['rev-parse', 'HEAD'], {encoding: 'utf8'}).trim(),
  buildType: 'sender-zero-sharing',
  builtAt: new Date().toISOString()
};
fs.writeFileSync(`${output}/deployment-manifest.json`, `${JSON.stringify(manifest, null, 2)}\n`);
fs.writeFileSync(`${output}/circum-build-identity.txt`, 'CIRCUM_BUILD_ID=sender-app\n');
