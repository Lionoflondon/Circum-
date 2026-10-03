/* eslint-disable max-len, require-jsdoc */
"use strict";
const test = require("node:test"); const assert = require("node:assert/strict");
const {eventTarget} = require("./recognition-recovery-http");
const source = "//firestore.googleapis.com/projects/circum-2797c/databases/(default)";
test("recognition events require the exact project/database and canonical Rider collections", () => {
 const headers = {"ce-id": "test_event", "ce-source": source, "ce-type": "google.cloud.firestore.document.v1.written"};
 const decoded = {documentName: "projects/circum-2797c/databases/(default)/documents/riders/test_rider"};
 assert.deepEqual(eventTarget(headers, decoded), {fixtureId: undefined, collection: "riders", id: "test_rider"});
 assert.throws(() => eventTarget({...headers, "ce-source": source.replace("circum-2797c", "foreign")}, decoded), /invalid_event_source/);
 assert.throws(() => eventTarget(headers, {documentName: decoded.documentName.replace("riders", "users")}), /invalid_event_document/);
 assert.throws(() => eventTarget(headers, {documentName: decoded.documentName.replace("circum-2797c", "foreign")}), /invalid_event_source/);
});
test("recognition TEST documents remain nested under the exact sealed runtime fixture", () => {
 const path = "projects/circum-2797c/databases/(default)/documents/giftStoryRuntimeFixtures/__codex_recognition/state/riderProfiles/records/test_rider";
 assert.deepEqual(eventTarget({"ce-id": "test_event", "ce-source": source, "ce-type": "google.cloud.firestore.document.v1.updated"}, {documentName: path}), {fixtureId: "__codex_recognition", collection: "riderProfiles", id: "test_rider"});
});
