/* eslint-disable max-len, require-jsdoc */
"use strict";

const crypto = require("crypto");
const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue, Timestamp} = require("firebase-admin/firestore");
const {getStorage} = require("firebase-admin/storage");

const STORY_RETENTION_HOURS = 48;
const COMPLETE_STATUSES = new Set(["completed", "complete", "delivered"]);

function text(value) {
  return `${value || ""}`.trim();
}

function normalizeEmail(value) {
  return text(value).toLowerCase();
}

function isComplete(value) {
  return COMPLETE_STATUSES.has(text(value).toLowerCase());
}

function isGiftDelivery(delivery) {
  return text(delivery.serviceType).toUpperCase() === "GIFTS" ||
    text(delivery.sourceModule).toLowerCase() === "gifts" ||
    Boolean(delivery.giftOrderId || delivery.giftRequestId);
}

function tokenHash(token) {
  return crypto.createHash("sha256").update(token).digest("hex");
}

function storyLink(token) {
  return `https://circumuk.com/story/${encodeURIComponent(token)}`;
}

function safeStory(giftId, gift) {
  return {
    id: giftId,
    giftStoryEnabled: true,
    giftStoryApproved: gift.giftStoryApproved !== false,
    giftStoryShareEnabled: gift.giftStoryShareEnabled !== false,
    giftStorySharePrivacy: gift.giftStorySharePrivacy || "private",
    giftStoryVideoStatus: gift.giftStoryVideoStatus || "processing",
    giftStoryVideoExpiresAt: gift.giftStoryVideoExpiresAt || null,
    giftStoryMusicEnabled: gift.giftStoryMusicEnabled === true,
    giftStoryCustomAudioUrl: gift.giftStoryCustomAudioUrl || null,
    giftStoryPhotos: Array.isArray(gift.giftStoryPhotos) ? gift.giftStoryPhotos : [],
    giftStoryPhotoUrls: Array.isArray(gift.giftStoryPhotoUrls) ? gift.giftStoryPhotoUrls : [],
    giftStoryCircumMessage: gift.giftStoryCircumMessage || "",
    senderMessageText: gift.senderMessageText || gift.personalMessage || "",
    personalMessage: gift.personalMessage || "",
    senderName: gift.senderName || "Someone special",
    recipientName: gift.recipientName || "Recipient",
    relationship: gift.relationship || "",
    occasion: gift.occasion || "A special moment",
    deliveryDate: gift.deliveryDate || gift.deliveredAt || null,
    deliveryTimeWindow: gift.deliveryTimeWindow || "Delivered",
    interestTags: Array.isArray(gift.interestTags) ? gift.interestTags : [],
    interests: Array.isArray(gift.interests) ? gift.interests : [],
    giftItemsSummary: gift.giftItemsSummary || gift.approvedRevealSummary || "",
    approvedGiftPhotoUrls: Array.isArray(gift.approvedGiftPhotoUrls) ? gift.approvedGiftPhotoUrls : [],
    status: "delivered",
    giftStatus: "delivered",
  };
}

function list(value) {
  return Array.isArray(value) ? value.map((item) => text(item)).filter(Boolean) : [];
}

function bool(value) {
  if (value === true) return true;
  if (value === false || value == null) return false;
  return ["true", "yes", "accepted", "consented", "allow", "allowed"].includes(text(value).toLowerCase());
}

function hasActiveGiftDispute(gift = {}) {
  return bool(gift.activeDispute) ||
    bool(gift.activeInvestigation) ||
    bool(gift.deliveryInvestigationActive) ||
    bool(gift.activeDeliveryDispute) ||
    bool(gift.hasActiveDeliveryDispute) ||
    bool(gift.disputeOpen) ||
    ["open", "active", "investigating", "under_review"].includes(text(gift.disputeStatus).toLowerCase()) ||
    ["open", "active", "investigating", "under_review"].includes(text(gift.investigationStatus).toLowerCase());
}

function revealPolicyAllowsMutualReveal(policy) {
  const clean = text(policy).toLowerCase();
  if (!clean || clean === "anonymous_only" || clean === "anonymous") return false;
  return [
    "mutual_consent",
    "anonymous_until_consent",
    "reveal_after_delivery",
    "reveal_immediately",
    "mutual-reveal",
  ].includes(clean);
}

function participantRevealConsent(participant = {}) {
  return bool(participant.revealConsent) ||
    bool(participant.identityRevealConsent) ||
    bool(participant.senderRevealConsent) ||
    bool(participant.matchRevealConsent);
}

function storyViewedByRequiredUsers(gift = {}, participantA = {}, participantB = {}) {
  const viewedBy = new Set([
    ...list(gift.storyViewedBy),
    ...list(gift.giftStoryViewedBy),
    ...list(gift.giftStoryViewedByUserIds),
  ]);
  const aUserId = text(participantA.userId || participantA.uid);
  const bUserId = text(participantB.userId || participantB.uid);
  if (aUserId && bUserId) return viewedBy.has(aUserId) && viewedBy.has(bUserId);
  return bool(gift.storyViewedByBothParticipants) || bool(gift.giftStoryViewedByBothParticipants);
}

function campaignRevealMatchDecision({gift = {}, participantA = {}, participantB = {}} = {}) {
  const storyStatus = text(gift.giftStoryStatus || gift.storyStatus || (gift.giftStoryUnlocked ? "unlocked" : "")).toLowerCase();
  if (storyStatus !== "unlocked") return {create: false, reason: "story_locked"};
  if (!storyViewedByRequiredUsers(gift, participantA, participantB)) return {create: false, reason: "story_not_viewed"};
  if (!participantRevealConsent(participantA) || !participantRevealConsent(participantB)) {
    return {create: false, reason: "waiting_for_mutual_reveal_consent"};
  }
  if (!revealPolicyAllowsMutualReveal(gift.revealPolicy || gift.senderRevealMode || participantA.revealPolicy || participantB.revealPolicy)) {
    return {create: false, reason: "reveal_policy_blocks"};
  }
  if (hasActiveGiftDispute(gift)) return {create: false, reason: "active_dispute"};
  return {create: true, reason: "eligible"};
}

function safeName(participant = {}) {
  return text(participant.displayName || participant.name || participant.anonymousHandle || "Campaign match");
}

function buildRevealedCampaignMatchRecord({matchId, giftStoryId, gift = {}, participantA = {}, participantB = {}, now = null} = {}) {
  const sharedInterests = list(gift.sharedInterests).length ?
    list(gift.sharedInterests) :
    [...new Set([...list(participantA.interests), ...list(participantB.interests)].filter((interest) => list(participantA.interests).includes(interest) && list(participantB.interests).includes(interest)))];
  return {
    matchId,
    campaignId: text(gift.campaignId || participantA.campaignId || participantB.campaignId),
    giftStoryId: text(giftStoryId || gift.giftStoryId || gift.id),
    participantAUserId: text(participantA.userId || participantA.uid),
    participantBUserId: text(participantB.userId || participantB.uid),
    participantAName: safeName(participantA),
    participantBName: safeName(participantB),
    participantAProfilePhotoUrl: text(participantA.profilePhotoUrl || participantA.photoUrl),
    participantBProfilePhotoUrl: text(participantB.profilePhotoUrl || participantB.photoUrl),
    sharedInterests,
    matchDate: now,
    revealConfirmedAt: now,
    storyViewedAt: now,
    createdAt: now,
    status: "revealed",
    source: "gift_campaign",
  };
}

async function maybeCreateRevealedCampaignMatch(db, giftRef, giftId, gift, viewerUserId = "") {
  if (text(gift.giftType) !== "campaign" && text(gift.anonymousGiftType) !== "campaign" && text(gift.source) !== "gift_campaign") {
    return {created: false, reason: "not_campaign"};
  }
  const viewedBy = new Set([...list(gift.storyViewedBy), ...list(gift.giftStoryViewedBy)]);
  if (viewerUserId) viewedBy.add(viewerUserId);
  const nextGift = {
    ...gift,
    id: giftId,
    storyViewedBy: [...viewedBy],
    giftStoryStatus: gift.giftStoryStatus || (gift.giftStoryUnlocked ? "unlocked" : ""),
  };
  const participantAId = text(gift.campaignParticipantId || gift.participantAId || gift.senderCampaignParticipantId);
  const participantBId = text(gift.linkedParticipantId || gift.participantBId || gift.matchedParticipantId || gift.recipientCampaignParticipantId);
  if (!participantAId || !participantBId) return {created: false, reason: "missing_participants"};
  const [aSnap, bSnap] = await Promise.all([
    db.collection("giftCampaignParticipants").doc(participantAId).get(),
    db.collection("giftCampaignParticipants").doc(participantBId).get(),
  ]);
  if (!aSnap.exists || !bSnap.exists) return {created: false, reason: "participant_not_found"};
  const participantA = {id: aSnap.id, ...(aSnap.data() || {})};
  const participantB = {id: bSnap.id, ...(bSnap.data() || {})};
  const decision = campaignRevealMatchDecision({gift: nextGift, participantA, participantB});
  if (!decision.create) {
    await giftRef.set({
      storyViewedBy: [...viewedBy],
      giftStoryViewedBy: [...viewedBy],
      visibleMatchStatus: decision.reason,
      giftStoryUpdatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    return {created: false, reason: decision.reason};
  }
  const matchId = text(gift.visibleMatchId || gift.matchId) || `${participantAId}_${participantBId}_${giftId}`;
  const now = FieldValue.serverTimestamp();
  const record = buildRevealedCampaignMatchRecord({
    matchId,
    giftStoryId: giftId,
    gift: nextGift,
    participantA,
    participantB,
    now,
  });
  const batch = db.batch();
  const matchRef = db.collection("matches").doc(matchId);
  batch.set(matchRef, record, {merge: true});
  for (const participant of [participantA, participantB]) {
    const userId = text(participant.userId || participant.uid);
    if (!userId) continue;
    batch.set(db.collection("users").doc(userId).collection("matches").doc(matchId), {
      matchId,
      campaignId: record.campaignId,
      giftStoryId: record.giftStoryId,
      status: "revealed",
      source: "gift_campaign",
      createdAt: now,
      revealConfirmedAt: now,
    }, {merge: true});
  }
  batch.set(giftRef, {
    storyViewedBy: [...viewedBy],
    giftStoryViewedBy: [...viewedBy],
    visibleMatchId: matchId,
    visibleMatchStatus: "revealed",
    visibleMatchRevealedAt: now,
    giftStoryUpdatedAt: now,
  }, {merge: true});
  batch.set(aSnap.ref, {visibleMatchId: matchId, visibleMatchStatus: "revealed", updatedAt: now}, {merge: true});
  batch.set(bSnap.ref, {visibleMatchId: matchId, visibleMatchStatus: "revealed", updatedAt: now}, {merge: true});
  await batch.commit();
  return {created: true, matchId};
}

async function findGift(db, delivery) {
  const directId = text(delivery.giftOrderId || delivery.giftRequestId);
  if (directId) {
    const direct = await db.collection("giftRequests").doc(directId).get();
    if (direct.exists) return direct;
  }
  const deliveryId = text(delivery.deliveryId || delivery.requestId || delivery.id);
  if (!deliveryId) return null;
  const query = await db.collection("giftRequests").where("deliveryId", "==", deliveryId).limit(1).get();
  return query.empty ? null : query.docs[0];
}

async function queueStoryEmail(db, {giftId, role, email, token, retryId = ""}) {
  if (!email || !email.includes("@")) return false;
  const sender = role === "sender";
  const suffix = retryId ? `_${retryId}` : "";
  const ref = db.collection("emailQueue").doc(`gift_story_${giftId}_${role}${suffix}`);
  await ref.set({
    to: email,
    subject: sender ? "Your Circum Gift Story is ready" : "You have received a Circum Gift Story",
    body: sender ?
      `Hello,\n\nYour Circum Gift Story is ready.\n\nWatch your story:\n${storyLink(token)}\n\nThoughtful gifting, delivered by Circum.\n\n— Circum` :
      `Hello,\n\nYou have received a Circum Gift Story.\n\nWatch your story:\n${storyLink(token)}\n\nThoughtful gifting, delivered by Circum.\n\n— Circum`,
    type: "gift_story_ready",
    recipientRole: role,
    giftRequestId: giftId,
    status: "queued",
    attempts: FieldValue.increment(1),
    updatedAt: FieldValue.serverTimestamp(),
    createdAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  return true;
}

async function unlockGiftStory(db, giftSnap, deliveryId, {forceNewToken = false, retryEmails = false} = {}) {
  const giftId = giftSnap.id;
  const gift = giftSnap.data() || {};
  const existingToken = text(gift.giftStoryAccessToken);
  const token = !forceNewToken && existingToken ? existingToken : crypto.randomBytes(32).toString("base64url");
  const hash = tokenHash(token);
  const expiresAt = Timestamp.fromMillis(Date.now() + STORY_RETENTION_HOURS * 60 * 60 * 1000);
  const tokenRef = db.collection("giftStoryAccessTokens").doc(hash);
  const giftRef = giftSnap.ref;
  await db.runTransaction(async (transaction) => {
    transaction.set(tokenRef, {
      giftRequestId: giftId,
      deliveryId,
      tokenHash: hash,
      status: "active",
      privacy: gift.giftStorySharePrivacy || "private",
      expiresAt,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      views: gift.giftStoryViews || 0,
      shares: gift.giftStoryShares || 0,
      downloads: gift.giftStoryDownloads || 0,
      videoPlays: gift.giftStoryVideoPlays || 0,
      completedViews: gift.giftStoryCompletedViews || 0,
    }, {merge: true});
    transaction.set(giftRef, {
      status: "delivered",
      giftStatus: "delivered",
      deliveryId,
      giftStoryEnabled: true,
      giftStoryUnlocked: true,
      giftStoryAccessToken: token,
      giftStoryAccessTokenHash: hash,
      giftStoryAccessExpiresAt: expiresAt,
      giftStoryVideoStatus: gift.giftStoryRenderedVideoPath ? "ready" : "processing",
      giftStoryAutomationStatus: "ready",
      giftStoryAutomationError: FieldValue.delete(),
      giftStoryAvailableAt: FieldValue.serverTimestamp(),
      giftStoryUpdatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  });
  const senderEmail = normalizeEmail(gift.senderEmail);
  const recipientEmail = normalizeEmail(gift.recipientEmail || gift.recipientContact);
  const retryId = retryEmails ? `${Date.now()}` : "";
  const emailResults = await Promise.allSettled([
    queueStoryEmail(db, {giftId, role: "sender", email: senderEmail, token, retryId}),
    queueStoryEmail(db, {giftId, role: "recipient", email: recipientEmail, token, retryId}),
  ]);
  const failures = emailResults.filter((result) => result.status === "rejected");
  if (failures.length) {
    await giftRef.set({
      giftStoryEmailStatus: "retry_required",
      giftStoryEmailError: failures.map((result) => `${result.reason}`).join(" | ").slice(0, 1000),
      giftStoryUpdatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  } else {
    await giftRef.set({
      giftStoryEmailStatus: "queued",
      giftStoryEmailError: FieldValue.delete(),
      giftStoryUpdatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  }
  return {giftId, token, expiresAt};
}

async function markAutomationFailure(db, deliveryId, giftId, error) {
  const message = `${error && error.message ? error.message : error}`.slice(0, 1200);
  console.error("Gift Story automation failed", {deliveryId, giftId, message});
  const batch = db.batch();
  batch.set(db.collection("deliveryRequests").doc(deliveryId), {
    giftStoryAutomationStatus: "retry_required",
    giftStoryAutomationError: message,
    giftStoryAutomationUpdatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  if (giftId) {
    batch.set(db.collection("giftRequests").doc(giftId), {
      giftStoryAutomationStatus: "retry_required",
      giftStoryAutomationError: message,
      giftStoryUpdatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  }
  await batch.commit();
}

exports.onGiftDeliveryCompleted = functions.firestore.document("deliveryRequests/{deliveryId}").onUpdate(async (change, context) => {
  const before = change.before.data() || {};
  const after = change.after.data() || {};
  if (!isGiftDelivery(after) || isComplete(before.status) || !isComplete(after.status)) return null;
  const db = getFirestore();
  let giftSnap = null;
  try {
    giftSnap = await findGift(db, {...after, id: context.params.deliveryId});
    if (!giftSnap) throw new Error("Linked gift request was not found.");
    await unlockGiftStory(db, giftSnap, context.params.deliveryId);
    await change.after.ref.set({
      giftStoryAutomationStatus: "ready",
      giftStoryAutomationUpdatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  } catch (error) {
    await markAutomationFailure(db, context.params.deliveryId, giftSnap && giftSnap.id, error);
  }
  return null;
});

async function tokenRecord(db, token) {
  const clean = text(token);
  if (!clean) return null;
  const snap = await db.collection("giftStoryAccessTokens").doc(tokenHash(clean)).get();
  if (!snap.exists) return null;
  const data = snap.data() || {};
  const expiry = data.expiresAt && data.expiresAt.toMillis ? data.expiresAt.toMillis() : 0;
  if (data.status !== "active" || !expiry || expiry <= Date.now()) return null;
  return {snap, data};
}

exports.resolveGiftStoryAccess = functions.https.onCall(async (data, context) => {
  const db = getFirestore();
  const record = await tokenRecord(db, data && data.token);
  if (!record) throw new functions.https.HttpsError("permission-denied", "This Gift Story link is invalid or expired.");
  const giftSnap = await db.collection("giftRequests").doc(record.data.giftRequestId).get();
  if (!giftSnap.exists) throw new functions.https.HttpsError("not-found", "Gift Story not found.");
  const gift = giftSnap.data() || {};
  if (!isComplete(gift.giftStatus || gift.status) || gift.giftStoryEnabled === false || gift.giftStoryApproved === false) {
    throw new functions.https.HttpsError("failed-precondition", "This Gift Story is not available yet.");
  }
  const viewerUserId = context.auth && context.auth.uid ? context.auth.uid : text(data && data.viewerUserId);
  await record.snap.ref.set({views: FieldValue.increment(1), lastViewedAt: FieldValue.serverTimestamp()}, {merge: true});
  const storyViewPatch = {
    giftStoryViews: FieldValue.increment(1),
    giftStoryUpdatedAt: FieldValue.serverTimestamp(),
  };
  if (viewerUserId) {
    storyViewPatch.storyViewedBy = FieldValue.arrayUnion(viewerUserId);
    storyViewPatch.giftStoryViewedBy = FieldValue.arrayUnion(viewerUserId);
  }
  await giftSnap.ref.set(storyViewPatch, {merge: true});
  await maybeCreateRevealedCampaignMatch(db, giftSnap.ref, giftSnap.id, gift, viewerUserId);
  return {story: safeStory(giftSnap.id, gift), expiresAt: record.data.expiresAt.toMillis()};
});

exports.recordGiftStoryEvent = functions.https.onCall(async (data, context) => {
  const db = getFirestore();
  const record = await tokenRecord(db, data && data.token);
  if (!record) throw new functions.https.HttpsError("permission-denied", "Gift Story access expired.");
  const event = text(data.event);
  const fields = {
    view: "views",
    play: "videoPlays",
    complete: "completedViews",
    download: "downloads",
    share: "shares",
  };
  const field = fields[event];
  if (!field) throw new functions.https.HttpsError("invalid-argument", "Unknown Gift Story event.");
  const viewerUserId = context.auth && context.auth.uid ? context.auth.uid : text(data && data.viewerUserId);
  const giftRef = db.collection("giftRequests").doc(record.data.giftRequestId);
  const giftPatch = {
    [`giftStory${field[0].toUpperCase()}${field.slice(1)}`]: FieldValue.increment(1),
    giftStoryUpdatedAt: FieldValue.serverTimestamp(),
  };
  if (event === "view" && viewerUserId) {
    giftPatch.storyViewedBy = FieldValue.arrayUnion(viewerUserId);
    giftPatch.giftStoryViewedBy = FieldValue.arrayUnion(viewerUserId);
  }
  await Promise.all([
    record.snap.ref.set({[field]: FieldValue.increment(1), updatedAt: FieldValue.serverTimestamp()}, {merge: true}),
    giftRef.set(giftPatch, {merge: true}),
  ]);
  if (event === "view" || event === "complete") {
    const giftSnap = await giftRef.get();
    if (giftSnap.exists) {
      await maybeCreateRevealedCampaignMatch(db, giftRef, giftSnap.id, giftSnap.data() || {}, viewerUserId);
    }
  }
  return {ok: true};
});

exports.updateGiftStoryPrivacy = functions.https.onCall(async (data, context) => {
  const db = getFirestore();
  const giftId = text(data.giftRequestId);
  const privacy = text(data.privacy).toLowerCase();
  if (!["private", "unlisted", "public"].includes(privacy)) throw new functions.https.HttpsError("invalid-argument", "Invalid Gift Story privacy.");
  const giftRef = db.collection("giftRequests").doc(giftId);
  const giftSnap = await giftRef.get();
  if (!giftSnap.exists) throw new functions.https.HttpsError("not-found", "Gift Story not found.");
  const gift = {...(giftSnap.data() || {}), id: giftId};
  if (!await participantAuthorized(context, gift, text(data.token))) throw new functions.https.HttpsError("permission-denied", "Gift Story access required.");
  await giftRef.set({giftStorySharePrivacy: privacy, giftStoryShareEnabled: privacy !== "private", giftStoryUpdatedAt: FieldValue.serverTimestamp()}, {merge: true});
  const hash = text(gift.giftStoryAccessTokenHash);
  if (hash) await db.collection("giftStoryAccessTokens").doc(hash).set({privacy, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
  return {ok: true, privacy};
});

async function adminAuthorized(context) {
  if (!context.auth) return false;
  const roles = Array.isArray(context.auth.token.roles) ? context.auth.token.roles : [];
  if (roles.some((role) => ["admin", "super_admin", "gifts_admin", "operations_admin"].includes(role))) return true;
  const snap = await getFirestore().collection("adminUsers").doc(context.auth.uid).get();
  const role = snap.exists ? text(snap.data().role) : "";
  return ["admin", "super_admin", "gifts_admin", "operations_admin"].includes(role);
}

async function participantAuthorized(context, gift, suppliedToken) {
  if (await adminAuthorized(context)) return true;
  if (context.auth) {
    const uid = context.auth.uid;
    const email = normalizeEmail(context.auth.token.email);
    if (uid && [gift.senderId, gift.userId, gift.customerId].includes(uid)) return true;
    if (email && [normalizeEmail(gift.senderEmail), normalizeEmail(gift.recipientEmail || gift.recipientContact)].includes(email)) return true;
  }
  if (suppliedToken) {
    const record = await tokenRecord(getFirestore(), suppliedToken);
    return Boolean(record && record.data.giftRequestId === gift.id);
  }
  return false;
}

exports.createGiftStoryVideoUpload = functions.https.onCall(async (data, context) => {
  const db = getFirestore();
  const giftId = text(data.giftRequestId);
  const giftSnap = await db.collection("giftRequests").doc(giftId).get();
  if (!giftSnap.exists) throw new functions.https.HttpsError("not-found", "Gift Story not found.");
  const gift = {...(giftSnap.data() || {}), id: giftId};
  if (!isComplete(gift.giftStatus || gift.status)) throw new functions.https.HttpsError("failed-precondition", "Gift Story is not unlocked.");
  if (!await participantAuthorized(context, gift, text(data.token))) throw new functions.https.HttpsError("permission-denied", "Gift Story access required.");
  const extension = text(data.extension).toLowerCase() === "mp4" ? "mp4" : "webm";
  const mime = extension === "mp4" ? "video/mp4" : "video/webm";
  const nonce = crypto.randomBytes(12).toString("hex");
  const storagePath = `gift_story_renders/${giftId}/${Date.now()}_${nonce}.${extension}`;
  const file = getStorage().bucket().file(storagePath);
  const [uploadUrl] = await file.getSignedUrl({
    version: "v4",
    action: "write",
    expires: Date.now() + 15 * 60 * 1000,
    contentType: mime,
  });
  return {uploadUrl, storagePath, mime};
});

exports.finalizeGiftStoryVideoUpload = functions.https.onCall(async (data, context) => {
  const db = getFirestore();
  const giftId = text(data.giftRequestId);
  const giftRef = db.collection("giftRequests").doc(giftId);
  const giftSnap = await giftRef.get();
  if (!giftSnap.exists) throw new functions.https.HttpsError("not-found", "Gift Story not found.");
  const gift = {...(giftSnap.data() || {}), id: giftId};
  if (!await participantAuthorized(context, gift, text(data.token))) throw new functions.https.HttpsError("permission-denied", "Gift Story access required.");
  const storagePath = text(data.storagePath);
  if (!storagePath.startsWith(`gift_story_renders/${giftId}/`)) throw new functions.https.HttpsError("invalid-argument", "Invalid story video path.");
  const file = getStorage().bucket().file(storagePath);
  const [exists] = await file.exists();
  if (!exists) throw new functions.https.HttpsError("not-found", "Rendered video upload was not found.");
  const expiresAt = Timestamp.fromMillis(Date.now() + STORY_RETENTION_HOURS * 60 * 60 * 1000);
  const previousPath = text(gift.giftStoryRenderedVideoPath);
  if (previousPath && previousPath !== storagePath) await getStorage().bucket().file(previousPath).delete({ignoreNotFound: true}).catch(() => null);
  await giftRef.set({
    giftStoryRenderedVideoPath: storagePath,
    giftStoryVideoMime: text(data.mime),
    giftStoryVideoStatus: "ready",
    giftStoryVideoRenderedAt: FieldValue.serverTimestamp(),
    giftStoryVideoExpiresAt: expiresAt,
    giftStoryUpdatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  return {ok: true, expiresAt: expiresAt.toMillis()};
});

exports.getGiftStoryVideoDownload = functions.https.onCall(async (data, context) => {
  const db = getFirestore();
  const giftId = text(data.giftRequestId);
  const giftSnap = await db.collection("giftRequests").doc(giftId).get();
  if (!giftSnap.exists) throw new functions.https.HttpsError("not-found", "Gift Story not found.");
  const gift = {...(giftSnap.data() || {}), id: giftId};
  if (!await participantAuthorized(context, gift, text(data.token))) throw new functions.https.HttpsError("permission-denied", "Gift Story access required.");
  const storagePath = text(gift.giftStoryRenderedVideoPath);
  if (!storagePath || gift.giftStoryVideoStatus !== "ready") throw new functions.https.HttpsError("failed-precondition", "Gift Story video is still processing.");
  const expiry = gift.giftStoryVideoExpiresAt && gift.giftStoryVideoExpiresAt.toMillis ? gift.giftStoryVideoExpiresAt.toMillis() : 0;
  if (!expiry || expiry <= Date.now()) throw new functions.https.HttpsError("failed-precondition", "Gift Story video has expired.");
  const [downloadUrl] = await getStorage().bucket().file(storagePath).getSignedUrl({version: "v4", action: "read", expires: Math.min(expiry, Date.now() + 15 * 60 * 1000)});
  return {downloadUrl, mime: gift.giftStoryVideoMime || "video/webm", expiresAt: expiry};
});

exports.retryGiftStoryAutomation = functions.https.onCall(async (data, context) => {
  if (!await adminAuthorized(context)) throw new functions.https.HttpsError("permission-denied", "Admin access required.");
  const giftId = text(data.giftRequestId);
  const giftSnap = await getFirestore().collection("giftRequests").doc(giftId).get();
  if (!giftSnap.exists) throw new functions.https.HttpsError("not-found", "Gift request not found.");
  const gift = giftSnap.data() || {};
  if (!isComplete(gift.giftStatus || gift.status)) throw new functions.https.HttpsError("failed-precondition", "Gift must be delivered first.");
  const result = await unlockGiftStory(getFirestore(), giftSnap, text(gift.deliveryId), {
    forceNewToken: Boolean(data.regenerateToken),
    retryEmails: true,
  });
  return {ok: true, expiresAt: result.expiresAt.toMillis()};
});

exports.manageGiftStoryAccess = functions.https.onCall(async (data, context) => {
  if (!await adminAuthorized(context)) throw new functions.https.HttpsError("permission-denied", "Admin access required.");
  const db = getFirestore();
  const giftId = text(data.giftRequestId);
  const action = text(data.action);
  const giftRef = db.collection("giftRequests").doc(giftId);
  const giftSnap = await giftRef.get();
  if (!giftSnap.exists) throw new functions.https.HttpsError("not-found", "Gift request not found.");
  const gift = giftSnap.data() || {};
  const hash = text(gift.giftStoryAccessTokenHash);
  if (action === "revoke") {
    if (hash) await db.collection("giftStoryAccessTokens").doc(hash).set({status: "revoked", revokedAt: FieldValue.serverTimestamp()}, {merge: true});
    await giftRef.set({giftStoryShareEnabled: false, giftStoryAccessStatus: "revoked", giftStoryUpdatedAt: FieldValue.serverTimestamp()}, {merge: true});
  } else if (action === "extend") {
    const expiresAt = Timestamp.fromMillis(Date.now() + STORY_RETENTION_HOURS * 60 * 60 * 1000);
    if (hash) await db.collection("giftStoryAccessTokens").doc(hash).set({expiresAt, status: "active", updatedAt: FieldValue.serverTimestamp()}, {merge: true});
    await giftRef.set({giftStoryAccessExpiresAt: expiresAt, giftStoryVideoExpiresAt: expiresAt, giftStoryUpdatedAt: FieldValue.serverTimestamp()}, {merge: true});
  } else if (action === "delete_assets") {
    const path = text(gift.giftStoryRenderedVideoPath);
    if (path) await getStorage().bucket().file(path).delete({ignoreNotFound: true});
    await giftRef.set({giftStoryRenderedVideoPath: FieldValue.delete(), giftStoryVideoStatus: "deleted", giftStoryUpdatedAt: FieldValue.serverTimestamp()}, {merge: true});
  } else {
    throw new functions.https.HttpsError("invalid-argument", "Unknown Gift Story action.");
  }
  return {ok: true};
});

exports.giftStoryLanding = functions.https.onRequest(async (req, res) => {
  res.set("X-Robots-Tag", "noindex, nofollow, noarchive");
  res.set("Cache-Control", "no-store");
  const token = text(req.path.split("/").filter(Boolean).pop() || req.query.token);
  const record = await tokenRecord(getFirestore(), token);
  if (!record) return res.status(410).send("<!doctype html><title>Gift Story expired</title><meta name=robots content=noindex><body style='background:#050816;color:white;font-family:Helvetica;padding:48px'><h1>This Gift Story link has expired.</h1></body>");
  const giftSnap = await getFirestore().collection("giftRequests").doc(record.data.giftRequestId).get();
  if (!giftSnap.exists) return res.status(404).send("Gift Story not found.");
  const gift = giftSnap.data() || {};
  const occasion = text(gift.occasion || "A special gift").replace(/[<>]/g, "");
  const approvedPhotos = [
    ...(Array.isArray(gift.giftStoryPhotos) ? gift.giftStoryPhotos : []),
    ...(Array.isArray(gift.giftStoryPhotoUrls) ? gift.giftStoryPhotoUrls : []),
  ].filter((value) => /^https:\/\//.test(text(value)));
  const imageMeta = approvedPhotos.length ? `<meta property="og:image" content="${text(approvedPhotos[0]).replace(/[<>"]/g, "")}">` : "";
  let videoMeta = "";
  const videoPath = text(gift.giftStoryRenderedVideoPath);
  if (gift.giftStoryVideoStatus === "ready" && videoPath) {
    try {
      const [videoUrl] = await getStorage().bucket().file(videoPath).getSignedUrl({version: "v4", action: "read", expires: Date.now() + 15 * 60 * 1000});
      const cleanVideoUrl = videoUrl.replace(/[<>"]/g, "");
      const videoType = text(gift.giftStoryVideoMime || "video/webm").replace(/[<>"]/g, "");
      videoMeta = `<meta property="og:video" content="${cleanVideoUrl}"><meta property="og:video:secure_url" content="${cleanVideoUrl}"><meta property="og:video:type" content="${videoType}">`;
    } catch (error) {
      console.error("Gift Story social video metadata failed", error);
    }
  }
  const appUrl = `https://circumuk.com/?app=gifts&giftStoryToken=${encodeURIComponent(token)}`;
  return res.status(200).send(`<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width"><meta name="robots" content="noindex,nofollow,noarchive"><meta property="og:title" content="A special gift story from Gifts by Circum"><meta property="og:description" content="${occasion} — watch this private Gift Story."><meta property="og:type" content="video.other">${imageMeta}${videoMeta}<title>Gifts by Circum Story</title></head><body style="margin:0;background:radial-gradient(circle at 20% 10%,#6D5EF8 0,#121938 36%,#050816 78%);color:white;font-family:Helvetica,Arial;min-height:100vh;display:grid;place-items:center"><main style="text-align:center;max-width:540px;padding:36px"><div style="font-size:14px;letter-spacing:.18em;font-weight:800">GIFTS BY CIRCUM</div><h1 style="font-size:48px;line-height:1.02">A special gift story awaits.</h1><p style="font-size:18px;opacity:.78">Private, thoughtful, and created to be remembered.</p><a href="${appUrl}" style="display:inline-block;margin-top:18px;padding:17px 28px;border-radius:999px;color:white;text-decoration:none;font-weight:800;background:linear-gradient(120deg,#38BDF8,#6D5EF8,#F472B6)">Watch Story</a></main></body></html>`);
});

exports.cleanupExpiredGiftStories = functions.pubsub.schedule("every 60 minutes").onRun(async () => {
  const db = getFirestore();
  const expired = await db.collection("giftStoryAccessTokens").where("expiresAt", "<=", Timestamp.now()).limit(200).get();
  for (const tokenDoc of expired.docs) {
    const data = tokenDoc.data() || {};
    const giftRef = db.collection("giftRequests").doc(data.giftRequestId);
    const giftSnap = await giftRef.get();
    if (giftSnap.exists) {
      const gift = giftSnap.data() || {};
      const path = text(gift.giftStoryRenderedVideoPath);
      if (path) await getStorage().bucket().file(path).delete({ignoreNotFound: true}).catch((error) => console.error("Gift Story asset cleanup failed", error));
      await giftRef.set({
        giftStoryRenderedVideoPath: FieldValue.delete(),
        giftStoryAccessToken: FieldValue.delete(),
        giftStoryAccessTokenHash: FieldValue.delete(),
        giftStoryAccessStatus: "expired",
        giftStoryVideoStatus: "expired",
        giftStoryUpdatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    }
    await tokenDoc.ref.delete();
  }
  return null;
});

module.exports.isGiftDelivery = isGiftDelivery;
module.exports.isComplete = isComplete;
module.exports.tokenHash = tokenHash;
module.exports.safeStory = safeStory;
module.exports.hasActiveGiftDispute = hasActiveGiftDispute;
module.exports.revealPolicyAllowsMutualReveal = revealPolicyAllowsMutualReveal;
module.exports.campaignRevealMatchDecision = campaignRevealMatchDecision;
module.exports.buildRevealedCampaignMatchRecord = buildRevealedCampaignMatchRecord;
