/* eslint-disable max-len, require-jsdoc */
const {test, before, after} = require("node:test");
const assert = require("node:assert/strict");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const {getStorage} = require("firebase-admin/storage");
const enabled = Boolean(
  process.env.FIRESTORE_EMULATOR_HOST && process.env.STORAGE_EMULATOR_HOST,
);
let app;
let db;
let bucket;
before(() => {
  if (enabled) {
    app = initializeApp({
      projectId: "demo-completion-evidence",
      storageBucket: "demo-completion-evidence.appspot.com",
    });
    db = getFirestore();
    bucket = getStorage().bucket();
  }
});
after(async () => {
  if (app) await deleteApp(app);
});
const ctx = {auth: {uid: "evidence-rider", token: {}}, app: {appId: "test"}};
const jpeg = Buffer.from([255, 216, 255, 224, 0, 2, 255, 217]).toString(
  "base64",
);
const evidence = () => require("./delivery-evidence");
const complete = (id, extra = {}, context = ctx) =>
  require("./delivery-completion-reconciled").completeDelivery.run(
    {deliveryId: id, ...extra},
    context,
  );
async function fixture(id) {
  await db.doc(`deliveryRequests/${id}`).set({
    riderId: ctx.auth.uid,
    senderId: "evidence-sender",
    status: "arrived_at_dropoff",
    paymentStatus: "paid",
    serviceType: "standard",
    riderEarning: 6,
  });
  await db.doc(`riderProfiles/${ctx.auth.uid}`).set({trustPoints: 0});
}
const upload = (id, stage = "handover", extra = {}) =>
  evidence().recordDeliveryEvidence.run(
    {deliveryId: id, stage, imageBase64: jpeg, ...extra},
    ctx,
  );
test(
  "inline evidence rejects invalid MIME, signature, size, owner and terminal lifecycle",
  {skip: !enabled},
  async () => {
    await fixture("upload");
    await assert.rejects(
      upload("upload", "handover", {contentType: "text/html"}),
      /Unsupported/,
    );
    await assert.rejects(
      upload("upload", "handover", {
        imageBase64: Buffer.from("not an image").toString("base64"),
      }),
      /bytes/,
    );
    await assert.rejects(
      upload("upload", "handover", {
        imageBase64: Buffer.alloc(8 * 1024 * 1024 + 1).toString("base64"),
      }),
      /large|oversized/,
    );
    await assert.rejects(
      evidence().recordDeliveryEvidence.run(
        {deliveryId: "upload", stage: "handover", imageBase64: jpeg},
        {auth: {uid: "wrong"}},
      ),
      /assigned Rider/,
    );
    await assert.rejects(
      evidence().submitDeliveryEvidence.run(
        {deliveryId: "upload", stage: "handover", imageBase64: jpeg},
        {auth: ctx.auth},
      ),
      /Security verification/,
    );
    await db.doc("deliveryRequests/upload").update({status: "completed"});
    await assert.rejects(upload("upload"), /open delivery/);
  },
);
test(
  "concurrent record/submit retries create one immutable verified evidence record",
  {skip: !enabled},
  async () => {
    await fixture("retry");
    const results = await Promise.all([
      upload("retry"),
      upload("retry"),
      evidence().submitDeliveryEvidence.run(
        {deliveryId: "retry", stage: "handover", imageBase64: jpeg},
        ctx,
      ),
    ]);
    assert.equal(new Set(results.map((r) => r.evidenceId)).size, 1);
    assert.equal(
      (await db.doc("deliveryEvidence/retry").get()).data().verifiedPhotoCount,
      1,
    );
    const record = (
      await db.doc(`deliveryEvidence/${results[0].evidenceId}`).get()
    ).data();
    assert.equal(record.visibility, "sender_safe");
    await evidence()._private.validateRecord(record, {
      deliveryId: "retry",
      riderId: ctx.auth.uid,
      requiredStage: "handover",
      bucket,
    });
  },
);
test(
  "live completion denies absent/forged/wrong-delivery/owner/stage evidence and retains exactly-once settlement",
  {skip: !enabled},
  async () => {
    await fixture("complete");
    await assert.rejects(complete("complete"), /Verified deliveryEvidence/);
    await db.doc("deliveryEvidence/complete").set({verifiedPhotoCount: 99});
    await assert.rejects(complete("complete"), /No valid owned/);
    const pickup = await upload("complete", "pickup");
    await assert.rejects(
      complete("complete", {evidenceId: pickup.evidenceId}),
      /wrong stage/,
    );
    await fixture("other-job");
    const other = await upload("other-job");
    await assert.rejects(
      complete("complete", {evidenceId: other.evidenceId}),
      /this delivery/,
    );
    const valid = await upload("complete");
    const ref = db.doc(`deliveryEvidence/${valid.evidenceId}`);
    const original = (await ref.get()).data();
    await ref.update({riderId: "someone-else"});
    await assert.rejects(
      complete("complete", {evidenceId: valid.evidenceId}),
      /this rider/,
    );
    await ref.set(original);
    await assert.rejects(
      complete(
        "complete",
        {evidenceId: valid.evidenceId},
        {auth: {uid: "loser"}},
      ),
      /assigned rider/,
    );
    const results = await Promise.all([
      complete("complete", {evidenceId: valid.evidenceId}),
      complete("complete", {evidenceId: valid.evidenceId}),
    ]);
    assert.equal(results.filter((r) => r.idempotent).length, 1);
    assert.equal(
      (await db.doc("deliveryRequests/complete").get()).data().status,
      "delivered",
    );
    assert.equal(
      (await db.doc(`riderEarnings/${ctx.auth.uid}`).get()).data()
        .availableBalance,
      6,
    );
    const canonicalRetry =
      await require("./delivery-tracking").updateDeliveryTrackingStatus.run(
        {
          deliveryId: "complete",
          action: "verify_receiver_pin",
          evidence: {evidenceId: valid.evidenceId},
        },
        ctx,
      );
    assert.equal(canonicalRetry.idempotent, true);
    assert.equal(
      (await db.collection("riderEarningTransactions").get()).size,
      1,
    );
  },
);
test(
  "completion retains product settlement and payment gates",
  {skip: !enabled},
  async () => {
    await fixture("health-domain");
    await db
      .doc("deliveryRequests/health-domain")
      .update({serviceType: "health_plus", product: "health_plus"});
    await assert.rejects(complete("health-domain"), /domain completion/);
    await fixture("unpaid");
    await db.doc("deliveryRequests/unpaid").update({paymentStatus: "pending"});
    await assert.rejects(complete("unpaid"), /payment authority/);
  },
);

test(
  "background settlement cannot bypass verified evidence on a legacy pending delivery",
  {skip: !enabled},
  async () => {
    await fixture("pending");
    await db.doc("deliveryRequests/pending").update({
      status: "settlement_pending",
      settlementStatus: "pending_authority",
    });
    const reconcile = require("./delivery-tracking")._private
      .reconcileSettlementPendingDelivery;
    assert.equal((await reconcile(db, "pending")).status, "pending_authority");
    assert.equal(
      (await db.doc("riderEarningTransactions/pending").get()).exists,
      false,
    );
    // An already captured, backend verified handover remains usable by recovery.
    await db
      .doc("deliveryRequests/pending")
      .update({status: "arrived_at_dropoff"});
    const photo = await upload("pending");
    await db.doc("deliveryRequests/pending").update({
      status: "settlement_pending",
      handoverEvidence: {evidenceId: photo.evidenceId},
    });
    assert.equal((await reconcile(db, "pending")).status, "delivered");
    assert.equal((await reconcile(db, "pending")).idempotent, true);
  },
);
test("deployed record v13 and submit v2 evidence schemas retain valid handover completion", {skip: !enabled}, async () => {
  for (const legacy of [
    {id: "record-v13", prefix: "deliveryEvidence", stage: "dropoff", status: "finalized"},
    {id: "submit-v2", prefix: "delivery_evidence", stage: "handover", status: "verified"},
  ]) {
    await fixture(legacy.id);
    const storagePath = `${legacy.prefix}/${legacy.id}/${ctx.auth.uid}/photo.jpg`;
    await bucket.file(storagePath).save(Buffer.from(jpeg, "base64"), {metadata: {contentType: "image/jpeg", metadata: {deliveryId: legacy.id, riderId: ctx.auth.uid, stage: legacy.stage}}});
    await db.doc(`deliveryEvidence/legacy-${legacy.id}`).set({deliveryId: legacy.id, riderId: ctx.auth.uid, stage: legacy.stage, status: legacy.status, storagePath, contentType: "image/jpeg"});
    assert.equal((await complete(legacy.id, {evidenceId: `legacy-${legacy.id}`})).status, "delivered");
  }
});
