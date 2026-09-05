/* eslint-disable max-len, require-jsdoc */
const {test, before, after} = require("node:test");
const fs = require("node:fs");
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require("@firebase/rules-unit-testing");
let env;
before(async () => {
  env = await initializeTestEnvironment({
    projectId: process.env.GCLOUD_PROJECT || "demo-delivery-evidence",
    firestore: {
      rules: fs.readFileSync(`${__dirname}/../../firestore.rules`, "utf8"),
    },
    storage: {
      rules: fs.readFileSync(`${__dirname}/../../storage.rules`, "utf8"),
    },
  });
  await env.withSecurityRulesDisabled(async (c) =>
    c
      .firestore()
      .doc("deliveryRequests/evidence-storage-job")
      .set({riderId: "rider", senderId: "sender", status: "accepted"}),
  );
});
after(async () => env.cleanup());
const path = "delivery_weight_evidence/evidence-storage-job/pickup/123.jpg";
const meta = {
  contentType: "image/jpeg",
  customMetadata: {
    deliveryId: "evidence-storage-job",
    uploadedBy: "rider",
    evidenceType: "weight_discrepancy",
  },
};
test("assigned Rider uploads evidence; missing metadata, wrong rider, Sender, MIME and oversize fail", async () => {
  const rider = env.authenticatedContext("rider").storage();
  await assertFails(
    rider.ref(path).put(Buffer.from("jpeg"), {contentType: "image/jpeg"}),
  );
  await assertFails(
    env
      .authenticatedContext("other")
      .storage()
      .ref(path)
      .put(Buffer.from("jpeg"), meta),
  );
  await assertFails(
    env
      .authenticatedContext("sender")
      .storage()
      .ref(path)
      .put(Buffer.from("jpeg"), meta),
  );
  await assertFails(
    rider
      .ref(path)
      .put(Buffer.from("jpeg"), {...meta, contentType: "text/html"}),
  );
  await assertFails(
    rider.ref(path).put(Buffer.alloc(15 * 1024 * 1024 + 1), meta),
  );
  await assertSucceeds(rider.ref(path).put(Buffer.from("jpeg"), meta));
});
test("evidence is immutable and unrelated readers are denied, Admin audit read succeeds", async () => {
  const rider = env.authenticatedContext("rider").storage();
  await assertSucceeds(rider.ref(path).getMetadata());
  await assertSucceeds(
    env
      .authenticatedContext("admin", {adminRole: "operations_admin"})
      .storage()
      .ref(path)
      .getMetadata(),
  );
  await assertFails(
    env.authenticatedContext("other").storage().ref(path).getMetadata(),
  );
  await assertFails(rider.ref(path).put(Buffer.from("replacement"), meta));
  await assertFails(rider.ref(path).delete());
  await env.withSecurityRulesDisabled(async (c) =>
    c
      .firestore()
      .doc("deliveryRequests/evidence-storage-job")
      .update({status: "completed"}),
  );
  await assertFails(
    rider
      .ref("delivery_weight_evidence/evidence-storage-job/handover/456.jpg")
      .put(Buffer.from("jpeg"), meta),
  );
});
test("live discrepancy and Health+ evidence paths remain usable and immutable", async () => {
  await env.withSecurityRulesDisabled(async (c) => {
    await c.firestore().doc("deliveryRequests/live-path").set({
      riderId: "rider",
      driverId: "rider",
      assignedRiderId: "rider",
      assignedDriverId: "rider",
      status: "collected",
    });
    await c
      .firestore()
      .doc("prescriptionPickups/live-health")
      .set({assignedDriverId: "rider", status: "collected"});
  });
  const rider = env.authenticatedContext("rider").storage();
  const rows = [
    [
      "delivery-discrepancies/live-path/rider/evidence.png",
      {
        contentType: "image/png",
        customMetadata: {
          deliveryId: "live-path",
          uploadedBy: "rider",
          evidenceType: "weight_discrepancy",
        },
      },
    ],
    ...["pickup", "custody", "handover", "verification", "exception"].map(
      (stage) => [
        `health_delivery_evidence/live-health/${stage}/evidence.jpg`,
        {
          contentType: "image/jpeg",
          customMetadata: {
            pickupId: "live-health",
            uploadedBy: "rider",
            evidenceType: stage,
          },
        },
      ],
    ),
  ];
  for (const [objectPath, metadata] of rows) {
    await assertSucceeds(
      rider.ref(objectPath).put(Buffer.from("image"), metadata),
    );
    await assertSucceeds(rider.ref(objectPath).getMetadata());
    await assertSucceeds(
      env
        .authenticatedContext("admin", {adminRole: "operations_admin"})
        .storage()
        .ref(objectPath)
        .getMetadata(),
    );
    await assertFails(
      env.authenticatedContext("other").storage().ref(objectPath).getMetadata(),
    );
    await assertFails(
      rider.ref(objectPath).put(Buffer.from("overwrite"), metadata),
    );
    await assertFails(rider.ref(objectPath).delete());
  }
});
test("all deployed Storage path families are retained, including private Gift Story voice", async () => {
  const rules = fs.readFileSync(`${__dirname}/../../storage.rules`, "utf8");
  const assert = require("node:assert/strict");
  for (const prefix of [
    "delivery-discrepancies",
    "delivery_weight_evidence",
    "health_delivery_evidence",
    "riderDocuments",
    "riders",
    "vehicleDocuments",
    "profilePhotos",
    "users",
    "rider-profiles",
    "businessUploads",
    "giftAssets",
    "giftStories",
    "irisReferenceImages",
    "gift_requests",
  ]) {
    assert.ok(rules.includes(`match /${prefix}/`), prefix);
  }
  const owner = env.authenticatedContext("voice-owner").storage();
  const objectPath = "gift_requests/voice-owner_123/voice/note.webm";
  await assertSucceeds(
    owner
      .ref(objectPath)
      .put(Buffer.from("audio"), {contentType: "audio/webm"}),
  );
  await assertSucceeds(owner.ref(objectPath).getMetadata());
  await assertFails(
    env.authenticatedContext("rider").storage().ref(objectPath).getMetadata(),
  );
});
