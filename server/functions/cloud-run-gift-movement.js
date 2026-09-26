/* eslint-disable max-len */
"use strict";

const http = require("node:http");
const {initializeApp, getApps} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const {decodeEventarcPayload} = require("./cloud-run-notification-events");
const {projectLatestGiftMovement} = require("./gift-movement-projection-core");
const {FIXTURE_COLLECTION, validFixtureId, fixtureDb} = require("./gift-movement-fixture-db");

const EVENT_TYPES = new Set([
  "google.cloud.firestore.document.v1.created",
  "google.cloud.firestore.document.v1.updated",
]);
const MAX_BODY_BYTES = 2 * 1024 * 1024;
if (!getApps().length) initializeApp();

function configuredDb() {
  const db = getFirestore();
  db.settings({ignoreUndefinedProperties: true});
  return db;
}

function giftIdFromName(name) {
  const path = String(name || "").split("/documents/")[1] || String(name || "").replace(/^documents\//, "");
  const match = /^giftRequests\/([^/]+)$/.exec(path);
  return match && match[1];
}

function eventTarget(name, db, enabledFixtureId) {
  const path = String(name || "").split("/documents/")[1] || String(name || "").replace(/^documents\//, "");
  const giftId = giftIdFromName(path);
  if (giftId) return {giftId, eventDb: db};
  if (!validFixtureId(enabledFixtureId)) return null;
  const expectedPrefix = `${FIXTURE_COLLECTION}/${enabledFixtureId}/giftRequests/`;
  if (!path.startsWith(expectedPrefix)) return null;
  const fixtureGiftId = path.slice(expectedPrefix.length);
  if (!/^__codex_[A-Za-z0-9_-]{1,100}$/.test(fixtureGiftId)) return null;
  return {giftId: fixtureGiftId, eventDb: fixtureDb(db, enabledFixtureId)};
}

function createServer({db = configuredDb(), project = projectLatestGiftMovement,
  fixtureId = process.env.GIFT_MOVEMENT_FIXTURE_ID} = {}) {
  return http.createServer((req, res) => {
    if (req.method === "GET" && req.url === "/healthz") {
      res.writeHead(200, {"content-type": "application/json"});
      res.end(JSON.stringify({ok: true, service: "gift-movement", sourceSha: process.env.SOURCE_SHA || "unknown"}));
      return;
    }
    if (req.method !== "POST" || req.url !== "/" || !EVENT_TYPES.has(String(req.headers["ce-type"] || ""))) {
      res.writeHead(404).end();
      return;
    }
    let size = 0;
    const chunks = [];
    req.on("data", (chunk) => {
      size += chunk.length;
      if (size <= MAX_BODY_BYTES) chunks.push(chunk);
    });
    req.on("end", async () => {
      if (size > MAX_BODY_BYTES) return res.writeHead(413).end();
      try {
        const decoded = decodeEventarcPayload(Buffer.concat(chunks));
        const target = eventTarget(decoded.documentName || req.headers["ce-subject"], db, fixtureId);
        if (!target) return res.writeHead(400).end();
        const result = await project(target.eventDb, target.giftId);
        console.log("gift_movement_projection", {status: result.status});
        res.writeHead(200, {"content-type": "application/json"});
        res.end(JSON.stringify({ok: true, status: result.status}));
      } catch (error) {
        console.error("gift_movement_projection_failed", {code: String(error && error.code || "internal").slice(0, 120)});
        res.writeHead(500, {"content-type": "application/json"});
        res.end(JSON.stringify({ok: false}));
      }
    });
  });
}

if (require.main === module) createServer().listen(Number(process.env.PORT || 8080), "0.0.0.0");
module.exports = {createServer, giftIdFromName, eventTarget};
