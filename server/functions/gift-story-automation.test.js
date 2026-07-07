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

const consentedA = {
  userId: "user-a",
  displayName: "Alex",
  profilePhotoUrl: "https://example.com/a.jpg",
  revealConsent: true,
  interests: ["coffee", "travel"],
  email: "private@example.com",
  allergies: ["nuts"],
};

const consentedB = {
  userId: "user-b",
  displayName: "Bailey",
  profilePhotoUrl: "https://example.com/b.jpg",
  revealConsent: true,
  interests: ["coffee", "architecture"],
  phone: "+440000",
  medicalRestrictions: "private",
};

test("campaign revealed match is blocked before Story unlock", () => {
  const decision = story.campaignRevealMatchDecision({
    gift: {
      giftStoryStatus: "locked",
      storyViewedBy: ["user-a", "user-b"],
      revealPolicy: "mutual_consent",
    },
    participantA: consentedA,
    participantB: consentedB,
  });
  assert.equal(decision.create, false);
  assert.equal(decision.reason, "story_locked");
});

test("campaign revealed match is blocked before Story is viewed", () => {
  const decision = story.campaignRevealMatchDecision({
    gift: {
      giftStoryStatus: "unlocked",
      storyViewedBy: ["user-a"],
      revealPolicy: "mutual_consent",
    },
    participantA: consentedA,
    participantB: consentedB,
  });
  assert.equal(decision.create, false);
  assert.equal(decision.reason, "story_not_viewed");
});

test("campaign revealed match is blocked with one-sided consent", () => {
  const decision = story.campaignRevealMatchDecision({
    gift: {
      giftStoryStatus: "unlocked",
      storyViewedBy: ["user-a", "user-b"],
      revealPolicy: "mutual_consent",
    },
    participantA: consentedA,
    participantB: {...consentedB, revealConsent: false},
  });
  assert.equal(decision.create, false);
  assert.equal(decision.reason, "waiting_for_mutual_reveal_consent");
});

test("campaign revealed match is created only after mutual consent and Story views", () => {
  const decision = story.campaignRevealMatchDecision({
    gift: {
      giftStoryStatus: "unlocked",
      storyViewedBy: ["user-a", "user-b"],
      revealPolicy: "mutual_consent",
    },
    participantA: consentedA,
    participantB: consentedB,
  });
  assert.equal(decision.create, true);
});

test("campaign revealed match record excludes private fields", () => {
  const record = story.buildRevealedCampaignMatchRecord({
    matchId: "match-1",
    giftStoryId: "gift-1",
    gift: {
      id: "gift-1",
      campaignId: "campaign-1",
      sharedInterests: ["coffee"],
      budget: 1500,
      paymentMethod: "card",
      deliveryAddress: "private",
      privateAdminNotes: "private",
    },
    participantA: consentedA,
    participantB: consentedB,
    now: "now",
  });
  assert.equal(record.matchId, "match-1");
  assert.equal(record.status, "revealed");
  assert.equal(record.source, "gift_campaign");
  assert.deepEqual(record.sharedInterests, ["coffee"]);
  assert.equal(record.participantAUserId, "user-a");
  assert.equal(record.participantBUserId, "user-b");
  assert.equal(Object.hasOwn(record, "email"), false);
  assert.equal(Object.hasOwn(record, "phone"), false);
  assert.equal(Object.hasOwn(record, "budget"), false);
  assert.equal(Object.hasOwn(record, "paymentMethod"), false);
  assert.equal(Object.hasOwn(record, "deliveryAddress"), false);
  assert.equal(Object.hasOwn(record, "allergies"), false);
  assert.equal(Object.hasOwn(record, "medicalRestrictions"), false);
  assert.equal(Object.hasOwn(record, "privateAdminNotes"), false);
});

test("active dispute prevents campaign revealed match creation", () => {
  const decision = story.campaignRevealMatchDecision({
    gift: {
      giftStoryStatus: "unlocked",
      storyViewedBy: ["user-a", "user-b"],
      revealPolicy: "mutual_consent",
      activeDispute: true,
    },
    participantA: consentedA,
    participantB: consentedB,
  });
  assert.equal(decision.create, false);
  assert.equal(decision.reason, "active_dispute");
});
