"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const cors = require("./gift-media-storage-cors.json");
test("signed Gift media supports both existing app origins without widening bucket policy", () => {
  assert.equal(cors.length, 1);
  assert.deepEqual(cors[0].origin, ["https://circum-rider-2797c.web.app", "https://circum-app-2797c.web.app"]);
  assert.deepEqual(cors[0].method, ["GET", "HEAD", "POST", "PUT", "DELETE", "OPTIONS"]);
  assert.deepEqual(cors[0].responseHeader, ["Authorization", "Content-Type", "Content-Length", "Content-Range", "Range", "ETag", "x-goog-resumable"]);
  assert.equal(cors[0].maxAgeSeconds, 3600);
});
