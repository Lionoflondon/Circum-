/* eslint-disable max-len, require-jsdoc */
const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const core = require("./rider-presence-core");

function requireAuth(context) {
  if (!context.auth || !context.auth.uid) {
    throw new functions.https.HttpsError("unauthenticated", "Sign in first.");
  }
  return context.auth.uid;
}

function text(value) {
  return `${value || ""}`.trim();
}

async function riderProfile(db, riderId) {
  const riderDoc = await db.collection("riders").doc(riderId).get();
  const profileDoc = await db.collection("riderProfiles").doc(riderId).get();
  return {
    ...(riderDoc.exists ? riderDoc.data() : {}),
    ...(profileDoc.exists ? profileDoc.data() : {}),
  };
}

async function hasActiveDelivery(db, riderId) {
  const activeStates = [
    "accepted",
    "navigating_to_pickup",
    "arrived_at_pickup",
    "waiting",
    "pickup_verification",
    "pickup_verified",
    "collected",
    "navigating_to_dropoff",
    "arrived_at_dropoff",
    "pin_required",
    "issue_reported",
  ];
  const byRider = await db.collection("deliveryRequests")
      .where("riderId", "==", riderId)
      .where("status", "in", activeStates)
      .limit(1)
      .get();
  if (!byRider.empty) return true;
  const byAssigned = await db.collection("deliveryRequests")
      .where("assignedRiderId", "==", riderId)
      .where("status", "in", activeStates)
      .limit(1)
      .get();
  return !byAssigned.empty;
}

function presencePatch({riderId, status, busy = false, location = null}) {
  const patch = {
    riderId,
    isOnline: status !== "offline",
    availabilityStatus: status,
    busy,
    updatedAt: FieldValue.serverTimestamp(),
    lastHeartbeatAt: Date.now(),
  };
  if (status === "available") patch.lastOnlineAt = FieldValue.serverTimestamp();
  if (status === "offline") patch.lastOfflineAt = FieldValue.serverTimestamp();
  if (location) {
    patch.currentLocation = {
      latitude: Number(location.latitude),
      longitude: Number(location.longitude),
      accuracyMeters: Number(location.accuracyMeters || location.accuracy || 0),
      updatedAt: Date.now(),
    };
  }
  return patch;
}

exports.goOnline = functions.https.onCall(async (data, context) => {
  const riderId = requireAuth(context);
  const db = getFirestore();
  const profile = await riderProfile(db, riderId);
  const founder = context.auth.token && context.auth.token.founderRider === true;
  const reason = core.blockedReasonForAccess(profile, founder);
  if (reason) {
    throw new functions.https.HttpsError("failed-precondition", reason);
  }
  const patch = presencePatch({riderId, status: "available", busy: false, location: data && data.location});
  const batch = db.batch();
  batch.set(db.collection("riderPresence").doc(riderId), {...patch, source: "goOnline"}, {merge: true});
  batch.set(db.collection("riders").doc(riderId), {status: "online", availabilityStatus: "available", updatedAt: FieldValue.serverTimestamp()}, {merge: true});
  batch.set(db.collection("riderOperationalAudit").doc(), {riderId, action: "go_online", founderOverride: founder, actorUid: riderId, createdAt: FieldValue.serverTimestamp()});
  await batch.commit();
  return {success: true, presence: {...patch, serverTimestampPending: true}};
});

exports.goOffline = functions.https.onCall(async (data, context) => {
  const riderId = requireAuth(context);
  const db = getFirestore();
  const current = await db.collection("riderPresence").doc(riderId).get();
  const presence = current.exists ? current.data() : {};
  if (
    presence.busy === true ||
    text(presence.activeDeliveryId) ||
    await hasActiveDelivery(db, riderId)
  ) {
    throw new functions.https.HttpsError(
        "failed-precondition",
        "Complete your active delivery before going offline.",
    );
  }
  const patch = presencePatch({riderId, status: "offline", busy: false, location: data && data.location});
  const batch = db.batch();
  batch.set(db.collection("riderPresence").doc(riderId), {...patch, source: "goOffline"}, {merge: true});
  batch.set(db.collection("riders").doc(riderId), {status: "offline", availabilityStatus: "offline", updatedAt: FieldValue.serverTimestamp()}, {merge: true});
  batch.set(db.collection("riderOperationalAudit").doc(), {riderId, action: "go_offline", actorUid: riderId, createdAt: FieldValue.serverTimestamp()});
  await batch.commit();
  return {success: true, presence: {...patch, serverTimestampPending: true}};
});

exports.updateRiderPresence = functions.https.onCall(async (data, context) => {
  const riderId = requireAuth(context);
  const db = getFirestore();
  const current = await db.collection("riderPresence").doc(riderId).get();
  const presence = current.exists ? current.data() : {};
  if (presence.isOnline !== true) {
    throw new functions.https.HttpsError("failed-precondition", "Go online before sending presence updates.");
  }
  const status = presence.busy === true ? "busy" : "available";
  const patch = presencePatch({riderId, status, busy: presence.busy === true, location: data && data.location});
  await current.ref.set({
    ...patch,
    source: "heartbeat",
  }, {merge: true});
  return {success: true, presence: {...patch, serverTimestampPending: true}};
});

exports.onDeliveryPresenceWrite = functions.firestore
    .document("deliveryRequests/{deliveryId}")
    .onWrite(async (change, context) => {
      const before = change.before.exists ? change.before.data() : {};
      const after = change.after.exists ? change.after.data() : {};
      const riderId = text(after.riderId || after.assignedRiderId || after.driverId || after.assignedDriverId || before.riderId || before.assignedRiderId);
      const next = core.nextPresenceOnDelivery({before, after, riderId});
      if (!next) return null;
      const busy = next === "busy";
      await getFirestore().collection("riderPresence").doc(riderId).set({
        riderId,
        isOnline: true,
        busy,
        availabilityStatus: next,
        activeDeliveryId: busy ? context.params.deliveryId : null,
        updatedAt: FieldValue.serverTimestamp(),
        source: "deliveryWrite",
      }, {merge: true});
      return null;
    });

exports.markStaleRiderPresenceOffline = functions.pubsub
    .schedule("every 2 minutes")
    .onRun(async () => {
      const db = getFirestore();
      const cutoff = Date.now() - core.STALE_HEARTBEAT_MS;
      const snapshot = await db.collection("riderPresence")
          .where("isOnline", "==", true)
          .where("lastHeartbeatAt", "<", cutoff)
          .limit(200)
          .get();
      const batch = db.batch();
      snapshot.docs.forEach((doc) => {
        batch.set(doc.ref, {
          isOnline: false,
          busy: false,
          availabilityStatus: "offline",
          staleAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
          source: "staleHeartbeat",
        }, {merge: true});
      });
      await batch.commit();
      return {markedOffline: snapshot.size};
    });

exports.requireDispatchablePresence = async function(riderId, riderProfileData = {}) {
  const presenceDoc = await getFirestore().collection("riderPresence").doc(riderId).get();
  const presence = presenceDoc.exists ? presenceDoc.data() : {};
  if (!core.canReceiveDispatch({profile: riderProfileData, presence})) {
    throw new functions.https.HttpsError("failed-precondition", "Go online and remain available before accepting deliveries.");
  }
  return presence;
};
