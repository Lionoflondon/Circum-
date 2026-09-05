/* eslint-disable max-len */
const test = require("node:test");
const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const fs = require("node:fs");
const os = require("node:os");

process.env.FIREBASE_CONFIG = JSON.stringify({
  projectId: "demo-rider-onboarding",
  storageBucket: "demo-rider-onboarding.appspot.com",
});
process.env.GCLOUD_PROJECT = "demo-rider-onboarding";
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
require("./index");
const db = admin.firestore();
const bucket = admin.storage().bucket();


const presence = require("./rider-presence");
const account = require("./rider-account");
const location = {latitude: 51.5, longitude: -0.1, accuracyMeters: 10, permission: "always", gpsStatus: "active"};
const profile = {fullName: "Test Rider", phoneNumber: "07700900123", postcode: "SW1A 1AA", homeAddress: "Test address", vehicleType: "car", vehicleRegistration: "AB12 CDE"};
const context = (uid) => ({auth: {uid, token: {email: uid + "@example.test"}}});

test("full Auth/application/PDF/image/review flow preserves zero wallet and approved online authority", async () => {
  assert.ok(process.env.FIREBASE_AUTH_EMULATOR_HOST && process.env.FIRESTORE_EMULATOR_HOST && process.env.FIREBASE_STORAGE_EMULATOR_HOST, "emulators required");
  const user = await admin.auth().createUser({email: "flow@example.test", password: "Emulator-only-123!"});
  const ctx = context(user.uid);
  assert.equal((await account.verifyRiderAccountAccess.run({}, ctx)).profileExists, false);
  await account.updateRiderProfile.run(profile, ctx);
  assert.equal((await account.verifyRiderAccountAccess.run({}, ctx)).profileExists, true);
  await account.ensureRiderRothWallet.run({}, ctx);
  assert.equal((await db.collection("riderRothWallets").doc(user.uid).get()).data().balance, 0);
  const request = {idempotencyKey: "onboarding-flow"};
  const [first, retry] = await Promise.all([account.submitRiderApplication.run(request, ctx), account.submitRiderApplication.run(request, ctx)]);
  assert.equal(first.applicationId, retry.applicationId);
  assert.equal((await db.collection("riderApplications").doc(user.uid).get()).data().status, "submitted");
  assert.equal((await db.collection("riderProfiles").doc(user.uid).get()).data().vehicleType, "car");
  for (const [type, contentType, body] of [["passport", "application/pdf", "%PDF-1.4 test"], ["vehicle_registration", "image/png", "image-emulator-bytes"]]) {
    await account.submitRiderDocument.run({documentType: type, contentType, fileBase64: Buffer.from(body).toString("base64"), fileName: type, idempotencyKey: "flow-" + type}, ctx);
  }
  const docs = await db.collection("riderDocuments").where("riderId", "==", user.uid).get();
  assert.deepEqual(docs.docs.map((d) => d.data().type).sort(), ["identity", "registration_v5c"]);
  assert.ok(docs.docs.every((d) => d.data().status === "pending"));
  await assert.rejects(presence.goOnline.run({location}, ctx), (e) => e.code === "failed-precondition");
  // Admin SDK writes are intentionally restricted to this emulator fixture.
  await db.collection("riderProfiles").doc(user.uid).set({approvalStatus: "approved", verificationStatus: "approved", onboardingComplete: true, vehicleApproved: true, onboardingStatus: "approved", riderRank: "senior", trustPoints: 42}, {merge: true});
  await db.collection("riderApplications").doc(user.uid).set({status: "approved"}, {merge: true});
  const online = await presence.goOnline.run({location}, ctx);
  assert.equal(online.success, true);
  await account.submitRiderApplication.run({idempotencyKey: "another-key"}, ctx);
  const approved = (await db.collection("riderProfiles").doc(user.uid).get()).data();
  assert.equal(approved.approvalStatus, "approved");
  assert.equal(approved.trustPoints, 42);
  assert.equal(approved.riderRank, "senior");
});

test("required fields are precise; documents and optional notes never gate initial submission", async () => {
  for (const [field, message] of [["fullName", "Enter your full name."], ["phoneNumber", "Enter your phone number."], ["postcode", "Enter your postcode."], ["homeAddress", "Enter your address."], ["vehicleType", "Choose Motorbike, Car or Van."], ["vehicleRegistration", "Enter your vehicle registration."]]) {
    await assert.rejects(account.submitRiderApplication.run({...profile, [field]: ""}, context("missing-" + field)), (e) => e.code === "invalid-argument" && e.message === message);
  }
  const result = await account.submitRiderApplication.run({...profile, notes: ""}, context("no-docs"));
  assert.equal(result.status, "submitted");
});

test("wrong surface denied, shared idempotency keys cannot leak another Rider application", async () => {
  for (const role of ["sender", "admin"]) {
    await db.collection("users").doc(role).set({role});
    await assert.rejects(account.verifyRiderAccountAccess.run({}, context(role)), (e) => e.code === "permission-denied");
    await assert.rejects(account.updateRiderProfile.run(profile, context(role)), (e) => e.code === "permission-denied");
    assert.equal((await db.collection("riderProfiles").doc(role).get()).exists, false);
  }
  await db.collection("users").doc("legacy-sender").set({name: "Existing Sender"});
  await db.collection("adminUsers").doc("admin-record").set({active: true});
  for (const uid of ["legacy-sender", "admin-record"]) {
    await assert.rejects(account.verifyRiderAccountAccess.run({}, context(uid)), (e) => e.code === "permission-denied");
  }
  await assert.rejects(account.verifyRiderAccountAccess.run({}, {auth: {uid: "admin-claim", token: {adminRole: "operations_admin"}}}), (e) => e.code === "permission-denied");
  await db.collection("riderProfiles").doc("legacy-sender").set({name: "Old client-forged shell"});
  await assert.rejects(account.verifyRiderAccountAccess.run({}, context("legacy-sender")), (e) => e.code === "permission-denied");
  await db.collection("riderProfiles").doc("legacy-rider").set({approvalStatus: "pending"});
  await account.verifyRiderAccountAccess.run({}, context("legacy-rider"));
  const a = await account.submitRiderApplication.run({...profile, idempotencyKey: "shared-key"}, context("rider-a"));
  const b = await account.submitRiderApplication.run({...profile, idempotencyKey: "shared-key"}, context("rider-b"));
  assert.notEqual(a.applicationId, b.applicationId);
  for (const section of ["personal_details", "identity_verification", "review_status", "vehicle_documents"]) {
    await assert.rejects(account.updateRiderApplicationSection.run({section, status: "approved"}, context("rider-a")), (e) => e.code === "permission-denied");
    if (section !== "personal_details") {
      await assert.rejects(account.updateRiderProfile.run({section}, context("rider-a")), (e) => e.code === "permission-denied");
    }
  }
});

test("concurrent document retries retain one record/object, reject changed content and preserve review", async () => {
  const ctx = context("parallel-upload");
  const data = {documentType: "passport", contentType: "application/pdf", fileName: "id.pdf", fileBase64: Buffer.from("%PDF-test").toString("base64"), idempotencyKey: "concurrent-upload"};
  const results = await Promise.all(Array.from({length: 3}, () => account.submitRiderDocument.run(data, ctx)));
  assert.equal(new Set(results.map((r) => r.documentId)).size, 1);
  const [objects] = await bucket.getFiles({prefix: "rider_documents/parallel-upload/"});
  assert.equal(objects.length, 1);
  await db.collection("riderDocuments").doc(results[0].documentId).update({status: "approved"});
  await account.submitRiderDocument.run(data, ctx);
  assert.equal((await db.collection("riderDocuments").doc(results[0].documentId).get()).data().status, "approved");
  await assert.rejects(account.submitRiderDocument.run({...data, fileBase64: Buffer.from("different").toString("base64")}, ctx), (e) => e.code === "already-exists");
});

test("8 MiB document uses bounded chunks, finalizes once and clears temporary objects", async () => {
  const ctx = context("large-document");
  const bytes = Buffer.alloc(8 * 1024 * 1024, 65);
  bytes.write("%PDF-1.4\n");
  const manifest = {side: "primary", contentType: "application/pdf", fileName: "large.pdf", sizeBytes: bytes.length, sha256: crypto.createHash("sha256").update(bytes).digest("hex")};
  const base = {documentType: "identity", idempotencyKey: "large-file-upload"};
  for (let i = 0; i < 4; i += 1) {
    const request = {...base, chunk: {...manifest, index: i, base64: bytes.subarray(i * 2 * 1024 * 1024, (i + 1) * 2 * 1024 * 1024).toString("base64")}};
    assert.ok(Buffer.byteLength(JSON.stringify(request)) < 10 * 1000 * 1000);
    await account.submitRiderDocument.run(request, ctx);
    await account.submitRiderDocument.run(request, ctx);
  }
  const request = {...base, stagedFiles: [manifest]};
  const result = await account.submitRiderDocument.run(request, ctx);
  const replay = await account.submitRiderDocument.run(request, ctx);
  assert.equal(replay.documentId, result.documentId);
  const document = (await db.collection("riderDocuments").doc(result.documentId).get()).data();
  assert.equal(document.sizeBytes, bytes.length);
  const [temporary] = await bucket.getFiles({prefix: "rider_document_chunks/large-document/"});
  assert.equal(temporary.length, 0);
  await assert.rejects(account.submitRiderDocument.run({...base, chunk: {...manifest, sizeBytes: bytes.length + 1, index: 0, base64: "AA=="}}, ctx));
});
