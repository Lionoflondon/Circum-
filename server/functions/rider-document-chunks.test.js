/* eslint-disable max-len */
const test = require("node:test");
const assert = require("node:assert/strict");
const {cleanupExpired} = require("./rider-document-chunks");
const now = Date.parse("2026-09-05T12:00:00Z");
const expired = "2026-09-03T12:00:00Z";

test("abandoned staging cleanup is private, time-bounded and generation-safe", async () => {
  const deleted = [];
  const file = (name, timeCreated, generation = "1") => ({name, metadata: {timeCreated, generation}, delete: async (options) => deleted.push({name, options})});
  const files = [
    file("rider_document_chunks/rider/old", expired, "7"),
    file("rider_document_chunks/rider/fresh", "2026-09-05T11:00:00Z"),
    file("rider_document_chunks/rider/boundary", "2026-09-04T12:00:00Z"),
    file("rider_document_chunks/rider/unknown", "invalid"),
    file("rider_document_chunks/rider/no-generation", expired, ""),
    file("rider_documents/rider/approved.pdf", expired),
  ];
  const result = await cleanupExpired({now, bucket: {getFiles: async (query) => {
    assert.equal(query.prefix, "rider_document_chunks/");
    assert.equal(query.autoPaginate, false);
    return [files, null];
  }}});
  assert.deepEqual(result, {deleted: 1, incomplete: false});
  assert.deepEqual(deleted, [{name: "rider_document_chunks/rider/old", options: {ifGenerationMatch: "7", ignoreNotFound: true}}]);
});

test("cleanup preserves replacement generations and traverses staging pages", async () => {
  let calls = 0;
  const result = await cleanupExpired({now, bucket: {getFiles: async (query) => {
    calls += 1;
    assert.equal(query.prefix, "rider_document_chunks/");
    if (calls === 1) {
return [[{name: "rider_document_chunks/rider/racing", metadata: {timeCreated: expired, generation: "1"}, delete: async () => {
throw Object.assign(new Error("replaced"), {code: 412});
}}], {pageToken: "next"}];
}
    assert.equal(query.pageToken, "next");
    return [[], null];
  }}});
  assert.equal(calls, 2);
  assert.deepEqual(result, {deleted: 0, incomplete: false});
});
