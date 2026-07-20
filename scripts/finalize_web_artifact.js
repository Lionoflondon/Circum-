#!/usr/bin/env node
/* eslint-disable no-console */
const fs = require('node:fs');
const path = require('node:path');
const cp = require('node:child_process');

const surfaces = {
  website: {
    identity: 'circum-public-web',
    name: 'Circum Website',
    shortName: 'Circum',
    description: 'Circum public website. Sender Web and Rider Web are independent products.',
    startUrl: '/',
    themeColor: '#0f172a',
    title: 'Circum',
  },
  'sender-app': {
    identity: 'circum-sender-web',
    name: 'Circum Sender App',
    shortName: 'Circum Sender',
    description: 'Circum Sender application.',
    startUrl: '/',
    themeColor: '#0f172a',
    title: 'Circum Sender',
  },
  admin: {
    identity: 'circum-admin-web',
    name: 'Circum Admin',
    shortName: 'Circum Admin',
    description: 'Circum Admin operations console.',
    startUrl: '/',
    themeColor: '#0f172a',
    title: 'Circum Admin',
  },
};

function fail(message) {
  console.error(message);
  process.exit(1);
}

function git(args) {
  try {
    return cp.execFileSync('git', args, {
      cwd: process.cwd(),
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    }).trim();
  } catch (_) {
    return null;
  }
}

function command(args) {
  try {
    return cp.execFileSync(args[0], args.slice(1), {
      cwd: process.cwd(),
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    }).trim();
  } catch (_) {
    return null;
  }
}

const surfaceName = process.argv[2];
const outDir = process.argv[3];
const surface = surfaces[surfaceName];
if (!surface || !outDir) {
  fail('Usage: finalize_web_artifact.js <website|sender-app|admin> <output-dir>');
}

const absoluteOut = path.resolve(outDir);
const manifestPath = path.join(absoluteOut, 'manifest.json');
const indexPath = path.join(absoluteOut, 'index.html');
if (!fs.existsSync(indexPath)) {
  fail(`Missing Flutter web artifact in ${absoluteOut}`);
}

const sourceManifestPath = path.join(process.cwd(), 'web', 'manifest.json');
const manifest = fs.existsSync(manifestPath)
  ? JSON.parse(fs.readFileSync(manifestPath, 'utf8'))
  : fs.existsSync(sourceManifestPath)
    ? JSON.parse(fs.readFileSync(sourceManifestPath, 'utf8'))
    : {};
manifest.name = surface.name;
manifest.short_name = surface.shortName;
manifest.description = surface.description;
manifest.start_url = surface.startUrl;
manifest.scope = '/';
manifest.theme_color = surface.themeColor;
manifest.background_color = surface.themeColor;
fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);

let index = fs.readFileSync(indexPath, 'utf8');
index = index.replace(/<title>.*?<\/title>/, `<title>${surface.title}</title>`);
index = index.replace(
  /<meta name="apple-mobile-web-app-title" content=".*?">/,
  `<meta name="apple-mobile-web-app-title" content="${surface.shortName}">`,
);
if (!index.includes('name="circum-web-surface"')) {
  index = index.replace(
    '</head>',
    `  <meta name="circum-web-surface" content="${surface.identity}">\n</head>`,
  );
}
fs.writeFileSync(indexPath, index);

const rootManifestCopies = [
  ['assets/AssetManifest.bin.json', 'AssetManifest.bin.json'],
  ['assets/FontManifest.json', 'FontManifest.json'],
];
for (const [source, destination] of rootManifestCopies) {
  const sourcePath = path.join(absoluteOut, source);
  if (!fs.existsSync(sourcePath)) {
    fail(`Missing generated Flutter manifest ${source}`);
  }
  fs.copyFileSync(sourcePath, path.join(absoluteOut, destination));
}

fs.writeFileSync(
  path.join(absoluteOut, 'circum-surface.json'),
  `${JSON.stringify({
    identity: surface.identity,
    surface: surfaceName,
    generatedAt: new Date().toISOString(),
    gitCommit: git(['rev-parse', 'HEAD']),
    gitCommitTimestamp: git(['show', '-s', '--format=%cI', 'HEAD']),
    flutterVersion: process.env.FLUTTER_BIN
      ? command([process.env.FLUTTER_BIN, '--version', '--machine'])
      : null,
  }, null, 2)}\n`,
);

console.log(JSON.stringify({
  surface: surfaceName,
  identity: surface.identity,
  output: absoluteOut,
}, null, 2));
