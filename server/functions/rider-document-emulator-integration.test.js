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
    idempotencyKey: "integration-upload-001",
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
        idempotencyKey: "integration-invalid-001",
        files: [file("front", "front"), {...file("back", "back"), base64: "not-base64"}],
      }, {auth: {uid: "rider-invalid", token: {email: "invalid@example.test"}}}),
  );
  const documents = await db.collection("riderDocuments")
      .where("riderId", "==", "rider-invalid").get();
  assert.equal(documents.size, 0);
  const [files] = await bucket.getFiles({prefix: "rider_documents/rider-invalid/"});
  assert.equal(files.length, 0);
});

test("replaying an upload request does not create duplicate records or objects", async () => {
  const request = {
    documentType: "driving_licence",
    idempotencyKey: "integration-replay-001",
    files: [file("front", "front-replay"), file("back", "back-replay")],
  };
  const context = {auth: {uid: "rider-replay", token: {email: "replay@example.test"}}};

  const first = await functions.submitRiderDocument.run(request, context);
  const second = await functions.submitRiderDocument.run(request, context);

  assert.equal(second.documentId, first.documentId);
  assert.equal(second.idempotentReplay, true);
  const documents = await db.collection("riderDocuments")
      .where("riderId", "==", "rider-replay").get();
  assert.equal(documents.size, 1);
  const [files] = await bucket.getFiles({prefix: "rider_documents/rider-replay/"});
  assert.equal(files.length, 2);
});

test("legacy clients without an upload request key remain compatible", async () => {
  const result = await functions.submitRiderDocument.run({
    documentType: "insurance",
    fileBase64: Buffer.from("legacy-insurance").toString("base64"),
    contentType: "application/pdf",
    fileName: "insurance.pdf",
  }, {auth: {uid: "rider-legacy", token: {email: "legacy@example.test"}}});

  assert.equal(result.ok, true);
  const documents = await db.collection("riderDocuments")
      .where("riderId", "==", "rider-legacy").get();
  assert.equal(documents.size, 1);
  assert.equal(documents.docs[0].data().idempotencyKey, undefined);
});

test("legacy document section acknowledgements derive from uploads without writing review authority", async () => {
  const uid = "legacy-section-evidence";
  const context = {auth: {uid, token: {email: "legacy-section@example.test"}}};
  const acknowledge = (section, extra = {}) => functions.updateRiderApplicationSection.run({section, status: "submitted", ...extra}, context);
  await assert.rejects(acknowledge("identity_verification"), {code: "failed-precondition"});
  for (const [type, section, mime] of [["passport", "identity_verification", "application/pdf"], ["right_to_work", "right_to_work", "image/jpeg"], ["insurance", "vehicle_documents", "application/pdf"]]) {
    await functions.submitRiderDocument.run({documentType: type, idempotencyKey: `legacy-section-${type}`, fileBase64: Buffer.from("synthetic evidence").toString("base64"), contentType: mime, fileName: "evidence"}, context);
    const before = (await db.collection("riderProfiles").doc(uid).get()).data();
    assert.equal((await acknowledge(section)).derivedFromDocuments, true);
    assert.equal((await acknowledge(section)).status, "submitted");
    assert.deepEqual((await db.collection("riderProfiles").doc(uid).get()).data(), before);
    assert.equal((await db.collection("riderApplications").doc(uid).get()).exists, false);
    await assert.rejects(acknowledge(section, {status: "approved"}), {code: "permission-denied"});
    await assert.rejects(acknowledge(section, {verificationStatus: "verified"}), {code: "permission-denied"});
    await assert.rejects(functions.updateRiderApplicationSection.run({section, status: "submitted"}, {auth: {uid: "wrong-section-rider", token: {}}}), {code: "failed-precondition"});
  }
  await assert.rejects(functions.updateRiderApplicationSection.run({section: "identity_verification", status: "submitted"}, {}), {code: "unauthenticated"});
  const docs = await db.collection("riderDocuments").where("riderId", "==", uid).get();
  await Promise.all(docs.docs.map((doc) => doc.ref.update({status: "rejected"})));
  await assert.rejects(acknowledge("identity_verification"), {code: "failed-precondition"});
});

test("legacy multipart section acknowledgement preserves backend review and application state", async () => {
  const uid = "legacy-multipart-section";
  const context = {auth: {uid, token: {}}};
  await functions.submitRiderDocument.run({documentType: "driving_licence", files: [file("front", "front"), file("back", "back")], idempotencyKey: "legacy-multipart-section"}, context);
  await db.collection("riderApplications").doc(uid).set({status: "under_review", sectionStatus: {identity_verification: "needs_attention"}});
  const before = (await db.collection("riderApplications").doc(uid).get()).data();
  const result = await functions.updateRiderApplicationSection.run({section: "identity_verification", status: "submitted"}, context);
  assert.equal(result.derivedFromDocuments, true);
  assert.deepEqual((await db.collection("riderApplications").doc(uid).get()).data(), before);
});
