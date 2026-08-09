"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const root = path.resolve(__dirname, "../..");

test("stale Rider presence query has its required composite index", () => {
  const source = fs.readFileSync(path.join(__dirname, "rider-presence.js"), "utf8");
  assert.match(source, /collection\("riderPresence"\)[\s\S]*?where\("isOnline", "==", true\)[\s\S]*?where\("lastHeartbeatAt", "<", cutoff\)/);

  const config = JSON.parse(fs.readFileSync(path.join(root, "firestore.indexes.json"), "utf8"));
  const index = config.indexes.find((candidate) =>
    candidate.collectionGroup === "riderPresence" &&
    candidate.queryScope === "COLLECTION" &&
    candidate.fields.map((field) => field.fieldPath).join(",") ===
      "isOnline,lastHeartbeatAt,__name__",
  );
  assert.ok(index, "riderPresence stale-heartbeat composite index is required");
  assert.deepEqual(index.fields.map((field) => field.order), ["ASCENDING", "ASCENDING", "ASCENDING"]);
});
