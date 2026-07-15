#!/usr/bin/env node

const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const platform = path.join(root, 'build', 'web_platform');

const products = [
  {
    name: 'Public Website',
    directory: platform,
    base: '<base href="/">',
    required: ['Send anything across town', 'Earn as a Rider'],
    forbidden: ['rider-web-root', 'sender-root'],
  },
  {
    name: 'Sender Web',
    directory: path.join(platform, 'send'),
    base: '<base href="/send/">',
    required: ['sender-root'],
    forbidden: ['Send anything across town', 'rider-web-root'],
  },
  {
    name: 'Rider Web',
    directory: path.join(platform, 'rider'),
    base: '<base href="/rider/">',
    required: ['rider-web-root', 'Roth', 'Report Load Discrepancy'],
    forbidden: ['Send anything across town', 'sender-root'],
  },
];

const failures = [];
for (const product of products) {
  const indexPath = path.join(product.directory, 'index.html');
  const bundlePath = path.join(product.directory, 'main.dart.js');
  if (!fs.existsSync(indexPath) || !fs.existsSync(bundlePath)) {
    failures.push(`${product.name}: incomplete build output`);
    continue;
  }
  const index = fs.readFileSync(indexPath, 'utf8');
  const bundle = fs.readFileSync(bundlePath, 'utf8');
  if (!index.includes(product.base)) {
    failures.push(`${product.name}: wrong base href`);
  }
  for (const marker of product.required) {
    if (!bundle.includes(marker)) failures.push(`${product.name}: missing ${marker}`);
  }
  for (const marker of product.forbidden) {
    if (bundle.includes(marker)) failures.push(`${product.name}: contains ${marker}`);
  }
}

if (failures.length) {
  console.error(`Web platform verification failed:\n${failures.join('\n')}`);
  process.exit(1);
}
console.log('Web platform verification passed: Public, Sender Web, and Rider Web are isolated.');
