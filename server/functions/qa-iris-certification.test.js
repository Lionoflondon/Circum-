const {test} = require("node:test");
const assert = require("node:assert/strict");
const {SCENARIOS, syntheticParcelPng, analyse} = require("./qa-iris-certification");

test("IRIS QA scenarios are fixed, synthetic and customer-safe", () => {
  for (const scenario of Object.keys(SCENARIOS)) {
    const result = analyse({uid: "qa_sender", scenario});
    assert.equal(result.scenario, scenario);
    assert.ok(result.iris);
    assert.equal(JSON.stringify(result).includes("privateReason"), false);
  }
  assert.throws(() => analyse({uid: "qa_sender", scenario: "user_supplied"}), /Unsupported synthetic/);
  assert.equal(analyse({uid: "qa_sender", scenario: "weed"}).iris.compliance.status, "prohibited");
  assert.equal(analyse({uid: "qa_sender", scenario: "pets"}).iris.compliance.status, "referral_required");
  assert.equal(analyse({uid: "qa_sender", scenario: "remains"}).iris.compliance.status, "referral_required");
  assert.ok(analyse({uid: "qa_sender", scenario: "weed"}).iris.compliance.customerMessage);
});

test("the QA parcel photo is a valid fixed PNG and analysis is replay-stable", () => {
  const bytes = syntheticParcelPng();
  assert.ok(bytes.length >= 128);
  assert.equal(bytes.subarray(0, 8).toString("hex"), "89504e470d0a1a0a");
  assert.equal(bytes.readUInt32BE(16), 128);
  assert.equal(bytes.readUInt32BE(20), 128);
  const first = analyse({uid: "qa_sender", scenario: "photo"});
  const replay = analyse({uid: "qa_sender", scenario: "photo"});
  assert.equal(first.photo.analysisId, replay.photo.analysisId);
  assert.equal(first.photo.userId, "qa_sender");
  assert.equal(first.photo.source, "backend_parcel_photo_analysis");
  assert.ok(first.photo.estimatedWeightKg > 0);
});
