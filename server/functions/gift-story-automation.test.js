"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const story = require("./gift-story-automation");

test("Gift Story automation only targets Gifts deliveries", () => {
  assert.equal(story.isGiftDelivery({serviceType: "GIFTS"}), true);
  assert.equal(story.isGiftDelivery({sourceModule: "gifts"}), true);
  assert.equal(story.isGiftDelivery({serviceType: "STANDARD"}), false);
  assert.equal(story.isGiftDelivery({serviceType: "HEALTH_PLUS"}), false);
});

test("Gift Story unlock only accepts final delivery states", () => {
  assert.equal(story.isComplete("completed"), true);
  assert.equal(story.isComplete("delivered"), true);
  assert.equal(story.isComplete("in_transit"), false);
});

test("secure story token hashes are deterministic and opaque", () => {
  const hash = story.tokenHash("private-token");
  assert.equal(hash, story.tokenHash("private-token"));
  assert.notEqual(hash, "private-token");
  assert.equal(hash.length, 64);
});

test("safe story payload excludes private operational fields", () => {
  const safe = story.safeStory("gift-1", {
    occasion: "Birthday",
    recipientName: "Tasha",
    internalNotes: "private",
    deliveryAddress: "private address",
    procurementActualCost: 42,
    giftStoryPhotos: ["approved.jpg"],
  });
  assert.equal(safe.occasion, "Birthday");
  assert.deepEqual(safe.giftStoryPhotos, ["approved.jpg"]);
  assert.equal(Object.hasOwn(safe, "internalNotes"), false);
  assert.equal(Object.hasOwn(safe, "deliveryAddress"), false);
  assert.equal(Object.hasOwn(safe, "procurementActualCost"), false);
});
