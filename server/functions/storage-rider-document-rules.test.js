/* eslint-disable max-len */
const test = require("node:test");
const fs = require("node:fs");
const path = require("node:path");
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require("@firebase/rules-unit-testing");

let testEnv;

test.before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: "circum-rider-storage-rules-test",
    storage: {
      rules: fs.readFileSync(path.join(__dirname, "..", "..", "storage.rules"), "utf8"),
    },
  });
});

test.after(async () => testEnv.cleanup());

async function assertClientUploadDenied(context, storagePath) {
  const storage = context.storage();
  await assertFails(storage.ref(storagePath).put(Buffer.from("test"), {
    contentType: "image/jpeg",
  }));
}

test("Rider cannot directly upload protected document binaries", async () => {
  const rider = testEnv.authenticatedContext("rider-a");
  await assertClientUploadDenied(rider, "riderDocuments/rider-a/front.jpg");
  await assertClientUploadDenied(rider, "riders/rider-a/documents/back.jpg");
  await assertClientUploadDenied(rider, "vehicleDocuments/rider-a/logbook.pdf");
});

test("Rider cannot upload another Rider's document or use the legacy path", async () => {
  const rider = testEnv.authenticatedContext("rider-a");
  await assertClientUploadDenied(rider, "riderDocuments/rider-b/front.jpg");
  await assertClientUploadDenied(rider, "riders/rider-b/documents/back.jpg");
  await assertClientUploadDenied(rider, "verification-photos/rider-a/front.jpg");
});

test("Unauthenticated clients cannot upload Rider documents", async () => {
  const anonymous = testEnv.unauthenticatedContext();
  await assertClientUploadDenied(anonymous, "riderDocuments/rider-a/front.jpg");
  await assertClientUploadDenied(anonymous, "vehicleDocuments/rider-a/document.pdf");
});

test("Rider profile photos enforce the canonical 10 MiB owner-only contract", async () => {
  const rider = testEnv.authenticatedContext("rider-a");
  const storage = rider.storage();
  const tenMiB = Buffer.alloc(10 * 1024 * 1024);

  await assertSucceeds(storage.ref("rider-profiles/rider-a/profile.jpg").put(
    tenMiB,
    {contentType: "image/jpeg"},
  ));
  await assertFails(storage.ref("rider-profiles/rider-a/profile.jpg").put(
    Buffer.alloc((10 * 1024 * 1024) + 1),
    {contentType: "image/jpeg"},
  ));
  await assertFails(storage.ref("rider-profiles/rider-b/profile.jpg").put(
    Buffer.from("test"),
    {contentType: "image/jpeg"},
  ));
  await assertFails(storage.ref("rider-profiles/rider-a/profile.jpg").put(
    Buffer.from("test"),
    {contentType: "application/pdf"},
  ));
});
