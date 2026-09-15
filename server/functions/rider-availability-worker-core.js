/* eslint-disable max-len, require-jsdoc */
"use strict";

const crypto = require("node:crypto");
const presenceCore = require("./rider-presence-core");

function claimId(event = {}) {
  const source = String(event.sourceCollection || "unknown");
  const eventId = String(event.eventId || "");
  return `rider_availability_${crypto.createHash("sha256").update(`${source}:${eventId}`).digest("hex")}`;
}

function assertEvent(event = {}) {
  if (!/^[A-Za-z0-9_-]{1,128}$/.test(String(event.riderId || ""))) throw Object.assign(new Error("invalid_rider_id"), {statusCode: 400});
  if (!["riderProfiles", "riders"].includes(event.sourceCollection)) throw Object.assign(new Error("invalid_event_source"), {statusCode: 400});
  if (!String(event.eventId || "").trim() || String(event.eventId).length > 128) throw Object.assign(new Error("invalid_event_id"), {statusCode: 400});
}

async function processAvailabilityEvent({db, event, fieldValue}) {
  assertEvent(event);
  const id = claimId(event);
  return db.runTransaction(async (transaction) => {
    const claimRef = db.collection("eventHandlerClaims").doc(id);
    const riderRef = db.collection("riders").doc(event.riderId);
    const profileRef = db.collection("riderProfiles").doc(event.riderId);
    const presenceRef = db.collection("riderPresence").doc(event.riderId);
    const [claim, riderSnapshot, profileSnapshot, presenceSnapshot] = await Promise.all([
      transaction.get(claimRef), transaction.get(riderRef), transaction.get(profileRef), transaction.get(presenceRef),
    ]);
    if (claim.exists) return {outcome: "DUPLICATE", claimId: id, riderId: event.riderId, changedFields: []};
    const rider = riderSnapshot.exists ? riderSnapshot.data() || {} : {};
    const profile = profileSnapshot.exists ? profileSnapshot.data() || {} : {};
    const presence = presenceSnapshot.exists ? presenceSnapshot.data() || {} : {};
    const desired = presenceCore.computeRiderOperationalState({profile: {...rider, ...profile}, presence});
    const patch = presenceCore.semanticPatch(presence, desired);
    const outcome = Object.keys(patch).length ? "APPLIED" : "NO_OP";
    if (outcome === "APPLIED") {
      transaction.set(presenceRef, {...patch, riderId: event.riderId, updatedAt: fieldValue.serverTimestamp(), source: `cloudRunAvailability:${event.sourceCollection}`}, {merge: true});
    }
    transaction.create(claimRef, {
      handler: "rider_availability",
      eventId: event.eventId,
      riderId: event.riderId,
      sourceCollection: event.sourceCollection,
      status: "completed",
      outcome,
      changedFields: Object.keys(patch),
      createdAt: fieldValue.serverTimestamp(),
    });
    return {outcome, claimId: id, riderId: event.riderId, changedFields: Object.keys(patch), state: desired};
  });
}

module.exports = {assertEvent, claimId, processAvailabilityEvent};
