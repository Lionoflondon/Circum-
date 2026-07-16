/* eslint-disable max-len */
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const iris = fs.readFileSync(path.join(__dirname, "iris.js"), "utf8");
const adminAuth = fs.readFileSync(path.join(__dirname, "admin-auth.js"), "utf8");

test("adjudicateIris requires admin authorization before any privileged access", () => {
  const functionStart = iris.indexOf("const adjudicateIris = functions.https.onCall");
  const guard = iris.indexOf("const adminUid = requireAdmin(context", functionStart);
  const firestore = iris.indexOf("const db = getFirestore()", functionStart);
  const firstDeliveryRead = iris.indexOf("collection(\"deliveryRequests\")", functionStart);
  const firstWrite = iris.indexOf("doc.ref.set", functionStart);
  assert.ok(functionStart >= 0);
  assert.ok(guard > functionStart, "admin guard must be inside adjudicateIris");
  assert.ok(guard < firestore, "admin guard must execute before Firestore is opened");
  assert.ok(guard < firstDeliveryRead, "admin guard must execute before target delivery reads");
  assert.ok(guard < firstWrite, "admin guard must execute before privileged writes");
});

test("adjudicateIris uses authenticated admin identity for all actor fields", () => {
  assert.match(iris, /adminUserId: adminUid/);
  assert.match(iris, /createdBy: adminUid/);
  assert.match(iris, /updatedBy: adminUid/);
  assert.match(iris, /actorUid: adminUid/);
  assert.doesNotMatch(iris, /adminUserId:\s*data\./);
  assert.doesNotMatch(iris, /createdBy:\s*data\./);
  assert.doesNotMatch(iris, /updatedBy:\s*data\./);
});

test("adjudicateIris protected operations remain behind the guard", () => {
  for (const pattern of [
    /update\.status = decision/,
    /update\.matchingStatus = "blocked"/,
    /collection\("irisPrivate"\)\.doc\(requestId\)\.set/,
    /collection\("adminAuditLogs"\)\.add/,
    /collection\("irisReferrals"\)\.doc\(requestId\)\.set/,
  ]) {
    assert.match(iris, pattern);
  }
});

test("analyseIris remains ordinary authenticated and is not admin-gated", () => {
  const analyseStart = iris.indexOf("const analyseIris = functions.https.onCall");
  const adjudicateStart = iris.indexOf("const adjudicateIris = functions.https.onCall");
  const analyseBody = iris.slice(analyseStart, adjudicateStart);
  assert.match(analyseBody, /if \(!context\.auth\)/);
  assert.doesNotMatch(analyseBody, /requireAdmin/);
});

test("shared admin guard recognises only established admin roles", () => {
  assert.match(adminAuth, /"admin"/);
  assert.match(adminAuth, /"super_admin"/);
  assert.match(adminAuth, /"operations_admin"/);
  assert.match(adminAuth, /token\.admin === true/);
  assert.match(adminAuth, /token\.superAdmin === true/);
  assert.match(adminAuth, /token\.adminRole/);
  assert.match(adminAuth, /token\.role/);
  assert.match(adminAuth, /token\.roles/);
});
