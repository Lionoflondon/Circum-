/* eslint-disable max-len */
"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const iris = fs.readFileSync(path.join(__dirname, "iris.js"), "utf8");
const admin = fs.readFileSync(path.join(__dirname, "admin-operations-authority.js"), "utf8");

test("inference reads only active promoted canonical knowledge with version state", () => {
  assert.match(iris, /collection\("irisCanonicalObjects"\)[\s\S]*?where\("status", "==", "active"\)[\s\S]*?where\("repositoryReviewStatus", "==", "promoted"\)/);
  assert.match(iris, /collection\("irisKnowledgeState"\)\.doc\("current"\)/);
  assert.match(iris, /where\("lookupKeys", "array-contains", lookupKey\)\.limit\(10\)/);
  assert.match(iris, /expiresAt: now \+ 60 \* 1000/);
});

test("promotion is transaction-backed versioned auditable and retry-idempotent", () => {
  const start = admin.indexOf("exports.adminUpdateIrisCandidateWorkflow");
  const end = admin.indexOf("exports.adminSaveGiftRequestEditor", start);
  const source = admin.slice(start, end);
  assert.match(source, /db\.runTransaction/);
  assert.match(source, /repositoryPromotionStatus === "committed"/);
  assert.match(source, /idempotent = true/);
  assert.match(source, /knowledgeVersion = `iris-knowledge-v\$\{nextVersion\}`/);
  assert.match(source, /transaction\.set\(stateRef/);
  assert.match(source, /actionType: "iris_candidate_promoted"/);
});

test("raw learning cases are never queried as production inference knowledge", () => {
  const analyseStart = iris.indexOf("const analyseIris");
  const analyseEnd = iris.indexOf("const getIrisHealthMetrics", analyseStart);
  assert.doesNotMatch(iris.slice(analyseStart, analyseEnd), /irisLearningCases/);
});
