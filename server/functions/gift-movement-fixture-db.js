"use strict";

const FIXTURE_COLLECTION = "giftMovementRuntimeFixtures";
const FIXTURE_SUBCOLLECTIONS = new Set([
  "giftRequests", "deliveryRequests", "giftMovementProjectionClaims",
]);

function validFixtureId(id) {
  return /^__codex_gift_movement_[A-Za-z0-9_-]{1,64}$/.test(String(id || ""));
}

function fixtureDb(rawDb, fixtureId) {
  if (!validFixtureId(fixtureId)) throw new Error("invalid_gift_movement_fixture_id");
  const root = rawDb.collection(FIXTURE_COLLECTION).doc(fixtureId);
  return {
    collection(name) {
      if (!FIXTURE_SUBCOLLECTIONS.has(name)) throw new Error("invalid_gift_movement_fixture_collection");
      return root.collection(name);
    },
    runTransaction: rawDb.runTransaction.bind(rawDb),
  };
}

module.exports = {FIXTURE_COLLECTION, validFixtureId, fixtureDb};
