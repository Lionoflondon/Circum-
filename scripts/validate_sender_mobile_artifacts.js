#!/usr/bin/env node
/* eslint-disable no-console */
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');

function read(file) {
  return fs.readFileSync(path.join(root, file), 'utf8');
}

function fail(message, details = []) {
  console.error('SENDER MOBILE ARTIFACT VALIDATION FAILED');
  console.error(message);
  for (const detail of details) console.error(`- ${detail}`);
  process.exit(1);
}

function assertContains(file, pattern, description) {
  const source = read(file);
  if (!source.includes(pattern)) {
    fail(`${description} is missing.`, [file, pattern]);
  }
}

function assertNotContains(file, pattern, description) {
  const source = read(file);
  if (source.includes(pattern)) {
    fail(`${description} is present.`, [file, pattern]);
  }
}

assertContains('android/app/build.gradle', 'applicationId "com.circum.app"',
  'Sender Android package identity');
assertContains('android/app/build.gradle', 'GOOGLE_MAPS_API_KEY',
  'Android configured Maps key injection');
assertContains('android/app/src/main/AndroidManifest.xml',
  'android:value="${googleMapsApiKey}"',
  'Android Maps manifest placeholder');
assertContains('ios/Runner/Info.plist', '$(GOOGLE_MAPS_API_KEY)',
  'iOS configured Maps key injection');
assertContains('ios/Runner/AppDelegate.swift', 'GoogleMapsApiKey',
  'iOS Maps key lookup');
assertContains('lib/app/security/circum_app_check.dart',
  'AndroidProvider.playIntegrity',
  'Sender Android App Check provider');
assertContains('lib/app/security/circum_app_check.dart',
  'AppleProvider.appAttestWithDeviceCheckFallback',
  'Sender Apple App Check provider');
assertContains('lib/app/security/circum_app_check.dart',
  'ReCaptchaEnterpriseProvider',
  'Web App Check provider');

const senderEntrypoints = [
  'lib/main.dart',
  'lib/app.dart',
  'lib/app/sender_mobile/sender_mobile_home.dart',
];

for (const file of senderEntrypoints) {
  assertNotContains(file, "package:circum/website/",
    'Sender mobile Website package import');
  assertNotContains(file, '../website/',
    'Sender mobile relative Website import');
}

console.log(JSON.stringify({
  ok: true,
  surface: 'sender-app',
  checks: [
    'android-package',
    'android-maps-config',
    'ios-maps-config',
    'app-check-providers',
    'sender-mobile-website-imports',
  ],
}, null, 2));
