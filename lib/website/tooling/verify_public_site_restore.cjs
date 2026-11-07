const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const output = process.argv[2];
assert(output, 'Pass the built public website directory');
const read = (file) => fs.readFileSync(path.join(output, file), 'utf8');
const metadata = JSON.parse(read('circum-surface.json'));
assert.equal(metadata.identity, 'circum-public-web');
assert.equal(metadata.gitCommit, process.env.GITHUB_SHA);
assert.match(read('index.html'), /London Parcel Delivery & Courier Services/);
assert.match(read('main.dart.js'), /The Future/);
assert.match(read('main.dart.js'), /\/air\//);
assert.match(read('seo/routes/contact.html'), /Contact CIRCUM/);
assert.match(read('air/index.html'), /CIRCUM AIR/i);
assert.match(read('air/index.html'), /noindex/i);

function verifyAirFiles(relative = '') {
  for (const entry of fs.readdirSync(path.join('web/air', relative), {
    withFileTypes: true,
  })) {
    const file = path.join(relative, entry.name);
    if (entry.isDirectory()) {
      verifyAirFiles(file);
    } else {
      assert.deepEqual(
        fs.readFileSync(path.join(output, 'air', file)),
        fs.readFileSync(path.join('web/air', file)),
        `AIR artifact differs from the approved source: ${file}`,
      );
    }
  }
}
verifyAirFiles();
console.log('Public website identity, homepage, contact route and AIR assets verified.');
