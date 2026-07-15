#!/usr/bin/env node

const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const output = path.join(root, 'build', 'web_main');
const indexPath = path.join(output, 'index.html');
const bootstrapPath = path.join(output, 'flutter_bootstrap.js');
const workerPath = path.join(output, 'flutter_service_worker.js');

const bootstrapTag = '<script src="flutter_bootstrap.js" async></script>';
const safeBootstrap = `<script>
    (async function startPublicWeb() {
      if ('serviceWorker' in navigator) {
        const registrations = await navigator.serviceWorker.getRegistrations();
        await Promise.all(registrations.map((registration) => registration.unregister()));
      }
      if ('caches' in window) {
        const cacheNames = await caches.keys();
        await Promise.all(cacheNames.map((cacheName) => caches.delete(cacheName)));
      }
      const bootstrap = document.createElement('script');
      bootstrap.src = 'flutter_bootstrap.js';
      document.body.appendChild(bootstrap);
    })().catch(function () {
      document.getElementById('startup-loading').style.display = 'none';
      document.getElementById('startup-error').style.display = 'block';
    });
  </script>`;

let index = fs.readFileSync(indexPath, 'utf8');
if (!index.includes(bootstrapTag)) {
  throw new Error('Public index does not contain the expected Flutter bootstrap tag.');
}
index = index.replace(bootstrapTag, safeBootstrap);
fs.writeFileSync(indexPath, index);

let bootstrap = fs.readFileSync(bootstrapPath, 'utf8');
const serviceWorkerLoad = /_flutter\.loader\.load\(\{\s*serviceWorkerSettings:\s*\{[\s\S]*?\}\s*\}\);/;
if (!serviceWorkerLoad.test(bootstrap)) {
  throw new Error('Public Flutter bootstrap service-worker registration was not found.');
}
bootstrap = bootstrap.replace(serviceWorkerLoad, '_flutter.loader.load();');
fs.writeFileSync(bootstrapPath, bootstrap);

const cleanupWorker = `self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    const cacheNames = await caches.keys();
    await Promise.all(cacheNames.map((cacheName) => caches.delete(cacheName)));
    await self.clients.claim();
    await self.registration.unregister();
    const clients = await self.clients.matchAll({ type: 'window' });
    await Promise.all(clients.map((client) => client.navigate(client.url)));
  })());
});
`;
fs.writeFileSync(workerPath, cleanupWorker);

console.log('Prepared Public hosting output with legacy service-worker eviction.');
