/* eslint-disable max-len, indent */
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

test("Gift Story action IDs are deterministic for idempotent writes", () => {
  assert.deepEqual(story.giftStoryActionIds("gift-1", "recipient-1"), {
    thankYou: "gift-1_recipient_thank_you",
    thankYouAudit: "gift_story_thank_you_gift-1",
    thankYouNotification: "gift_thank_you_gift-1",
    vault: "recipient-1_gift-1",
    vaultAudit: "gift_story_saved_gift-1_recipient-1",
  });
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

test("safe story payload includes sender voice-note playback metadata", () => {
  const safe = story.safeStory("gift-voice", {
    voiceNote: {
      hasVoiceNote: true,
      downloadUrl: "https://storage.example/voice.webm",
      durationSeconds: 12,
      mimeType: "audio/webm",
      createdAt: "2026-07-13T09:00:00.000Z",
      storagePath: "gift_requests/sender_123/voice/original.webm",
    },
  });
  assert.deepEqual(safe.voiceNote, {
    hasVoiceNote: true,
    downloadUrl: "https://storage.example/voice.webm",
    durationSeconds: 12,
    mimeType: "audio/webm",
    createdAt: "2026-07-13T09:00:00.000Z",
  });
  assert.equal(
    safe.giftStorySenderVoiceNoteUrl,
    "https://storage.example/voice.webm",
  );
  assert.equal(Object.hasOwn(safe.voiceNote, "storagePath"), false);
});

test("Gift Story slides never use raw voice Storage paths as playback URLs", () => {
  const slides = story.buildGiftStorySlides({
    recipientName: "Ada",
    voiceNote: {
      storagePath: "gift_requests/sender_123/voice/original.webm",
      durationSeconds: 9,
      mimeType: "audio/webm",
    },
  });
  assert.equal(slides.some((slide) => slide.type === "voice_note"), false);
  assert.equal(
      slides.some((slide) => `${slide.mediaUrl || ""}`.includes("gift_requests/")),
      false,
  );
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

test("Gift Story notification records support sender app plus recipient email, WhatsApp, and iMessage delivery", () => {
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
  const imessage = story.storyNotificationRecord({
    notificationId: "n-imessage",
    giftStoryId: "gift-1",
    phone: "+447700900000",
    channel: "imessage",
    status: "queued",
    priority: 2,
    failedReason: "email_failed",
    secureStoryUrl: "https://circumuk.com/story/token",
  });
  const senderApp = story.storyNotificationRecord({
    notificationId: "n-sender-app",
    giftStoryId: "gift-1",
    userId: "sender-1",
    channel: "sender_app",
    status: "queued",
    priority: 1,
    secureStoryUrl: "https://circumuk.com/story/token",
  });
  assert.equal(email.channel, "email");
  assert.equal(email.priority, 1);
  assert.equal(whatsapp.channel, "whatsapp");
  assert.equal(whatsapp.priority, 2);
  assert.equal(whatsapp.failedReason, "email_failed");
  assert.equal(imessage.channel, "imessage");
  assert.equal(imessage.priority, 2);
  assert.equal(imessage.failedReason, "email_failed");
  assert.equal(senderApp.channel, "sender_app");
  assert.equal(senderApp.priority, 1);
});

test("Gift Story selects one recipient phone channel instead of duplicating WhatsApp and iMessage", () => {
  assert.equal(story.chooseRecipientLinkChannel({
    recipientAvailableMessagingChannels: ["whatsapp"],
  }), "whatsapp");
  assert.equal(story.chooseRecipientLinkChannel({
    recipientAvailableMessagingChannels: ["imessage"],
  }), "imessage");
  assert.equal(story.chooseRecipientLinkChannel({
    recipientAvailableMessagingChannels: ["whatsapp", "imessage"],
  }), "whatsapp");
  assert.equal(story.chooseRecipientLinkChannel({
    recipientAvailableMessagingChannels: ["whatsapp", "imessage"],
    recipientPreferredMessagingChannel: "imessage",
  }), "imessage");
  const source = require("node:fs").readFileSync(
      require("node:path").join(__dirname, "gift-story-automation.js"),
      "utf8",
  );
  assert.match(source, /imessageQueue/);
  assert.match(source, /normalizedChannel === "imessage"/);
  assert.match(source, /channel: normalizedChannel/);
  assert.match(source, /chooseRecipientLinkChannel/);
  assert.match(source, /const queue = normalizedChannel === "imessage" \? "imessageQueue" : "whatsappQueue"/);
  assert.match(source, /queueSenderStoryAppNotification/);
  assert.match(source, /channel: "sender_app"/);
  assert.match(source, /storyNotificationId\(giftId, "sender_app"/);
  assert.doesNotMatch(source, /role: "recipient", userId: text\(gift\.recipientUserId\)/);
  assert.doesNotMatch(source, /whatsappQueue[\s\S]*imessageQueue[\s\S]*return null;\n}\);/);
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

test("recipient web story lets non-members view and prompts Circum join as an enhancement", () => {
  const html = story.renderGiftStoryHtml({
    token: "secure-token",
    giftId: "gift-1",
    role: "recipient",
    gift: {
      recipientName: "Ada",
      recipientUserId: "",
      giftItems: [{name: "Candle", why: "It felt calm."}],
    },
  });
  assert.match(html, /Your Gift Story is ready\./);
  assert.match(html, /Save this Gift Story forever in your Vault/i);
  assert.match(html, /Join Circum/);
  assert.match(html, /Maybe later/);
  assert.doesNotMatch(html, /Join Circum to see video/);
  assert.doesNotMatch(html, /Join Circum to see the video version/);
});

test("recipient web story does not prompt linked Circum recipients to join", () => {
  const html = story.renderGiftStoryHtml({
    token: "secure-token",
    giftId: "gift-1",
    role: "recipient",
    gift: {
      recipientName: "Ada",
      recipientUserId: "recipient-1",
      giftItems: [{name: "Candle", why: "It felt calm."}],
    },
  });
  assert.doesNotMatch(html, /Your Gift Story is ready\./);
});

test("recipient token-only video download remains available while ownership actions require account", () => {
  const source = require("node:fs").readFileSync(
      require("node:path").join(__dirname, "gift-story-automation.js"),
      "utf8",
  );
  assert.doesNotMatch(source, /Join Circum to see this Gift Story video/);
  assert.match(source, /participantAuthorized\(context, gift, suppliedToken\)/);
  assert.match(source, /exports\.acknowledgeGiftStory[\s\S]*requireAccount: true/);
  assert.match(source, /exports\.saveGiftStoryToVault[\s\S]*requireAccount: true/);
  assert.match(source, /recordGiftStoryGuestAnalytics\(db, \{[\s\S]*event: "guest_watched_video"/);
});

test("Gift Story guest analytics records viewing, video, join, registration, and claim events", () => {
  const source = require("node:fs").readFileSync(
      require("node:path").join(__dirname, "gift-story-automation.js"),
      "utf8",
  );
  assert.match(source, /recordGiftStoryGuestEvent/);
  assert.match(source, /guest_viewed_story/);
  assert.match(source, /guest_watched_video/);
  assert.match(source, /guest_completed_video/);
  assert.match(source, /guest_clicked_join_circum/);
  assert.match(source, /guest_registered/);
  assert.match(source, /guest_claimed_gift_story/);
  assert.match(source, /source: "gift_story_guest_access"/);
});

test("recipient web story renders sender voice note as playable audio", () => {
  const html = story.renderGiftStoryHtml({
    token: "secure-token",
    giftId: "gift-1",
    role: "recipient",
    gift: {
      recipientName: "Ada",
      voiceNote: {
        downloadUrl: "https://storage.example/voice.webm",
        durationSeconds: 9,
        mimeType: "audio/webm",
      },
    },
  });
  assert.match(html, /type":"voice_note"/);
  assert.match(html, /<audio class="voice" controls preload="metadata"/);
  assert.match(html, /https:\/\/storage\.example\/voice\.webm/);
});

test("Gift Story lifecycle revokes and extends sender and recipient tokens", () => {
  const source = require("node:fs").readFileSync(
      require("node:path").join(__dirname, "gift-story-automation.js"),
      "utf8",
  );
  assert.match(source, /recipientStoryTokenHash/);
  assert.match(source, /tokenHashes/);
  assert.match(source, /status: "revoked"/);
  assert.match(source, /expiresAt, status: "active"/);
});

test("Gift Story cleanup removes every rendered video path and recipient token field", () => {
  const story = require("./gift-story-automation");
  assert.deepEqual(story.giftStoryVideoPaths({
    giftStoryRenderedVideoPath: "gifts/gift-1/story/exports/sound/current.webm",
    giftStorySilentVersionUrl: "gifts/gift-1/story/exports/silent/current.webm",
    giftStorySoundVersionUrl: "gifts/gift-1/story/exports/sound/current.webm",
    unsafeUrl: "https://storage.example/gifts/gift-1/story/exports/sound/current.webm",
  }, "gift-1"), [
    "gifts/gift-1/story/exports/sound/current.webm",
    "gifts/gift-1/story/exports/silent/current.webm",
  ]);

  const source = require("node:fs").readFileSync(
      require("node:path").join(__dirname, "gift-story-automation.js"),
      "utf8",
  );
  assert.match(source, /giftStorySilentVersionUrl: FieldValue\.delete\(\)/);
  assert.match(source, /giftStorySoundVersionUrl: FieldValue\.delete\(\)/);
  assert.match(source, /recipientStoryToken: FieldValue\.delete\(\)/);
  assert.match(source, /recipientStoryTokenHash: FieldValue\.delete\(\)/);
  assert.match(source, /recipientStoryUrl: FieldValue\.delete\(\)/);
});

test("Gift Story landing blocks disabled and unapproved stories", () => {
  const source = require("node:fs").readFileSync(
      require("node:path").join(__dirname, "gift-story-automation.js"),
      "utf8",
  );
  assert.match(source, /gift\.giftStoryEnabled === false/);
  assert.match(source, /gift\.giftStoryApproved === false/);
});

test("Gift Story thank-you message is preserved and requires a Circum account", () => {
  const source = require("node:fs").readFileSync(
      require("node:path").join(__dirname, "gift-story-automation.js"),
      "utf8",
  );
  assert.match(source, /thankYouMessage/);
  assert.match(source, /giftStoryThankYouMessage/);
  assert.match(source, /account_required/);
  assert.match(source, /Sign in to keep this Gift Story/);
});
