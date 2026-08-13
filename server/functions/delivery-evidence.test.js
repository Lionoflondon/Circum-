"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  decodeImage,
  evidenceAudienceAllowed,
  hasAdminClaim,
  MAX_BYTES,
} = require("./delivery-evidence")._private;

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

test("delivery evidence access is Rider, Sender proof, or Admin only", () => {
  const handover = {
    riderId: "rider-1",
    stage: "handover",
    purpose: "delivery_handover",
  };
  const discrepancy = {
    riderId: "rider-1",
    stage: "discrepancy",
    purpose: "delivery_discrepancy",
  };
  const delivery = {senderId: "sender-1"};

  assert.equal(evidenceAudienceAllowed({evidence: handover, delivery, uid: "rider-1"}), true);
  assert.equal(evidenceAudienceAllowed({evidence: handover, delivery, uid: "sender-1"}), true);
  assert.equal(evidenceAudienceAllowed({evidence: discrepancy, delivery, uid: "sender-1"}), false);
  assert.equal(evidenceAudienceAllowed({evidence: handover, delivery, uid: "other"}), false);
  assert.equal(evidenceAudienceAllowed({
    evidence: discrepancy,
    delivery,
    uid: "admin-1",
    token: {roles: ["operations_admin"]},
  }), true);
});

test("delivery evidence admin roles use established operations claims", () => {
  assert.equal(hasAdminClaim({role: "operations_admin"}), true);
  assert.equal(hasAdminClaim({adminRole: "driver_manager"}), true);
  assert.equal(hasAdminClaim({roles: ["support_agent"]}), true);
  assert.equal(hasAdminClaim({role: "rider"}), false);
});
