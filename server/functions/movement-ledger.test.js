/* eslint-disable max-len */
"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {FieldValue} = require("firebase-admin/firestore");
const movement = require("./movement-ledger");

test("gift movement remains held until ready for dispatch", () => {
  const pending = movement.giftMovement("g1", {status: "procuring", senderId: "u1"});
  assert.equal(pending.serviceType, "GIFTS");
  assert.equal(pending.status, "awaiting_procurement");
  assert.equal(pending.matchingStatus, "held");

  const ready = movement.giftMovement("g1", {status: "packed", senderId: "u1"});
  assert.equal(ready.status, "requested");
  assert.equal(ready.matchingStatus, "available");
});

test("Health+ movement remains held until collection details are ready", () => {
  const scheduled = movement.healthMovement("h1", {status: "scheduled"});
  assert.equal(scheduled.serviceType, "HEALTH_PLUS");
  assert.equal(scheduled.status, "scheduled");
  assert.equal(scheduled.matchingStatus, "held");

  const ready = movement.healthMovement("h1", {
    status: "scheduled",
    collectionDetailsReady: true,
  });
  assert.equal(ready.status, "requested");
  assert.equal(ready.matchingStatus, "available");
});

test("movement delivery ids are deterministic", () => {
  assert.equal(movement.giftMovement("abc", {}).deliveryId, "gift_abc");
  assert.equal(movement.healthMovement("xyz", {}).deliveryId, "health_xyz");
});

test("Gift projection preserves Rider authority without inventing earnings", () => {
  const projected = movement.giftMovement("g2", {
    status: "packed",
    riderEarning: 19.5,
    riderEligibleFare: 30,
    riderPayoutCalculationVersion: "65_35_v1",
    pickupDetails: {address: "1 Gift Street", locality: "Camden"},
    dropoffDetails: {address: "2 Recipient Road", locality: "Hackney"},
    route: {distanceText: "5.2 mi", durationText: "24 min"},
    iris: {rank: "amber"},
    handlingInstructions: "Keep upright",
  });
  assert.equal(projected.isGift, true);
  assert.equal(projected.riderEarning, 19.5);
  assert.equal(projected.riderEligibleFare, 30);
  assert.equal(projected.distanceText, "5.2 mi");
  assert.equal(projected.pickupLocality, "Camden");
  assert.deepEqual(projected.iris, {rank: "amber"});
  assert.equal(movement.giftMovement("g3", {price: 100}).riderEarning, undefined);
});

test("Gift movement never projects Gift Story voice metadata to Rider", () => {
  const projected = movement.giftMovement("g-voice", {
    status: "packed",
    senderId: "sender-1",
    voiceNote: {
      storagePath: "giftAssets/sender-1/voice.m4a",
      downloadUrl: "https://storage.example/voice.m4a?token=secret",
      mimeType: "audio/mp4",
      durationSeconds: 42,
    },
    voiceNoteUrl: "https://storage.example/legacy.webm",
    giftStorySenderVoiceNoteUrl: "https://storage.example/story.webm",
  });

  expectNoGiftStoryVoice(projected);
});

test("Gift projection redacts stale Rider voice fields on merge", () => {
  const patch = movement.riderGiftStoryVoiceRedaction();
  const expectedFields = [
    "voiceNote",
    "voiceNoteUrl",
    "giftStorySenderVoiceNoteUrl",
    "giftStoryCustomAudioUrl",
    "voiceStoragePath",
    "voiceMimeType",
    "voiceDuration",
    "voiceDurationSeconds",
  ];

  assert.deepEqual(Object.keys(patch).sort(), expectedFields.sort());
  for (const value of Object.values(patch)) {
    assert.equal(value.isEqual(FieldValue.delete()), true);
  }
});

test("Health+ projection preserves classification route and payout", () => {
  const projected = movement.healthMovement("h2", {
    collectionDetailsReady: true,
    pharmacyAddressData: {address: "1 Pharmacy Way", locality: "Brixton"},
    deliveryAddressData: {address: "2 Patient Close", locality: "Clapham"},
    authoritativeRoute: {distanceMeters: 2400, durationSeconds: 900},
    riderEarning: 13,
    riderEligibleFare: 20,
    specialInstructions: "Temperature controlled",
  });
  assert.equal(projected.isHealthPlus, true);
  assert.equal(projected.riderEarning, 13);
  assert.equal(projected.routeDistanceMeters, 2400);
  assert.equal(projected.pickupLocality, "Brixton");
  assert.equal(projected.handlingInstructions, "Temperature controlled");
});

function expectNoGiftStoryVoice(projected) {
  for (const key of [
    "voiceNote",
    "voiceNoteUrl",
    "giftStorySenderVoiceNoteUrl",
    "giftStoryCustomAudioUrl",
    "voiceStoragePath",
    "voiceMimeType",
    "voiceDuration",
    "voiceDurationSeconds",
  ]) {
    assert.equal(Object.hasOwn(projected, key), false, `${key} must not be projected`);
  }
}
