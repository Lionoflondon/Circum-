/* eslint-disable require-jsdoc */
"use strict";

const FIXTURE_COLLECTION = "giftStoryRuntimeFixtures";

function isFixtureDeliveryId(deliveryId) {
  return /^__codex_[A-Za-z0-9_-]{1,100}$/.test(String(deliveryId || ""));
}

function fixtureDb(rawDb, deliveryId) {
  if (!isFixtureDeliveryId(deliveryId)) throw Object.assign(new Error("invalid_fixture_delivery_id"), {statusCode: 400});
  const root = rawDb.collection(FIXTURE_COLLECTION).doc(deliveryId);
  return {
    fixtureMode: true,
    collection(name) {
      if (name === FIXTURE_COLLECTION) return rawDb.collection(name);
      if (!/^[A-Za-z][A-Za-z0-9]*$/.test(String(name || ""))) {
        throw new Error("invalid_fixture_collection");
      }
      return root.collection("state").doc(name).collection("records");
    },
    runTransaction: rawDb.runTransaction.bind(rawDb),
    batch: rawDb.batch.bind(rawDb),
  };
}

module.exports = {FIXTURE_COLLECTION, isFixtureDeliveryId, fixtureDb};
