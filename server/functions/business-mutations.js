/* eslint-disable max-len, require-jsdoc */
"use strict";

const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {resolveBusinessAuthority, hasBusinessPermission} = require("./business-authority");
const {appendOperationalEvent} = require("./delivery-operational-events");

function text(value, max = 500) {
  return `${value || ""}`.trim().slice(0, max);
}

async function requireAction(db, businessId, context, permission, systemRoles) {
  if (!context.auth || !context.auth.uid) {
    throw new functions.https.HttpsError("unauthenticated", "Sign in to continue.");
  }
  const account = await db.collection("businessAccounts").doc(businessId).get();
  if (!account.exists) throw new functions.https.HttpsError("not-found", "Business workspace not found.");
  const authority = await resolveBusinessAuthority(db, account.data() || {}, businessId, {
    uid: context.auth.uid,
    email: context.auth.token && context.auth.token.email,
  });
  if (!hasBusinessPermission(authority, permission, systemRoles)) {
    throw new functions.https.HttpsError("permission-denied", "This Business role cannot perform that action.");
  }
  return {uid: context.auth.uid, authority};
}

exports.updateBusinessDeliveryNotes = functions.runWith({enforceAppCheck: true})
    .region("us-central1").https.onCall(async (data, context) => {
      const db = getFirestore();
      const businessId = text(data && data.businessId, 160);
      const deliveryId = text(data && data.deliveryId, 180);
      const note = text(data && data.note, 1000);
      const reason = text(data && data.reason, 300);
      if (!businessId || !deliveryId) throw new functions.https.HttpsError("invalid-argument", "Business and delivery are required.");
      const {uid} = await requireAction(db, businessId, context, "deliveries.notes.modify", ["owner", "admin", "manager", "operations", "dispatcher"]);
      const deliveryRef = db.collection("deliveryRequests").doc(deliveryId);
      await db.runTransaction(async (tx) => {
        const snapshot = await tx.get(deliveryRef);
        if (!snapshot.exists || text(snapshot.data().businessId || snapshot.data().businessAccountId, 160) !== businessId) {
          throw new functions.https.HttpsError("not-found", "Business delivery not found.");
        }
        const previous = text(snapshot.data().businessDeliveryNotes, 1000);
        tx.set(deliveryRef, {
          businessDeliveryNotes: note,
          businessDeliveryNotesUpdatedAt: FieldValue.serverTimestamp(),
          businessDeliveryNotesUpdatedBy: uid,
        }, {merge: true});
        tx.set(db.collection("businessAuditLogs").doc(), {
          businessId,
          actorUserId: uid,
          action: "business_delivery_notes_updated",
          targetType: "delivery",
          targetId: deliveryId,
          previousState: {note: previous},
          newState: {note},
          reason: reason || null,
          createdAt: FieldValue.serverTimestamp(),
        });
      });
      return {status: "updated", deliveryId};
    });

exports.acknowledgeBusinessOperationalIncident = functions.runWith({enforceAppCheck: true})
    .region("us-central1").https.onCall(async (data, context) => {
      const db = getFirestore();
      const businessId = text(data && data.businessId, 160);
      const incidentId = text(data && data.incidentId, 180);
      const reason = text(data && data.reason, 300);
      if (!businessId || !incidentId) throw new functions.https.HttpsError("invalid-argument", "Business and incident are required.");
      const {uid} = await requireAction(db, businessId, context, "operations.incidents.acknowledge", ["owner", "admin", "manager", "operations"]);
      const incidentRef = db.collection("operationalIncidents").doc(incidentId);
      let deliveryId;
      await db.runTransaction(async (tx) => {
        const incident = await tx.get(incidentRef);
        if (!incident.exists) throw new functions.https.HttpsError("not-found", "Incident not found.");
        deliveryId = text(incident.data().deliveryId, 180);
        const delivery = await tx.get(db.collection("deliveryRequests").doc(deliveryId));
        if (!delivery.exists || text(delivery.data().businessId || delivery.data().businessAccountId, 160) !== businessId) {
          throw new functions.https.HttpsError("not-found", "Business incident not found.");
        }
        const previousStatus = text(incident.data().status || "OPEN", 40);
        tx.set(incidentRef, {
          status: "ACKNOWLEDGED",
          acknowledgedAt: FieldValue.serverTimestamp(),
          acknowledgedBy: uid,
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
        tx.set(db.collection("businessAuditLogs").doc(), {
          businessId,
          actorUserId: uid,
          action: "business_incident_acknowledged",
          targetType: "operationalIncident",
          targetId: incidentId,
          previousState: {status: previousStatus},
          newState: {status: "ACKNOWLEDGED"},
          reason: reason || null,
          createdAt: FieldValue.serverTimestamp(),
        });
      });
      await appendOperationalEvent(db, {
        deliveryId,
        eventType: "IncidentAcknowledged",
        correlationId: incidentId,
        actorType: "business",
        actorId: uid,
        source: "businessOperations",
        metadata: {incidentId},
      });
      return {ok: true, incidentId};
    });

exports._private = {text, requireAction};
