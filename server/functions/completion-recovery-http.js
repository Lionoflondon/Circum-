/* eslint-disable max-len, require-jsdoc */
"use strict";
const {getFirestore} = require("firebase-admin/firestore");
const {parseFirestoreEventarcPayload} = require("./lib/eventarc-envelope");
const {fixtureDb} = require("./gift-story-fixture-db");
const completion = require("./delivery-completed-event");
function eventTarget(headers, decoded) {
 const source = "//firestore.googleapis.com/projects/circum-2797c/databases/(default)";
 if (headers["ce-source"] !== source || !String(decoded.documentName || "").startsWith("projects/circum-2797c/databases/(default)/documents/")) throw Object.assign(new Error("invalid_event_source"), {statusCode: 400});
 if (headers["ce-type"] !== "google.cloud.firestore.document.v1.created" || !/^[A-Za-z0-9_-]{1,128}$/.test(headers["ce-id"] || "")) throw Object.assign(new Error("invalid_event_type_or_id"), {statusCode: 400});
 const path = decoded.documentName.split("/documents/")[1];
 const fixture = /^giftStoryRuntimeFixtures\/(__codex_[A-Za-z0-9_-]{1,100})\/state\/platformEvents\/records\/(delivery_completed_[A-Za-z0-9_-]{1,128})$/.exec(path);
 const live = /^platformEvents\/(delivery_completed_[A-Za-z0-9_-]{1,128})$/.exec(path);
 if (!fixture && !live) throw Object.assign(new Error("invalid_event_document"), {statusCode: 400});
 return {fixtureId: fixture?.[1], eventId: fixture?.[2] || live[1]};
}
async function processCompletion(db, eventId) {
 const snapshot = await db.collection("platformEvents").doc(eventId).get();
 const event = snapshot.data() || {};
 if (!snapshot.exists || event.eventId !== eventId || event.eventId !== `delivery_completed_${event.deliveryId}` || event.eventType !== completion.EVENT_TYPE || event.version !== completion.EVENT_VERSION) throw Object.assign(new Error("invalid_canonical_completion"), {statusCode: 400});
 // Read canonical Firestore timestamps and subscriber keys. Transport IDs never become new business event IDs.
 const results = await completion._private.runSubscribers(db, event);
 return {eventId, results};
}
function handle(req, res, options = {}) {
 if (new URL(req.url, "http://localhost").pathname !== "/v1/events/firestore/delivery-completed") return false;
 const send = (code, body) => {
res.writeHead(code, {"Content-Type": "application/json", "Cache-Control": "no-store"}); res.end(JSON.stringify(body));
};
 if (req.method !== "POST") {
send(405, {error: "method_not_allowed"}); return true;
}
 const chunks = []; let size = 0;
 req.on("data", (chunk) => {
size += chunk.length; if (size <= 2097152) chunks.push(chunk);
});
 req.on("end", async () => {
  try {
   if (size > 2097152) throw Object.assign(new Error("body_too_large"), {statusCode: 413});
   const decoded = parseFirestoreEventarcPayload(Buffer.concat(chunks)); const target = eventTarget(req.headers, decoded);
   const raw = options.dbFactory ? options.dbFactory() : getFirestore(); let db = raw;
   if (target.fixtureId) {
    const seal = (await raw.collection("giftStoryRuntimeFixtures").doc(target.fixtureId).get()).data() || {};
    if (seal.purpose !== "delivery_event_recovery" || seal.testOnly !== true || seal.suppressExternalSideEffects !== true) throw Object.assign(new Error("fixture_not_authorized"), {statusCode: 403});
    db = fixtureDb(raw, target.fixtureId);
   }
   const result = await processCompletion(db, target.eventId); send(200, {outcome: "PROCESSED", ...result});
  } catch (error) {
console.warn("completion_recovery_failed", {reason: error.code || error.message}); send(error.statusCode || 503, {error: error.statusCode ? error.message : "completion_requires_retry"});
}
 });
 return true;
}
module.exports = {handle, eventTarget, processCompletion};
