"use strict";

const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {getStorage} = require("firebase-admin/storage");
const {requireAdmin} = require("./admin-auth");
const evidence = require("./delivery-evidence-core");
const {appendOperationalEvent} = require("./delivery-operational-events");

const STATES = new Set([
  "procurement_review", "sourcing", "item_confirmed", "purchased",
  "ready_for_collection", "rider_fulfilment", "delivered", "unavailable",
  "substitution_required", "procurement_failed", "cancelled", "refunded",
]);
const TERMINAL = new Set(["delivered", "cancelled", "refunded"]);
const TRANSITIONS = {
  submitted_for_review: new Set(["procurement_review", "cancelled"]),
  procurement_review: new Set(["sourcing", "cancelled"]),
  sourcing: new Set(["item_confirmed", "substitution_required", "unavailable", "procurement_failed"]),
  substitution_required: new Set(["sourcing", "item_confirmed"]),
  unavailable: new Set(["sourcing", "substitution_required"]),
  procurement_failed: new Set(["sourcing"]),
  item_confirmed: new Set(["purchased", "sourcing"]),
  purchased: new Set(["ready_for_collection", "procurement_failed", "sourcing"]),
  ready_for_collection: new Set(["rider_fulfilment", "procurement_failed"]),
  rider_fulfilment: new Set(["delivered", "procurement_failed"]),
};

const COMMITTED_STATES = new Set([
  "sourcing", "item_confirmed", "purchased", "ready_for_collection",
  "rider_fulfilment", "unavailable", "substitution_required",
  "procurement_failed", "delivered",
]);

const TIMELINE_EVENTS = Object.freeze({
  sourcing: "SourcingStarted",
  unavailable: "ItemUnavailable",
  substitution_required: "SubstitutionProposed",
  item_confirmed: "SubstitutionApproved",
  purchased: "ItemPurchased",
  ready_for_collection: "ReadyForCollection",
  rider_fulfilment: "RiderAssigned",
  delivered: "Delivered",
  cancelled: "Cancelled",
});

function text(value, max = 500) {
  return `${value || ""}`.trim().slice(0, max);
}

function moneyMinor(value) {
  const amount = Number(value);
  if (!Number.isInteger(amount) || amount < 0) {
    throw new functions.https.HttpsError("invalid-argument", "Enter a valid procurement amount.");
  }
  return amount;
}

function assertTransition(current, next, committed = COMMITTED_STATES.has(current)) {
  if (committed && ["cancelled", "refunded"].includes(next)) {
    throw new functions.https.HttpsError("failed-precondition", "This Gift is being prepared and cannot be cancelled through the normal flow.");
  }
  if (!STATES.has(next) || TERMINAL.has(current) || !(TRANSITIONS[current] || new Set()).has(next)) {
    throw new functions.https.HttpsError("failed-precondition", "This procurement action is not available from the current state.");
  }
}

function isProcurementCommitted(gift = {}, current = "") {
  return gift.procurementCommitted === true || Boolean(gift.procurementCommittedAt) || COMMITTED_STATES.has(current);
}

async function appendGiftTimeline(db, gift, giftId, next, actorType, actorId, correlationId, metadata = {}) {
  const eventType = TIMELINE_EVENTS[next];
  if (!eventType) return;
  await appendOperationalEvent(db, {
    deliveryId: text(gift.deliveryId || gift.canonicalDeliveryId || giftId, 240),
    eventType,
    correlationId,
    actorType,
    actorId,
    source: "giftProcurementAuthority",
    previousState: text(gift.procurementStatus || gift.giftStatus || gift.status, 80) || null,
    newState: next,
    metadata: {giftId, domain: "gifts", ...metadata},
  });
}

function procurementEventId(next, idempotencyKey) {
  return `${next}_${text(idempotencyKey, 160).replace(/[^a-zA-Z0-9_-]/g, "_")}`;
}

async function verifyPurchaseEvidence({bucket, giftId, procurementId, storagePath, purchaserId}) {
  const prefix = `giftAssets/${giftId}/procurement/${procurementId}/`;
  if (!storagePath.startsWith(prefix) || storagePath.slice(prefix.length).includes("/")) {
    throw new Error("Gift purchase evidence path is not canonical.");
  }
  const file = bucket.file(storagePath);
  const [exists] = await file.exists();
  if (!exists) throw new Error("Gift purchase evidence was not found.");
  const [metadata] = await file.getMetadata();
  const custom = metadata.metadata || {};
  if (text(custom.giftId, 240) !== giftId || text(custom.procurementId, 240) !== procurementId || text(custom.uploadedBy, 240) !== purchaserId) {
    throw new Error("Gift purchase evidence metadata does not match procurement authority.");
  }
  return evidence.immutableStorageReference({storagePath, metadata, uploadedBy: purchaserId, context: {domain: "gift_procurement", giftId, procurementId}});
}

exports.updateGiftProcurement = functions.runWith({enforceAppCheck: true}).https.onCall(async (data, context) => {
  const actorUid = requireAdmin(context, "Gift procurement access is required.");
  const giftId = text(data && data.giftId, 240);
  const next = text(data && data.status, 80).toLowerCase();
  const idempotencyKey = text(data && data.idempotencyKey, 160);
  if (!giftId || !idempotencyKey) {
    throw new functions.https.HttpsError("invalid-argument", "Gift and idempotency key are required.");
  }
  const db = getFirestore();
  const procurementId = text(data && data.procurementId, 240);
  const purchaseEvidencePath = text(data && data.purchaseEvidencePath, 600);
  let verifiedPurchaseEvidence = null;
  if (next === "purchased") {
    if (!procurementId || !purchaseEvidencePath) {
      throw new functions.https.HttpsError("failed-precondition", "Verified procurement identity and purchase evidence are required.");
    }
    try {
      verifiedPurchaseEvidence = await verifyPurchaseEvidence({bucket: getStorage().bucket(), giftId, procurementId, storagePath: purchaseEvidencePath, purchaserId: actorUid});
    } catch (error) {
      throw new functions.https.HttpsError("failed-precondition", error.message);
    }
  }
  const giftRef = db.collection("giftRequests").doc(giftId);
  const eventRef = giftRef.collection("procurementEvents").doc(procurementEventId(next, idempotencyKey));
  const result = await db.runTransaction(async (tx) => {
    const [giftSnap, eventSnap] = await Promise.all([tx.get(giftRef), tx.get(eventRef)]);
    if (eventSnap.exists) return {...eventSnap.data(), idempotent: true};
    if (!giftSnap.exists) throw new functions.https.HttpsError("not-found", "Gift request not found.");
    const gift = giftSnap.data() || {};
    if (gift.paymentStatus !== "paid") {
      throw new functions.https.HttpsError("failed-precondition", "Only a paid Gift request can enter procurement.");
    }
    const current = text(gift.procurementStatus || gift.giftStatus || gift.status, 80).toLowerCase();
    const committed = isProcurementCommitted(gift, current);
    assertTransition(current, next, committed);
    const expectedPriceMinor = data.expectedPriceMinor == null ? null : moneyMinor(data.expectedPriceMinor);
    const actualPriceMinor = data.actualPriceMinor == null ? null : moneyMinor(data.actualPriceMinor);
    const paidBudgetMinor = Math.round(Number(gift.grossGiftBudget || gift.grossBudget || 0) * 100);
    if (actualPriceMinor != null && actualPriceMinor > paidBudgetMinor) {
      throw new functions.https.HttpsError("failed-precondition", "Purchase cost exceeds the paid Gift budget.");
    }
    if (next === "purchased" && (!actualPriceMinor || !verifiedPurchaseEvidence)) {
      throw new functions.https.HttpsError("failed-precondition", "Verified purchase amount and evidence are required.");
    }
    const patch = {
      procurementStatus: next,
      procurementUpdatedAt: FieldValue.serverTimestamp(),
      procurementUpdatedBy: actorUid,
      ...(text(data.selectedItem, 240) ? {procurementSelectedItem: text(data.selectedItem, 240)} : {}),
      ...(text(data.supplier, 240) ? {procurementSupplier: text(data.supplier, 240)} : {}),
      ...(expectedPriceMinor != null ? {procurementExpectedPriceMinor: expectedPriceMinor} : {}),
      ...(actualPriceMinor != null ? {procurementActualPriceMinor: actualPriceMinor} : {}),
      ...(verifiedPurchaseEvidence ? {procurementId, procurementPurchaseEvidence: verifiedPurchaseEvidence} : {}),
      ...(text(data.reason, 500) ? {procurementReason: text(data.reason, 500)} : {}),
      ...(!committed && next === "sourcing" ? {
        procurementCommitted: true,
        procurementCommittedAt: FieldValue.serverTimestamp(),
        procurementCommittedBy: actorUid,
        procurementCommitmentAuthority: "gifts_team",
        procurementCommitmentPaymentReference: text(gift.stripePaymentIntentId || gift.stripeCheckoutSessionId, 240),
      } : {}),
    };
    const event = {
      giftId, previousState: current, newState: next, actorType: "admin",
      actorId: actorUid, reason: text(data.reason, 500) || null,
      idempotencyKey, expectedPriceMinor, actualPriceMinor,
      createdAt: FieldValue.serverTimestamp(), source: "gift_procurement_authority",
    };
    tx.set(giftRef, patch, {merge: true});
    tx.create(eventRef, event);
    if (["unavailable", "procurement_failed"].includes(next)) {
      tx.set(db.collection("operationalIncidents").doc(`gift_${giftId}_${next}`), {
        incidentId: `gift_${giftId}_${next}`,
        giftId,
        incidentType: `gift_${next}`,
        severity: next === "procurement_failed" ? "RED" : "AMBER",
        status: "OPEN",
        currentDeliveryState: next,
        detectedAt: FieldValue.serverTimestamp(),
        source: "gift_procurement_authority",
      }, {merge: true});
    }
    return {giftId, status: next, idempotent: false, gift, commitmentCreated: !committed && next === "sourcing"};
  });
  if (!result.idempotent) {
    if (result.commitmentCreated) {
      await appendOperationalEvent(db, {
        deliveryId: text(result.gift.deliveryId || result.gift.canonicalDeliveryId || giftId, 240),
        eventType: "ProcurementCommitted",
        correlationId: `gift:${giftId}:commitment`,
        actorType: "admin",
        actorId: actorUid,
        source: "giftProcurementAuthority",
        previousState: text(result.gift.procurementStatus || result.gift.giftStatus || result.gift.status, 80) || null,
        newState: "sourcing",
        metadata: {giftId, domain: "gifts", paymentReferencePresent: Boolean(result.gift.stripePaymentIntentId || result.gift.stripeCheckoutSessionId)},
      });
    }
    await appendGiftTimeline(db, result.gift, giftId, next, "admin", actorUid, `gift:${giftId}:${procurementEventId(next, idempotencyKey)}`);
  }
  return {giftId: result.giftId, status: result.status, idempotent: result.idempotent};
});

exports.proposeGiftSubstitution = functions.runWith({enforceAppCheck: true}).https.onCall(async (data, context) => {
  const actorUid = requireAdmin(context, "Gift substitution access is required.");
  const giftId = text(data && data.giftId, 240);
  const replacement = text(data && data.proposedReplacement, 240);
  const reason = text(data && data.reason, 500);
  if (!giftId || !replacement || !reason) throw new functions.https.HttpsError("invalid-argument", "Gift, replacement and reason are required.");
  const ref = getFirestore().collection("giftRequests").doc(giftId);
  const snap = await ref.get();
  if (!snap.exists || snap.data().paymentStatus !== "paid") throw new functions.https.HttpsError("not-found", "Paid Gift request not found.");
  const gift = snap.data();
  if (!isProcurementCommitted(gift, text(gift.procurementStatus || gift.giftStatus || gift.status, 80).toLowerCase())) {
    throw new functions.https.HttpsError("failed-precondition", "Gift procurement must be committed before substitution.");
  }
  await ref.set({
    procurementStatus: "substitution_required",
    substitution: {proposedReplacement: replacement, reason, status: "pending_sender", proposedBy: actorUid, proposedAt: FieldValue.serverTimestamp()},
    procurementUpdatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  await appendGiftTimeline(getFirestore(), gift, giftId, "substitution_required", "admin", actorUid, `gift:${giftId}:substitution:${text(data.idempotencyKey, 160) || replacement}`);
  return {giftId, status: "substitution_required"};
});

exports.decideGiftSubstitution = functions.runWith({enforceAppCheck: true}).https.onCall(async (data, context) => {
  const senderId = context.auth && context.auth.uid;
  if (!senderId) throw new functions.https.HttpsError("unauthenticated", "Sign in to review this substitution.");
  const giftId = text(data && data.giftId, 240);
  const approved = data && data.approved === true;
  const ref = getFirestore().collection("giftRequests").doc(giftId);
  const snap = await ref.get();
  const gift = snap.exists ? snap.data() : {};
  if (!snap.exists || gift.senderId !== senderId || gift.procurementStatus !== "substitution_required") {
    throw new functions.https.HttpsError("permission-denied", "Gift substitution is unavailable.");
  }
  const next = approved ? "item_confirmed" : "sourcing";
  await ref.set({
    procurementStatus: next,
    "substitution.status": approved ? "approved" : "rejected",
    "substitution.decidedBy": senderId,
    "substitution.decidedAt": FieldValue.serverTimestamp(),
    procurementUpdatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  await appendOperationalEvent(getFirestore(), {
    deliveryId: text(gift.deliveryId || gift.canonicalDeliveryId || giftId, 240),
    eventType: approved ? "SubstitutionApproved" : "SubstitutionRejected",
    correlationId: `gift:${giftId}:substitution-decision:${text(gift.substitution && gift.substitution.proposedAt, 80) || "current"}`,
    actorType: "sender",
    actorId: senderId,
    source: "giftProcurementAuthority",
    previousState: "substitution_required",
    newState: next,
    metadata: {giftId, domain: "gifts", recoveryContinues: !approved},
  });
  return {giftId, status: next};
});

exports._private = {assertTransition, isProcurementCommitted, moneyMinor, procurementEventId, verifyPurchaseEvidence};
