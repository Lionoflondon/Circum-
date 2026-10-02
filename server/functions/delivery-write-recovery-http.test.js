/* eslint-disable max-len, require-jsdoc */
"use strict";
const test = require("node:test"); const assert = require("node:assert/strict"); const {target} = require("./delivery-write-recovery-http");
test("delivery events accept only the existing project database and supported document namespace", () => {
 const source = "//firestore.googleapis.com/projects/circum-2797c/databases/(default)";
 const headers = {"ce-source": source, "ce-type": "google.cloud.firestore.document.v1.written", "ce-id": "test-event"};
 const documentName = "projects/circum-2797c/databases/(default)/documents/deliveryRequests/job";
 assert.equal(target(headers, {documentName, before: {status: "accepted"}, after: {status: "completed"}}, "timeline").deliveryId, "job");
 assert.throws(() => target({...headers, "ce-source": source.replace("circum-2797c", "other")}, {documentName}, "timeline"), {statusCode: 400});
 assert.throws(() => target(headers, {documentName: documentName.replace("circum-2797c", "other")}, "timeline"), {statusCode: 400});
 assert.throws(() => target(headers, {documentName: documentName.replace("deliveryRequests", "riders")}, "presence"), {statusCode: 400});
 const isolated = target(headers, {documentName: "projects/circum-2797c/databases/(default)/documents/giftStoryRuntimeFixtures/__codex_delivery_test/state/deliveryRequests/records/job"}, "presence"); assert.equal(isolated.fixtureId, "__codex_delivery_test");
});
