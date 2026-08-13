"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {decodeImage, MAX_BYTES} = require("./delivery-evidence")._private;

test("delivery evidence accepts bounded approved images", () => {
  const jpeg = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10]);
  const result = decodeImage({contentType: "image/jpeg", imageBase64: jpeg.toString("base64")});
  assert.equal(result.contentType, "image/jpeg");
  assert.deepEqual(result.bytes, jpeg);
});

test("delivery evidence rejects unsupported and oversized payloads", () => {
  assert.throws(() => decodeImage({contentType: "application/pdf", imageBase64: "YQ=="}), /JPEG, PNG or WebP/);
  assert.throws(() => decodeImage({contentType: "image/jpeg", imageBase64: "a".repeat(Math.ceil(MAX_BYTES * 4 / 3) + 32)}), /too large/);
  assert.throws(() => decodeImage({contentType: "image/jpeg", imageBase64: Buffer.from("not a jpeg").toString("base64")}), /does not match/);
});
