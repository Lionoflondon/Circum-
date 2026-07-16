"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const briefEngine = require("./gift-brief-engine");

test("GiftBriefEngine generates a structured IRIS Gift Brief", () => {
  const update = briefEngine.giftBriefUpdate({
    recipientName: "Ayo",
    relationship: "Partner",
    occasion: "Anniversary",
    notes: "Loves fragrance, slow weekends and handwritten notes.",
    personalMessage: "You make ordinary days feel special.",
    interests: ["Fashion", "Fragrance"],
    favouriteColours: "sage green",
    likedBrands: "Aesop",
    deliveryAddress: "Marylebone",
    deliveryDate: "2026-07-12",
    senderRevealMode: "reveal_after_delivery",
  }, {giftRequestId: "gift-1", generatedAt: "2026-07-07T00:00:00.000Z"});

  assert.equal(update.irisGiftBriefStatus, "complete");
  assert.equal(update.giftBrief.generatedBy, "IRIS");
  assert.equal(update.giftBrief.schemaVersion, briefEngine.SCHEMA_VERSION);
  assert.equal(update.giftBrief.relationship, "Partner");
  assert.equal(update.giftBrief.occasion, "Anniversary");
  assert.deepEqual(update.giftBrief.giftSignals, ["fashionInterest", "fragranceInterest"]);
  assert.equal(update.giftBrief.brandSummary, "Aesop");
  assert.equal(update.giftBrief.colourSummary, "sage green");
  assert.equal(update.giftBrief.manualReviewRequired, false);
});

test("GiftBriefEngine keeps unsupported custom interests pending", () => {
  const brief = briefEngine.buildGiftBrief({
    recipientName: "Tasha",
    relationship: "Friend",
    occasion: "Birthday",
    notes: "Enjoys handmade ceramics.",
    interests: ["Ceramics"],
    customInterest: "Botanical workshops",
    deliveryAddress: "Chelsea",
    deliveryDate: "2026-07-12",
  }, {giftRequestId: "gift-2", generatedAt: "2026-07-07T00:00:00.000Z"});

  assert.deepEqual(brief.giftSignals, []);
  assert.equal(brief.manualReviewRequired, true);
  assert.deepEqual(
    brief.pendingInterests.map((item) => item.status),
    ["pending", "pending"],
  );
  assert.deepEqual(
    brief.pendingInterests.map((item) => item.interest),
    ["Botanical workshops", "Ceramics"],
  );
});

test("GiftBriefEngine only maps canonical supported IRIS gift signals", () => {
  assert.deepEqual(
    briefEngine.senderGiftIrisSignalsForThemes(["Beauty", "Makeup", "Gaming"]),
    ["beautyInterest"],
  );
});
