/* eslint-disable max-len, require-jsdoc */
"use strict";

const http = require("node:http");
const {initializeApp, getApps} = require("firebase-admin/app");
const {FieldValue, getFirestore} = require("firebase-admin/firestore");
const {parseAvailabilityEvent, parseFixtureAvailabilityEvent} = require("./rider-availability-firestore-event");
const {processAvailabilityEvent, processFixtureAvailabilityEvent} = require("./rider-availability-worker-core");

const MAX_EVENT_BODY_BYTES = 2 * 1024 * 1024;
const EVENT_PATHS = Object.freeze({
  "/v1/events/firestore/rider-profile": "riderProfiles",
  "/v1/events/firestore/rider-record": "riders",
  "/v1/events/firestore/runtime-fixture": "_runtimeFixtures",
});

function fixtureProductionProcessor() {
  if (!getApps().length) initializeApp();
  const db = getFirestore();
  db.settings({ignoreUndefinedProperties: true});
  return (event) => processFixtureAvailabilityEvent({db, event, fieldValue: FieldValue});
}

function productionProcessor() {
  if (!getApps().length) initializeApp();
  const db = getFirestore();
  db.settings({ignoreUndefinedProperties: true});
  return (event) => processAvailabilityEvent({db, event, fieldValue: FieldValue});
}

function json(response, status, body) {
  response.writeHead(status, {"content-type": "application/json; charset=utf-8", "cache-control": "no-store"});
  response.end(JSON.stringify(body));
}

function createServer(options = {}) {
  const processorFactory = options.processorFactory || productionProcessor;
  const fixtureProcessorFactory = options.fixtureProcessorFactory || fixtureProductionProcessor;
  let processor;
  let fixtureProcessor;
  return http.createServer((request, response) => {
    if (request.method === "GET" && request.url === "/health") return json(response, 200, {status: "ok", runtime: "node22", sourceSha: process.env.CIRCUM_SOURCE_SHA || "unknown"});
    const collection = EVENT_PATHS[request.url];
    if (!collection) return json(response, 404, {error: "not_found"});
    if (request.method !== "POST") return json(response, 405, {error: "method_not_allowed"});
    const contentType = String(request.headers["content-type"] || "").toLowerCase();
    if (!contentType.startsWith("application/json") && !contentType.startsWith("application/protobuf")) return json(response, 415, {error: "unsupported_media_type"});
    let size = 0;
    const chunks = [];
    request.on("data", (chunk) => {
      size += chunk.length;
      if (size <= MAX_EVENT_BODY_BYTES) chunks.push(chunk);
    });
    request.on("end", async () => {
      if (size > MAX_EVENT_BODY_BYTES) return json(response, 413, {error: "request_too_large"});
      try {
        const event = collection === "_runtimeFixtures" ?
          parseFixtureAvailabilityEvent({headers: request.headers, body: Buffer.concat(chunks)}) :
          parseAvailabilityEvent({headers: request.headers, body: Buffer.concat(chunks), collection});
        if (!event.relevant) {
          console.info(JSON.stringify({event: "rider_availability_filtered", eventId: event.eventId, riderId: event.riderId || null, fixtureId: event.fixtureId || null, sourceCollection: collection, outcome: "IGNORED"}));
          return json(response, 200, {outcome: "IGNORED", riderId: event.riderId || null, fixtureId: event.fixtureId || null});
        }
        if (collection === "_runtimeFixtures") {
          if (!fixtureProcessor) fixtureProcessor = fixtureProcessorFactory();
          const result = await fixtureProcessor(event);
          console.info(JSON.stringify({event: "rider_availability_fixture_processed", ...result}));
          return json(response, 200, result);
        }
        if (!processor) processor = processorFactory();
        const result = await processor(event);
        console.info(JSON.stringify({event: "rider_availability_processed", ...result, sourceCollection: collection}));
        return json(response, 200, result);
      } catch (error) {
        const status = Number(error.statusCode) || 500;
        console.error("rider_availability_event_failed", {reason: error.message || "unknown", sourceCollection: collection});
        return json(response, status, {error: status === 500 ? "worker_failed" : error.message});
      }
    });
  });
}

if (require.main === module) createServer().listen(Number(process.env.PORT || 8080), "0.0.0.0");

module.exports = {createServer, EVENT_PATHS, MAX_EVENT_BODY_BYTES, productionProcessor, fixtureProductionProcessor};
