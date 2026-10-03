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

test("a retry waits for every subscriber write before releasing the Cloud Run request", async () => {
 const completion = require("./delivery-completed-event")._private;
 const originalSender = completion.subscribers.sender; const originalRecipient = completion.subscribers.recipient;
 const originalOthers = {...completion.subscribers}; let release; let settled = false;
 const delayed = new Promise((resolve) => {
release = resolve;
});
 const records = new Map();
 const db = {collection: (name) => ({doc: (id) => ({key: `${name}/${id}`})}), runTransaction: async (fn) => fn({get: async (ref) => ({exists: records.has(ref.key), data: () => records.get(ref.key)}), set: (ref, data) => {
records.set(ref.key, {...records.get(ref.key), ...data});
}})};
 for (const name of Object.keys(completion.subscribers)) completion.subscribers[name] = async () => {};
 completion.subscribers.sender = async () => {
throw new Error("test_subscriber_failure");
};
 completion.subscribers.recipient = async () => delayed;
 try {
  const result = completion.runSubscribers(db, {eventId: "delivery_completed_test"}).catch((error) => {
settled = true; return error;
});
  await new Promise((resolve) => setImmediate(resolve)); assert.equal(settled, false, "an unfinished subscriber must retain request CPU");
  release(); assert.match((await result).message, /test_subscriber_failure/);
 } finally {
  release(); Object.assign(completion.subscribers, originalOthers); completion.subscribers.sender = originalSender; completion.subscribers.recipient = originalRecipient;
 }
});
