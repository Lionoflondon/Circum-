/* eslint-disable max-len */
const test = require("node:test");
const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const fs = require("node:fs");
const os = require("node:os");

process.env.FIREBASE_CONFIG = JSON.stringify({
  projectId: "circum-rider-document-integration",
  storageBucket: "circum-rider-document-integration.appspot.com",
});
process.env.GCLOUD_PROJECT = "circum-rider-document-integration";
const key = crypto.generateKeyPairSync("rsa", {modulusLength: 2048});
const privateKey = key.privateKey.export({type: "pkcs8", format: "pem"});
const credentialsPath = `${os.tmpdir()}/circum-emulator-service-account.json`;
fs.writeFileSync(credentialsPath, JSON.stringify({
  type: "service_account",
  project_id: process.env.GCLOUD_PROJECT,
  private_key_id: "test",
  private_key: privateKey,
  client_email: "test@circum.test",
}));
process.env.GOOGLE_APPLICATION_CREDENTIALS = credentialsPath;

const admin = require("firebase-admin");
const functions = require("./index");
const db = admin.firestore();
const bucket = admin.storage().bucket();

function file(side, content) {
  return {
    side,
    base64: Buffer.from(content).toString("base64"),
    mimeType: "image/jpeg",
    fileName: `${side}.jpg`,
  };
}

test("multipart document callable writes both sides and canonical pending metadata", async () => {
  const result = await functions.submitRiderDocument.run({
    documentType: "driving_licence",
    files: [file("front", "front"), file("back", "back")],
    approved: true,
    dispatchEligible: true,
    storagePath: "client-controlled/path",
  }, {auth: {uid: "rider-integration", token: {email: "rider@example.test"}}});

  assert.equal(result.ok, true);
  assert.deepEqual(Object.keys(result.attachments).sort(), ["back", "front"]);
  const documents = await db.collection("riderDocuments")
      .where("riderId", "==", "rider-integration").get();
  assert.equal(documents.size, 1);
  const document = documents.docs[0].data();
  assert.equal(document.status, "pending");
  assert.equal(document.verificationStatus, "pending");
  assert.equal(document.approved, undefined);
  assert.equal(document.dispatchEligible, undefined);
  assert.deepEqual(Object.keys(document.attachments).sort(), ["back", "front"]);
  const [files] = await bucket.getFiles({prefix: "rider_documents/rider-integration/"});
  assert.equal(files.length, 2);
});

test("invalid multipart document is rejected before any Storage or Firestore write", async () => {
  await assert.rejects(
      functions.submitRiderDocument.run({
        documentType: "driving_licence",
        files: [file("front", "front"), {...file("back", "back"), base64: "not-base64"}],
      }, {auth: {uid: "rider-invalid", token: {email: "invalid@example.test"}}}),
  );
  const documents = await db.collection("riderDocuments")
      .where("riderId", "==", "rider-invalid").get();
  assert.equal(documents.size, 0);
  const [files] = await bucket.getFiles({prefix: "rider_documents/rider-invalid/"});
  assert.equal(files.length, 0);
});
