"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {initializeTestEnvironment, assertFails, assertSucceeds} = require("@firebase/rules-unit-testing");
const {doc, setDoc} = require("firebase/firestore");
const {ref, uploadBytes, getBytes, deleteObject} = require("firebase/storage");

const projectId = "circum-2797c";
let environment;

test.before(async () => {
  environment = await initializeTestEnvironment({
    projectId,
    firestore: {host: "127.0.0.1", port: 8080, rules: fs.readFileSync(path.join(__dirname, "../../firestore.rules"), "utf8")},
    storage: {host: "127.0.0.1", port: 9199, rules: fs.readFileSync(path.join(__dirname, "../../storage.rules"), "utf8")},
  });
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "deliveryRequests/delivery-1"), {
      senderId: "sender-1",
      riderId: "rider-1",
      driverId: "rider-1",
      assignedDriverId: "rider-1",
      status: "arrived_at_pickup",
    });
  });
});

test.after(async () => environment && environment.cleanup());

function bytes() {
  return new Uint8Array([0xff, 0xd8, 0xff, 0xd9]);
}

function metadata(overrides = {}) {
  return {
    contentType: "image/jpeg",
    customMetadata: {
      deliveryId: "delivery-1",
      uploadedBy: "rider-1",
      evidenceType: "weight_discrepancy",
      ...overrides,
    },
  };
}

test("only assigned Rider can create immutable weight discrepancy evidence", async () => {
  const path = "delivery-discrepancies/delivery-1/rider-1/photo.jpg";
  const riderStorage = environment.authenticatedContext("rider-1", {role: "rider", adminRole: "rider", roles: []}).storage();
  await assertSucceeds(uploadBytes(ref(riderStorage, path), bytes(), metadata()));
  await assertSucceeds(getBytes(ref(riderStorage, path)));
  await assertFails(deleteObject(ref(riderStorage, path)));

  const wrongRider = environment.authenticatedContext("rider-2", {role: "rider", adminRole: "rider", roles: []}).storage();
  await assertFails(uploadBytes(ref(wrongRider, "delivery-discrepancies/delivery-1/rider-2/photo.jpg"), bytes(), metadata({uploadedBy: "rider-2"})));
  const sender = environment.authenticatedContext("sender-1", {role: "sender", adminRole: "sender", roles: []}).storage();
  await assertFails(getBytes(ref(sender, path)));
  await assertFails(uploadBytes(ref(riderStorage, "delivery-discrepancies/delivery-1/rider-1/bad.jpg"), bytes(), metadata({deliveryId: "delivery-2"})));
});

test("legacy native Rider path remains assigned-Rider-only and metadata-bound", async () => {
  const riderStorage = environment.authenticatedContext("rider-1", {role: "rider", adminRole: "rider", roles: []}).storage();
  const path = "delivery_weight_evidence/delivery-1/discrepancy/native.jpg";
  await assertSucceeds(uploadBytes(ref(riderStorage, path), bytes(), metadata()));
  await assertFails(uploadBytes(ref(riderStorage, "delivery_weight_evidence/delivery-1/discrepancy/bad.jpg"), bytes(), metadata({evidenceType: "other"})));
  const sender = environment.authenticatedContext("sender-1", {role: "sender", adminRole: "sender", roles: []}).storage();
  await assertFails(getBytes(ref(sender, path)));
  assert.ok(true);
});
