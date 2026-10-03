/* eslint-disable max-len, require-jsdoc */
const test = require("node:test"); const assert = require("node:assert/strict");
const {eventTarget} = require("./completion-recovery-http");
test("completion accepts only created canonical events in the exact project and database", () => {
 const headers = {"ce-id": "transport_id", "ce-source": "//firestore.googleapis.com/projects/circum-2797c/databases/(default)", "ce-type": "google.cloud.firestore.document.v1.created"};
 const decoded = {documentName: "projects/circum-2797c/databases/(default)/documents/platformEvents/delivery_completed_job"};
 assert.deepEqual(eventTarget(headers, decoded), {fixtureId: undefined, eventId: "delivery_completed_job"});
 assert.throws(() => eventTarget({...headers, "ce-type": "google.cloud.firestore.document.v1.updated"}, decoded));
 assert.throws(() => eventTarget(headers, {documentName: decoded.documentName.replace("circum-2797c", "foreign")}));
 assert.throws(() => eventTarget(headers, {documentName: decoded.documentName.replace("platformEvents", "deliveryRequests")}));
});
