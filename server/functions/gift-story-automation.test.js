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

test("Gift Story slides cap at 16 and always keep final thank-you slide", () => {
  const items = Array.from({length: 12}, (_, index) => ({
    name: `Gift ${index + 1}`,
    why: `Reason ${index + 1}`,
  }));
  const slides = story.buildGiftStorySlides({
    recipientName: "Ada",
    personalMessage: "For you",
    giftItems: items,
  });
  assert.equal(slides.length, 16);
  assert.equal(slides[0].headline, "Your gift has arrived, Ada.");
  assert.equal(slides.at(-1).type, "finale");
  assert.equal(slides.at(-1).headline, "Tell sender thank you");
});

test("Gift Story skins include safe fallback and storage paths are canonical", () => {
  assert.equal(story.cleanSkin("pink"), "pink");
  assert.equal(story.cleanSkin("blue"), "blue");
  assert.equal(story.cleanSkin("classic-dark"), "classic_dark");
  assert.equal(story.cleanSkin("unknown"), "iridescent");
  assert.deepEqual(story.giftStoryStoragePaths("gift-1"), {
    source: "gifts/gift-1/story/source/",
    silent: "gifts/gift-1/story/exports/silent/",
    sound: "gifts/gift-1/story/exports/sound/",
    thumbs: "gifts/gift-1/story/thumbs/",
  });
});

test("Gift Story notification records support email primary and WhatsApp fallback", () => {
  const email = story.storyNotificationRecord({
    notificationId: "n-email",
    giftStoryId: "gift-1",
    email: "recipient@example.com",
    phone: "+447700900000",
    channel: "email",
    status: "queued",
    priority: 1,
    secureStoryUrl: "https://circumuk.com/story/token",
  });
  const whatsapp = story.storyNotificationRecord({
    notificationId: "n-whatsapp",
    giftStoryId: "gift-1",
    phone: "+447700900000",
    channel: "whatsapp",
    status: "queued",
    priority: 2,
    failedReason: "email_failed",
    secureStoryUrl: "https://circumuk.com/story/token",
  });
  assert.equal(email.channel, "email");
  assert.equal(email.priority, 1);
  assert.equal(whatsapp.channel, "whatsapp");
  assert.equal(whatsapp.priority, 2);
  assert.equal(whatsapp.failedReason, "email_failed");
});

test("recipient web story renders final app CTA and avoids private fields", () => {
  const html = story.renderGiftStoryHtml({
    token: "secure-token",
    giftId: "gift-1",
    role: "recipient",
    gift: {
      giftStorySkin: "blue",
      recipientName: "Ada",
      senderName: "Private Sender",
      senderRevealMode: "anonymous_forever",
      budget: 1500,
      deliveryAddress: "Secret",
      giftItems: [{name: "Candle", why: "It felt calm."}],
    },
  });
  assert.match(html, /Your gift has arrived, Ada\./);
  assert.match(html, /Keep this story in the Circum app/);
  assert.match(html, /Tell sender thank you/);
  assert.doesNotMatch(html, /1500/);
  assert.doesNotMatch(html, /Secret/);
  assert.doesNotMatch(html, /Private Sender/);
});
