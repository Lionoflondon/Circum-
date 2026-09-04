/* eslint-disable max-len */
"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const voice = require("./rider-gift-voice");

const delivery = {
  assignedRiderId: "rider-1",
  status: "accepted",
  voiceNote: {
    storagePath: "gift_requests/sender-1_1784583541000/voice/original.m4a",
    mimeType: "audio/mp4",
    durationSeconds: 24,
  },
};

test("assigned Rider can resolve accepted Gift voice metadata", () => {
  assert.deepEqual(voice.authorizeRiderGiftVoice(delivery, "rider-1"), {
    storagePath: delivery.voiceNote.storagePath,
    mimeType: "audio/mp4",
    durationSeconds: 24,
  });
});

test("unassigned Rider and pre-accept offer cannot resolve Gift voice", () => {
  assert.throws(() => voice.authorizeRiderGiftVoice(delivery, "rider-2"), /assigned Rider/);
  assert.throws(() => voice.authorizeRiderGiftVoice({...delivery, status: "requested"}, "rider-1"), /Accept this Gift delivery/);
});

test("cross-delivery or invalid voice storage metadata is denied", () => {
  assert.throws(() => voice.authorizeRiderGiftVoice({
    ...delivery,
    voiceNote: {...delivery.voiceNote, storagePath: "giftAssets/other/voice.m4a"},
  }, "rider-1"), /no playable voice note/);
});
