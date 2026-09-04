/* eslint-disable max-len */
"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

const media = require("./gift-voice-media");

test("gift voice storage paths are owned, canonical, and timestamped", () => {
  assert.deepEqual(
      media.parseGiftVoiceStoragePath("gift_requests/sender-1_1784583541000/voice/original.webm"),
      {
        ownerId: "sender-1",
        uploadedAtMillis: 1784583541000,
        storagePath: "gift_requests/sender-1_1784583541000/voice/original.webm",
      },
  );
  assert.equal(media.parseGiftVoiceStoragePath("gift_requests/sender-1/voice/original.webm"), null);
  assert.equal(media.parseGiftVoiceStoragePath("giftAssets/gift-1/voice.webm"), null);
  assert.deepEqual(
      media.parseGiftVoiceStoragePath("gift_requests/sender-1_1784583541000/voice/original.m4a"),
      {
        ownerId: "sender-1",
        uploadedAtMillis: 1784583541000,
        storagePath: "gift_requests/sender-1_1784583541000/voice/original.m4a",
      },
  );
});

test("gift voice metadata is backend-normalized before Gift Story use", () => {
  assert.deepEqual(media.sanitizeGiftVoiceNoteMetadata({
    hasVoiceNote: true,
    durationSeconds: 12,
    storagePath: "gift_requests/sender-1_1784583541000/voice/original.webm",
    downloadUrl: "https://storage.example/voice.webm",
    mimeType: "audio/webm",
    uploadStatus: "client_value",
    retryState: "client_value",
    ownerId: "other",
  }, "sender-1"), {
    hasVoiceNote: true,
    durationSeconds: 12,
    storagePath: "gift_requests/sender-1_1784583541000/voice/original.webm",
    downloadUrl: "https://storage.example/voice.webm",
    mimeType: "audio/webm",
    createdAt: null,
    uploadStatus: "uploaded",
    retryState: "none",
    version: 1,
    ownerId: "sender-1",
  });
});

test("gift voice metadata rejects forged ownership and unsafe duration", () => {
  assert.throws(() => media.sanitizeGiftVoiceNoteMetadata({
    durationSeconds: 12,
    storagePath: "gift_requests/other_1784583541000/voice/original.webm",
    downloadUrl: "https://storage.example/voice.webm",
    mimeType: "audio/webm",
  }, "sender-1"), /Gift voice note does not belong/);

  assert.throws(() => media.sanitizeGiftVoiceNoteMetadata({
    durationSeconds: 61,
    storagePath: "gift_requests/sender-1_1784583541000/voice/original.webm",
    downloadUrl: "https://storage.example/voice.webm",
    mimeType: "audio/webm",
  }, "sender-1"), /duration is invalid/);
});

test("gift voice storage verification checks existence, type, size, and owner", async () => {
  const calls = [];
  const bucket = {
    file(path) {
      calls.push(path);
      return {
        async exists() {
          return [true];
        },
        async getMetadata() {
          return [{
            contentType: "audio/webm",
            size: "2048",
            metadata: {ownerId: "sender-1"},
          }];
        },
      };
    },
  };

  const verified = await media.verifyGiftVoiceStorageObject({
    bucket,
    senderId: "sender-1",
    voiceNote: {
      durationSeconds: 12,
      storagePath: "gift_requests/sender-1_1784583541000/voice/original.webm",
      downloadUrl: "https://storage.example/voice.webm",
      mimeType: "audio/webm",
    },
  });

  assert.equal(calls[0], "gift_requests/sender-1_1784583541000/voice/original.webm");
  assert.equal(verified.ownerId, "sender-1");
});

test("gift voice lifecycle audit records operational ownership and outcome", () => {
  const record = media.giftVoiceLifecycleAudit({
    action: "gift_voice_media_attached",
    actorUid: "sender-1",
    giftDraftId: "draft-1",
    giftRequestId: "gift-1",
    storagePath: "gift_requests/sender-1_1784583541000/voice/original.webm",
    reason: "client_payment_recovery",
  });
  assert.equal(record.action, "gift_voice_media_attached");
  assert.equal(record.actorUid, "sender-1");
  assert.equal(record.outcome, "success");
  assert.equal(record.reason, "client_payment_recovery");
});
