/* eslint-disable no-console, max-len, require-jsdoc */
"use strict";

const admin = require("firebase-admin");
const {FieldValue} = require("firebase-admin/firestore");

const ACTIVE_STATUSES = new Set([
  "requested",
  "pending",
  "available",
  "accepted",
  "rider_assigned",
  "navigating_to_pickup",
  "en_route_to_pickup",
  "arrived_at_pickup",
  "rider_arrived_pickup",
  "pickup_verified",
  "collected",
  "picked_up",
  "navigating_to_dropoff",
  "in_transit",
  "arrived_at_dropoff",
  "pin_required",
  "awaiting_pin",
  "awaiting_adjustment_review",
  "awaiting_sender_adjustment",
]);

function text(value) {
  return `${value || ""}`.trim();
}

function publicPinData(delivery = {}) {
  const protection = delivery.vanguardProtection || {};
  return {
    collectionPin: text(delivery.collectionPin || delivery.pickupPin || protection.collectionPin),
    deliveryPin: text(delivery.deliveryPin || delivery.receiverPin || delivery.dropoffPin || protection.deliveryPin),
    collectionPinAttemptCount: Number(delivery.collectionPinAttemptCount || 0),
    deliveryPinAttemptCount: Number(delivery.deliveryPinAttemptCount || 0),
    vanguardReviewRequired: delivery.vanguardReviewRequired === true,
    vanguardLastFailedStage: delivery.vanguardLastFailedStage || null,
  };
}

function numberOrNull(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function hasCompletePrivateAuthority(delivery = {}) {
  const pins = publicPinData(delivery);
  return pins.collectionPin.length > 0 && pins.deliveryPin.length > 0;
}

function hasPrivateMetadata(delivery = {}) {
  return Object.prototype.hasOwnProperty.call(delivery, "collectionPinAttemptCount") &&
    Object.prototype.hasOwnProperty.call(delivery, "deliveryPinAttemptCount") &&
    Object.prototype.hasOwnProperty.call(delivery, "vanguardReviewRequired");
}

function hasPublicPins(delivery = {}) {
  const pins = publicPinData(delivery);
  return pins.collectionPin.length > 0 || pins.deliveryPin.length > 0;
}

function isActive(delivery = {}) {
  const status = text(delivery.status || delivery.deliveryStatus).toLowerCase();
  return ACTIVE_STATUSES.has(status);
}

function stripPublicPinsPatch(delivery = {}) {
  const protection = delivery.vanguardProtection || {};
  const cleanProtection = {...protection};
  delete cleanProtection.collectionPin;
  delete cleanProtection.deliveryPin;
  return {
    collectionPin: FieldValue.delete(),
    pickupPin: FieldValue.delete(),
    deliveryPin: FieldValue.delete(),
    receiverPin: FieldValue.delete(),
    dropoffPin: FieldValue.delete(),
    collectionPinAttemptCount: FieldValue.delete(),
    deliveryPinAttemptCount: FieldValue.delete(),
    lastPinAttemptAt: FieldValue.delete(),
    vanguardReviewRequired: FieldValue.delete(),
    vanguardLastFailedStage: FieldValue.delete(),
    vanguardProtection: cleanProtection,
    updatedAt: FieldValue.serverTimestamp(),
  };
}

function privateAuthorityPatch({
  deliveryId,
  delivery = {},
  existingPrivate = {},
} = {}) {
  const publicPins = publicPinData(delivery);
  const privatePins = publicPinData(existingPrivate);
  const collectionPin = privatePins.collectionPin || publicPins.collectionPin;
  const deliveryPin = privatePins.deliveryPin || publicPins.deliveryPin;
  if (!collectionPin && !deliveryPin) return null;
  const privateCollectionAttempts = numberOrNull(existingPrivate.collectionPinAttemptCount);
  const privateDeliveryAttempts = numberOrNull(existingPrivate.deliveryPinAttemptCount);
  const publicCollectionAttempts = numberOrNull(delivery.collectionPinAttemptCount);
  const publicDeliveryAttempts = numberOrNull(delivery.deliveryPinAttemptCount);
  const protection = existingPrivate.vanguardProtection || {};
  return {
    deliveryId,
    requestId: existingPrivate.requestId || delivery.requestId || deliveryId,
    senderId: existingPrivate.senderId || delivery.senderId || delivery.userId || null,
    vanguardProtocolEnabled: true,
    vanguardProtection: {
      ...protection,
      enabled: true,
      ...(collectionPin ? {collectionPin} : {}),
      ...(deliveryPin ? {deliveryPin} : {}),
    },
    ...(collectionPin ? {collectionPin} : {}),
    ...(deliveryPin ? {deliveryPin} : {}),
    collectionPinAttemptCount: privateCollectionAttempts !== null ?
      privateCollectionAttempts :
      publicCollectionAttempts !== null ? publicCollectionAttempts : 0,
    deliveryPinAttemptCount: privateDeliveryAttempts !== null ?
      privateDeliveryAttempts :
      publicDeliveryAttempts !== null ? publicDeliveryAttempts : 0,
    vanguardReviewRequired:
      existingPrivate.vanguardReviewRequired === true ||
      publicPins.vanguardReviewRequired === true,
    vanguardLastFailedStage:
      existingPrivate.vanguardLastFailedStage ||
      publicPins.vanguardLastFailedStage ||
      null,
    migratedFromPublicDelivery: true,
    migratedAt: existingPrivate.migratedAt || FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };
}

async function migrate({apply = false, limit = 500} = {}) {
  if (!admin.apps.length) admin.initializeApp();
  const db = admin.firestore();
  const queryFields = [
    "vanguardProtocolEnabled",
    "vanguardEnabled",
    "requiresVanguard",
  ];
  const docs = new Map();
  for (const field of queryFields) {
    const snapshot = await db.collection("deliveryRequests")
        .where(field, "==", true)
        .limit(limit)
        .get();
    for (const doc of snapshot.docs) docs.set(doc.id, doc);
  }
  let scanned = 0;
  let eligible = 0;
  let migrated = 0;
  let strippedOnly = 0;
  let skippedMissingPins = 0;
  for (const doc of docs.values()) {
    scanned += 1;
    const delivery = doc.data();
    if (!isActive(delivery) || !hasPublicPins(delivery)) continue;
    eligible += 1;
    if (!apply) continue;
    const privateRef = db.collection("deliveryRequestsPrivate").doc(doc.id);
    await db.runTransaction(async (transaction) => {
      const privateSnapshot = await transaction.get(privateRef);
      const existingPrivate = privateSnapshot.exists ? privateSnapshot.data() || {} : {};
      const alreadyPrivate = hasCompletePrivateAuthority(existingPrivate);
      const privatePatch = alreadyPrivate && hasPrivateMetadata(existingPrivate) ? null : privateAuthorityPatch({
        deliveryId: doc.id,
        delivery,
        existingPrivate,
      });
      if (!alreadyPrivate && !privatePatch) {
        skippedMissingPins += 1;
        return;
      }
      if (privatePatch) transaction.set(privateRef, privatePatch, {merge: true});
      transaction.set(doc.ref, stripPublicPinsPatch(delivery), {merge: true});
      if (alreadyPrivate) strippedOnly += 1;
    });
    migrated += 1;
  }
  return {apply, scanned, eligible, migrated, strippedOnly, skippedMissingPins};
}

if (require.main === module) {
  const apply = process.argv.includes("--apply");
  const limitArg = process.argv.find((arg) => arg.startsWith("--limit="));
  const limit = limitArg ? Number(limitArg.split("=")[1]) : 500;
  migrate({apply, limit})
      .then((result) => {
        console.log(JSON.stringify(result, null, 2));
      })
      .catch((error) => {
        console.error(error);
        process.exit(1);
      });
}

module.exports = {
  migrate,
  publicPinData,
  hasCompletePrivateAuthority,
  hasPrivateMetadata,
  isActive,
  privateAuthorityPatch,
  stripPublicPinsPatch,
};
