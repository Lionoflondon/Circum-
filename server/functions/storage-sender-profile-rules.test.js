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
    projectId: "circum-sender-profile-storage-rules-test",
    storage: {
      rules: fs.readFileSync(path.join(__dirname, "..", "..", "storage.rules"), "utf8"),
    },
  });
});

test.after(async () => testEnv.cleanup());

test("Sender owns the canonical profile photo path and MIME contract", async () => {
  const owner = testEnv.authenticatedContext("sender-a").storage();
  const other = testEnv.authenticatedContext("sender-b").storage();

  await assertSucceeds(owner.ref("users/sender-a/profile/avatar.jpg").put(
      Buffer.from("jpeg"), {contentType: "image/jpeg"},
  ));
  await assertSucceeds(owner.ref("users/sender-a/profile/avatar.jpg").getDownloadURL());
  await assertFails(other.ref("users/sender-a/profile/avatar.jpg").getDownloadURL());
  await assertFails(other.ref("users/sender-a/profile/avatar.jpg").put(
      Buffer.from("forged"), {contentType: "image/jpeg"},
  ));
  await assertFails(owner.ref("users/sender-a/profile/avatar.gif").put(
      Buffer.from("gif"), {contentType: "image/gif"},
  ));
});

test("Sender profile photos reject oversized and unauthenticated uploads", async () => {
  const owner = testEnv.authenticatedContext("sender-a").storage();
  const anonymous = testEnv.unauthenticatedContext().storage();

  await assertFails(owner.ref("users/sender-a/profile/avatar.png").put(
      Buffer.alloc((8 * 1024 * 1024) + 1), {contentType: "image/png"},
  ));
  await assertFails(anonymous.ref("users/sender-a/profile/avatar.png").put(
      Buffer.from("anonymous"), {contentType: "image/png"},
  ));
});
