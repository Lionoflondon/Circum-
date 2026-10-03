/* eslint-disable max-len, require-jsdoc */
"use strict";
const {parseFirestoreEventarcPayload} = require("./lib/eventarc-envelope");
const {fixtureDb} = require("./gift-story-fixture-db");
const SOURCE = "//firestore.googleapis.com/projects/circum-2797c/databases/(default)";
function eventTarget(headers, decoded) {
 if (!String(headers["ce-id"] || "").trim() || String(headers["ce-id"]).length > 128) throw Object.assign(new Error("invalid_event_id"), {statusCode: 400});
 if (headers["ce-source"] !== SOURCE || !String(decoded.documentName || "").startsWith("projects/circum-2797c/databases/(default)/documents/")) throw Object.assign(new Error("invalid_event_source"), {statusCode: 400});
 if (!["google.cloud.firestore.document.v1.written", "google.cloud.firestore.document.v1.created", "google.cloud.firestore.document.v1.updated", "google.cloud.firestore.document.v1.deleted"].includes(headers["ce-type"])) throw Object.assign(new Error("invalid_event_type"), {statusCode: 400});
 const path = decoded.documentName.split("/documents/")[1];
 const fixture = /^giftStoryRuntimeFixtures\/(__codex_[A-Za-z0-9_-]{1,100})\/state\/(riderProfiles|riders)\/records\/([A-Za-z0-9_-]{1,128})$/.exec(path);
 const live = /^(riderProfiles|riders)\/([A-Za-z0-9_-]{1,128})$/.exec(path);
 if (!fixture && !live) throw Object.assign(new Error("invalid_event_document"), {statusCode: 400});
 return {fixtureId: fixture?.[1], collection: fixture?.[2] || live[1], id: fixture?.[3] || live[2]};
}
function handle(req, res, options) {
 if (new URL(req.url, "http://localhost").pathname !== "/v1/events/firestore/founding-recognition") return false;
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
   const {statusApproved} = require("./legends")._private;
   const approval = (value = {}) => statusApproved(value.accountStatus || value.approvalStatus || value.onboardingStatus || value.verificationStatus);
   if (approval(decoded.before) || !approval(decoded.after)) {
send(200, {outcome: "IGNORED"}); return;
}
   const raw = options.dbFactory(); let db = raw;
   if (target.fixtureId) {
    const root = await raw.collection("giftStoryRuntimeFixtures").doc(target.fixtureId).get(); const seal = root.data() || {};
    if (seal.purpose !== "delivery_event_recovery" || seal.testOnly !== true || seal.suppressExternalSideEffects !== true) throw Object.assign(new Error("fixture_not_authorized"), {statusCode: 403});
    db = fixtureDb(raw, target.fixtureId);
   }
   const award = options.award || require("./legends")._private.awardRecognition;
   const result = await award({db, type: "foundingRider", subjectRef: db.collection(target.collection).doc(target.id), subjectId: target.id, subjectCollection: target.collection, source: "rider_application_accepted", reason: "Rider accepted onto Circum."});
   send(200, result);
  } catch (error) {
console.warn("recognition_recovery_failed", {reason: error.code || error.message}); send(error.statusCode || 503, {error: error.statusCode ? error.message : "worker_failed"});
}
 });
 return true;
}
module.exports = {handle, eventTarget};
