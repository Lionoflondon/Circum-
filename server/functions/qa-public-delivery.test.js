"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const qaPublic = require("./qa-public-delivery");

const fixtureId = "f".repeat(64);
const env = {
  GCLOUD_PROJECT: "circum-2797c",
  STRIPE_MODE: "TEST",
  QA_LIFECYCLE_ENABLED: "true",
  QA_LIFECYCLE_ALLOWLIST: JSON.stringify({operators: ["operator"], senders: ["sender"], riders: ["rider"]}),
};
const fixture = {
  id: fixtureId,
  isSyntheticQa: true,
  qaCreatedBy: "operator",
  senderId: "sender",
  riderId: "rider",
  expiresAt: {toMillis: () => Date.now() + 60000},
  archived: false,
  publicDeliveryId: `qa_public_${fixtureId}`,
};
const delivery = {
  isSyntheticQa: true,
  qaPublic: true,
  qaNamespace: "qaSpecialFlowFixtures",
  qaFixtureId: fixtureId,
  realDispatch: false,
  suppressExternalSideEffects: true,
  excludeFromSettlement: true,
  excludeFromPayout: true,
  requestId: `qa_public_${fixtureId}`,
  status: "requested",
  riderId: null,
};

function ref(path, snapshots) {
  const parts = path.split("/");
  return {
    path,
    id: parts.at(-1),
    parent: {id: parts.at(-2)},
    collection: (name) => collection(`${path}/${name}`, snapshots),
    get: async () => snapshots.get(path) || {exists: false, id: parts.at(-1), data: () => ({})},
  };
}

function collection(prefix, snapshots) {
  return {doc: (id) => ref(`${prefix}/${id}`, snapshots)};
}

function fakeDb() {
  const snapshots = new Map();
  const addSnapshot = (path, value) => {
    const snapshot = {exists: true, id: path.split("/").at(-1), data: () => value};
    snapshot.ref = ref(path, snapshots);
    snapshots.set(path, snapshot);
  };
  addSnapshot(`deliveryRequests/${delivery.requestId}`, delivery);
  addSnapshot(`qaSpecialFlowFixtures/${fixtureId}`, fixture);
  addSnapshot("riders/rider", {fullName: "QA Rider", vehicleType: "car"});
  return {
    collection: (name) => collection(name, snapshots),
    doc: (path) => ref(path, snapshots),
    runTransaction: async (callback) => callback({
      get: async (target) => snapshots.get(target.path) || {exists: false, data: () => ({})},
      set: () => {},
      create: () => {},
    }),
  };
}

test("accept allows the assigned QA Rider to claim an unassigned public fixture", async () => {
  const db = fakeDb();
  const context = {auth: {uid: "rider"}, app: {appId: "qa-app"}};

  await assert.rejects(
      qaPublic.authorizePublicDelivery(db, context, delivery.requestId, env),
      /QA delivery access is not permitted/,
  );

  const result = await qaPublic.accept({db, context, deliveryId: delivery.requestId, env});
  assert.deepEqual(result, {
    status: "accepted",
    requestId: delivery.requestId,
    riderId: "rider",
    senderNotified: false,
    idempotent: false,
    qaOnly: true,
  });
});
