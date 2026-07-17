const fs = require('fs');
const fail = message => { throw new Error(`Public validation failed: ${message}`); };
const output = 'build/web_public';
for (const file of ['index.html', 'main.dart.js', 'deployment-manifest.json', 'circum-build-identity.txt']) {
  if (!fs.existsSync(`${output}/${file}`)) fail(`missing ${file}`);
}
const bundle = fs.readFileSync(`${output}/main.dart.js`, 'utf8');
for (const marker of ['Send anything across town.', 'Book trusted riders for parcels', 'Get started with Health+']) {
  if (!bundle.includes(marker)) fail(`missing identity marker: ${marker}`);
}
for (const marker of ['sender-root', 'SenderMobileHome', 'CIRCUM_BUILD_ID=sender-app', 'rider-app-root', 'CIRCUM_ADMIN_PORTAL_CANONICAL_V1', 'admin-root']) {
  if (bundle.includes(marker)) fail(`forbidden identity marker: ${marker}`);
}
const manifest = JSON.parse(fs.readFileSync(`${output}/deployment-manifest.json`, 'utf8'));
if (manifest.product !== 'circum-public-web' || manifest.hostingTarget !== 'public') fail('manifest identity mismatch');
console.log('PUBLIC VALIDATION PASS');
