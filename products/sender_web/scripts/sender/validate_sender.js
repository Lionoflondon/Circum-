const fs = require('fs');
const fail = message => { throw new Error(`Sender validation failed: ${message}`); };
const output = 'build/web_sender';
for (const file of ['index.html', 'main.dart.js', 'deployment-manifest.json', 'circum-build-identity.txt']) {
  if (!fs.existsSync(`${output}/${file}`)) fail(`missing ${file}`);
}
const bundle = fs.readFileSync(`${output}/main.dart.js`, 'utf8');
for (const marker of ['sender-root']) if (!bundle.includes(marker)) fail(`missing identity marker: ${marker}`);
for (const marker of ['CIRCUM_BUILD_ID=circum-public-web', 'Send anything across town', 'rider-app-root', 'CIRCUM_ADMIN_PORTAL_CANONICAL_V1', 'admin-root']) {
  if (bundle.includes(marker)) fail(`forbidden identity marker: ${marker}`);
}
const manifest = JSON.parse(fs.readFileSync(`${output}/deployment-manifest.json`, 'utf8'));
if (manifest.product !== 'circum-sender-web' || manifest.hostingTarget !== 'sender') fail('manifest identity mismatch');
console.log('SENDER VALIDATION PASS');
