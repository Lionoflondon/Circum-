/* eslint-disable max-len, require-jsdoc */
"use strict";

const {FieldValue, Timestamp} = require("firebase-admin/firestore");

const OWNERSHIP_COLLECTION = "runtimeOwnership";
const OWNERSHIP_DOCUMENT = "giftStoryCompletion";
const DEFAULT_OWNER = "firestore";
const CLAIM_LEASE_MS = 5 * 60 * 1000;
const VALID_OWNERS = new Set(["none", "firestore", "cloud_run"]);

function text(value) {
  return `${value || ""}`.trim();
}

function ownershipRef(db) {
  return db.collection(OWNERSHIP_COLLECTION).doc(OWNERSHIP_DOCUMENT);
}

async function getGiftStoryOwner(db) {
  const snapshot = await ownershipRef(db).get();
  if (!snapshot.exists) return DEFAULT_OWNER;
  const owner = text(snapshot.data() && snapshot.data().owner).toLowerCase();
  return VALID_OWNERS.has(owner) ? owner : "none";
}

async function isGiftStoryOwner(db, owner) {
  return (await getGiftStoryOwner(db)) === text(owner).toLowerCase();
}

function effectRef(db, giftId, effectId) {
  return db.collection("giftStoryCompletionEffects").doc(`${giftId}_${effectId}`);
}

function millis(value) {
  return value && typeof value.toMillis === "function" ? value.toMillis() : Number(value || 0);
}

async function waitForEffectCompletion(ref, effectId) {
  for (let attempt = 0; attempt < 100; attempt++) {
    await new Promise((resolve) => setTimeout(resolve, 10));
    const snapshot = await ref.get();
    const current = snapshot.exists ? snapshot.data() || {} : {};
    if (current.status === "completed") {
      return {status: "duplicate", effectId, result: current.result};
    }
    if (current.status !== "processing" || millis(current.leaseExpiresAt) <= Date.now()) break;
  }
  return {status: "busy", effectId};
}

async function runGiftStoryEffect(db, {
  giftId,
  deliveryId = "",
  effectId,
  source = "unknown",
  verify,
  execute,
}) {
  if (!giftId || !effectId || typeof execute !== "function") {
    throw new Error("gift_story_effect_requires_identity");
  }
  const ref = effectRef(db, giftId, effectId);
  const now = Date.now();
  const leaseOwner = `${source}:${effectId}:${now}`;
  const completedEffectMissing = typeof verify === "function" ? !(await verify()) : false;
  const claim = await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    const current = snapshot.exists ? snapshot.data() || {} : {};
    if (current.status === "completed" && !completedEffectMissing) return {status: "duplicate"};
    if (current.status === "processing" && millis(current.leaseExpiresAt) > now) {
      return {status: "busy"};
    }
    transaction.set(ref, {
      giftId,
      deliveryId,
      effectId,
      source,
      status: "processing",
      leaseOwner,
      attemptCount: Number(current.attemptCount || 0) + 1,
      leaseAcquiredAt: Timestamp.fromMillis(now),
      leaseExpiresAt: Timestamp.fromMillis(now + CLAIM_LEASE_MS),
      updatedAt: FieldValue.serverTimestamp(),
      createdAt: current.createdAt || FieldValue.serverTimestamp(),
    }, {merge: true});
    return {status: "claimed"};
  });
  if (claim.status === "duplicate") {
    const current = await ref.get();
    return {status: "duplicate", effectId, result: current.exists ? (current.data() || {}).result : undefined};
  }
  if (claim.status === "busy") return waitForEffectCompletion(ref, effectId);

  try {
    const result = await execute();
    await db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(ref);
      const current = snapshot.exists ? snapshot.data() || {} : {};
      if (current.leaseOwner !== leaseOwner) throw new Error("gift_story_effect_lease_lost");
      transaction.set(ref, {
        status: "completed",
        result: result && typeof result === "object" ? result : null,
        completedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
        leaseExpiresAt: Timestamp.fromMillis(Date.now()),
      }, {merge: true});
    });
    return {status: "completed", effectId, result};
  } catch (error) {
    await db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(ref);
      const current = snapshot.exists ? snapshot.data() || {} : {};
      if (current.leaseOwner !== leaseOwner) return;
      transaction.set(ref, {
        status: "retryable_failed",
        lastError: text(error && error.message || error).slice(0, 500),
        failedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
        leaseExpiresAt: Timestamp.fromMillis(Date.now()),
      }, {merge: true});
    }).catch(() => {});
    throw error;
  }
}

module.exports = {
  OWNERSHIP_COLLECTION,
  OWNERSHIP_DOCUMENT,
  DEFAULT_OWNER,
  CLAIM_LEASE_MS,
  ownershipRef,
  getGiftStoryOwner,
  isGiftStoryOwner,
  effectRef,
  runGiftStoryEffect,
};
