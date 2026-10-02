/* eslint-disable require-jsdoc */
"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {videoDownloadDb} = require("./gift-story-automation");
function db(data, exists = true) {
  return {collection: () => ({doc: () => ({get: async () => ({exists, data: () => data}), collection: () => ({})})}), runTransaction() {}, batch() {}};
}
test("ordinary Gift downloads keep their existing database and contract", async () => {
  const raw = db({}); assert.equal(await videoDownloadDb(raw, "gift-customer"), raw);
});
test("TEST download scope requires an operator-created isolated root", async () => {
  for (const value of [{}, {purpose: "gift_video_certification", testOnly: true}]) {
    await assert.rejects(videoDownloadDb(db(value), "__codex_video_test"), {code: "not-found"});
  }
  const scoped = await videoDownloadDb(db({purpose: "gift_video_certification", testOnly: true, suppressExternalSideEffects: true}), "__codex_video_test");
  assert.equal(scoped.fixtureMode, true);
});
