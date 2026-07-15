const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const publicRoot = path.join(root, 'lib', 'public_web');
const files = fs
  .readdirSync(publicRoot, { recursive: true })
  .filter((entry) => entry.endsWith('.dart'));

const forbidden = [
  /web_sender_app\.dart/,
  /main_admin\.dart/,
  /package:circum\/app\/sender/,
  /package:circum\/app\/rider/,
  /package:circum\/app\/admin/,
  /sender_mobile/,
  /sender[-_/ ]?(shell|navigation|routes?)/i,
  /rider[-_/ ]?(shell|navigation|routes?)/i,
  /admin[-_/ ]?(shell|navigation|routes?)/i,
  /CircumSenderAppRoot/,
  /CircumRiderAppRoot/,
  /CircumAdminAppRoot/,
];

const violations = [];

const legacySenderSource = fs.readFileSync(
  path.join(root, 'lib', 'web_sender_app.dart'),
  'utf8',
);
for (const retiredSymbol of ['CircumPublicAppRoot', 'class _LandingPage']) {
  if (legacySenderSource.includes(retiredSymbol)) {
    violations.push(`web_sender_app.dart retains ${retiredSymbol}`);
  }
}
for (const relative of files) {
  const absolute = path.join(publicRoot, relative);
  const source = fs.readFileSync(absolute, 'utf8');
  for (const pattern of forbidden) {
    if (pattern.test(source)) violations.push(`${relative}: ${pattern}`);
  }
}

const circumDartFiles = [];
function collectDartFiles(directory) {
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const absolute = path.join(directory, entry.name);
    if (entry.isDirectory()) collectDartFiles(absolute);
    else if (entry.name.endsWith('.dart')) circumDartFiles.push(absolute);
  }
}
collectDartFiles(path.join(root, 'lib'));

for (const absolute of circumDartFiles) {
  if (absolute.startsWith(publicRoot + path.sep)) continue;
  const source = fs.readFileSync(absolute, 'utf8');
  if (source.includes('public_web/public_app.dart') ||
      source.includes('public_web/main_public.dart')) {
    violations.push(
      `${path.relative(root, absolute)} imports the public application`,
    );
  }
}

if (fs.existsSync(path.join(root, 'lib', 'main_rider.dart'))) {
  violations.push('Circum repository contains a Rider application entry');
}

const riderRoot = path.resolve(root, '..', 'Circum-Rider');
if (fs.existsSync(path.join(riderRoot, 'lib'))) {
  const riderFiles = [];
  const collectRiderFiles = (directory) => {
    for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
      const absolute = path.join(directory, entry.name);
      if (entry.isDirectory()) collectRiderFiles(absolute);
      else if (entry.name.endsWith('.dart')) riderFiles.push(absolute);
    }
  };
  collectRiderFiles(path.join(riderRoot, 'lib'));
  for (const absolute of riderFiles) {
    const source = fs.readFileSync(absolute, 'utf8');
    if (source.includes('public_web')) {
      violations.push(
        `${path.relative(riderRoot, absolute)} imports the public application`,
      );
    }
  }
}

const deploy = fs.readFileSync(path.join(root, 'scripts', 'deploy_main_web.sh'), 'utf8');
if (!deploy.includes('--target lib/public_web/main_public.dart')) {
  violations.push('deploy_main_web.sh does not build the dedicated public entry');
}
if (!deploy.includes('--only hosting:public')) {
  violations.push('deploy_main_web.sh is not restricted to hosting:public');
}

function assertBundleBoundary(relativePath, forbiddenStrings) {
  const bundle = path.join(root, relativePath);
  if (!fs.existsSync(bundle)) return;
  const source = fs.readFileSync(bundle, 'utf8');
  for (const value of forbiddenStrings) {
    if (source.includes(value)) {
      violations.push(`${relativePath} contains forbidden marker: ${value}`);
    }
  }
}

assertBundleBoundary('build/web_sender/main.dart.js', [
  'Earn as a Rider',
  'Send anything across town.',
  'CircumPublicAppRoot',
  'public-landing',
]);
assertBundleBoundary('build/web_main/main.dart.js', [
  'CircumSenderAppRoot',
  'CircumRiderAppRoot',
  'CircumAdminAppRoot',
]);

if (violations.length) {
  console.error('Public web architecture boundary failed:\n' + violations.join('\n'));
  process.exit(1);
}

console.log(`Public web architecture boundary passed (${files.length} files).`);
