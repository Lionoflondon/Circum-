import fs from 'node:fs';
import process from 'node:process';
import { chromium } from 'playwright';

const baseUrl = process.env.SENDER_BROWSER_BASE_URL || 'https://circum-app-2797c.web.app/';
const expectedSha = process.env.SENDER_EXPECTED_SHA;
const artifactDir = process.env.SENDER_BROWSER_ARTIFACT_DIR || 'build/sender-browser-artifacts';
const errors = [];
fs.mkdirSync(artifactDir, { recursive: true });

const browser = await chromium.launch({ headless: true });
const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
page.on('pageerror', (error) => errors.push(`pageerror: ${error.message}`));
page.on('console', (message) => {
  if (message.type() === 'error') errors.push(`console: ${message.text()}`);
});

try {
  const provenanceResponse = await page.request.get(new URL('circum-surface.json', baseUrl).toString());
  if (!provenanceResponse.ok()) throw new Error(`provenance HTTP ${provenanceResponse.status()}`);
  const provenance = await provenanceResponse.json();
  if (provenance.identity !== 'circum-sender-web') throw new Error('wrong live surface identity');
  if (expectedSha && provenance.gitCommit !== expectedSha) {
    throw new Error(`live SHA ${provenance.gitCommit} does not match ${expectedSha}`);
  }

  await page.goto(baseUrl, { waitUntil: 'domcontentloaded' });
  await page.waitForFunction(() => {
    const text = document.body?.innerText || '';
    const pane = document.querySelector('flt-glass-pane');
    const canvas = document.querySelector('canvas') ||
      pane?.shadowRoot?.querySelector('flt-scene-host canvas, canvas');
    return /We're having trouble starting Circum|Circum could not start/.test(text) ||
      (canvas && canvas.width > 0 && canvas.height > 0);
  }, null, { timeout: 30000 });

  const visibleText = await page.locator('body').innerText();
  const renderSurface = await page.evaluate(() => {
    const pane = document.querySelector('flt-glass-pane');
    const canvas = document.querySelector('canvas') ||
      pane?.shadowRoot?.querySelector('flt-scene-host canvas, canvas');
    return { width: canvas?.width || 0, height: canvas?.height || 0 };
  });
  const recovery = /We're having trouble starting Circum|Circum could not start/.test(visibleText);
  const screenshot = await page.screenshot({ path: `${artifactDir}/sender-startup.png`, fullPage: true });
  const normal = !recovery && renderSurface.width > 0 &&
    renderSurface.height > 0 && screenshot.length > 10000;
  if (!normal && !recovery) throw new Error('no visible Sender normal or recovery surface');
  const unexpectedErrors = errors.filter(
    (error) => !error.includes('requestStorageAccess: Permission denied.'),
  );
  if (unexpectedErrors.length && !recovery) throw new Error(unexpectedErrors.join('\n'));
  console.log(`SENDER_BROWSER_RENDER=${recovery ? 'RECOVERY_UI' : 'NORMAL_UI'}`);
} catch (error) {
  await page.screenshot({ path: `${artifactDir}/sender-startup-failure.png`, fullPage: true }).catch(() => {});
  fs.writeFileSync(`${artifactDir}/browser-errors.log`, errors.join('\n'));
  console.error(error);
  process.exitCode = 1;
} finally {
  await browser.close();
}
