/* eslint-disable max-len, require-jsdoc */
"use strict";
const {parseFirestoreEventarcPayload} = require("./lib/eventarc-envelope");
const {fixtureDb} = require("./gift-story-fixture-db");
const {projectTimeline, projectPresence} = require("./delivery-write-recovery");
const TYPES = new Set(["google.cloud.firestore.document.v1.written", "google.cloud.firestore.document.v1.created", "google.cloud.firestore.document.v1.updated", "google.cloud.firestore.document.v1.deleted"]);
function target(headers, decoded, kind) {
 if (headers["ce-source"] !== "//firestore.googleapis.com/projects/circum-2797c/databases/(default)" || (decoded.documentName && !decoded.documentName.startsWith("projects/circum-2797c/databases/(default)/documents/"))) throw Object.assign(new Error("invalid_event_source"), {statusCode: 400});
 if (!TYPES.has(headers["ce-type"])) throw Object.assign(new Error("invalid_event_type"), {statusCode: 400});
 const collection = kind === "tracking" ? "deliveryLiveLocations" : "deliveryRequests";
 const path = String(decoded.documentName || headers["ce-subject"] || "").replace(/^.*\/documents\//, "").replace(/^documents\//, "");
 const fixture = new RegExp(`^giftStoryRuntimeFixtures/(__codex_[A-Za-z0-9_-]{1,100})/state/${collection}/records/([A-Za-z0-9_-]{1,128})$`).exec(path);
 const production = new RegExp(`^${collection}/([A-Za-z0-9_-]{1,128})$`).exec(path);
 if (!fixture && !production) throw Object.assign(new Error("invalid_event_document"), {statusCode: 400});
 return {fixtureId: fixture?.[1], deliveryId: fixture?.[2] || production[1], eventId: String(headers["ce-id"] || ""), time: headers["ce-time"], before: Object.keys(decoded.before || {}).length ? decoded.before : null, after: Object.keys(decoded.after || {}).length ? decoded.after : null};
}
function handle(req, res, {dbFactory, kinds}) {
 const pathname = new URL(req.url, "http://localhost").pathname;
 const kind = pathname.split("/").at(-1);
 if (!pathname.startsWith("/v1/events/firestore/delivery-write/") || !kinds.includes(kind)) return false;
 const send = (code, body) => {
res.writeHead(code, {"Content-Type": "application/json", "Cache-Control": "no-store"}); res.end(JSON.stringify(body));
};
 if (req.method !== "POST") {
send(405, {error: "method_not_allowed"}); return true;
}
 let size = 0; const chunks = [];
 req.on("data", (chunk) => {
size += chunk.length; if (size <= 2097152) chunks.push(chunk);
});
 req.on("end", async () => {
  try {
   if (size > 2097152) throw Object.assign(new Error("body_too_large"), {statusCode: 413});
   const decoded = parseFirestoreEventarcPayload(Buffer.concat(chunks));
   const event = target(req.headers, decoded, kind); const rawDb = dbFactory(); let db = rawDb;
   if (event.fixtureId) {
    const root = await rawDb.collection("giftStoryRuntimeFixtures").doc(event.fixtureId).get();
    if (root.data()?.purpose !== "delivery_event_recovery" || root.data()?.testOnly !== true || root.data()?.suppressExternalSideEffects !== true) throw Object.assign(new Error("fixture_not_authorized"), {statusCode: 403});
    db = fixtureDb(rawDb, event.fixtureId);
   }
   const result = kind === "presence" ? await projectPresence({db, event}) : await projectTimeline({db, event, live: kind === "tracking"});
   console.info("delivery_write_recovered", {kind, fixture: Boolean(event.fixtureId), outcome: result.outcome, changed: result.changed, events: result.events}); send(200, result);
  } catch (error) {
   console.warn("delivery_write_recovery_failed", {kind, code: error.code || error.message}); send(error.statusCode || 503, {error: error.statusCode ? error.message : "worker_failed"});
  }
 }); return true;
}
module.exports = {handle, target};
