/* eslint-disable max-len, require-jsdoc */
const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const core = require("./rider-presence-core");
const staleCore = require("./stale-delivery-core");
const {loadFounderTestAccount} = require("./founder-authority");

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

async function activeDelivery(db, riderId) {
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
  if (!byRider.empty) return byRider.docs[0];
  const byAssigned = await db.collection("deliveryRequests")
      .where("assignedRiderId", "==", riderId)
      .where("status", "in", activeStates)
      .limit(1)
      .get();
  return byAssigned.empty ? null : byAssigned.docs[0];
}

function presencePatch({riderId, status, busy = false, location = null}) {
  const now = Date.now();
  const patch = {
    riderId,
    isOnline: status !== "offline",
    status: status === "offline" ? "offline" : "online",
    availabilityStatus: status,
    busy,
    updatedAt: FieldValue.serverTimestamp(),
    lastHeartbeatAt: now,
  };
  if (status === "available") patch.lastOnlineAt = FieldValue.serverTimestamp();
  if (status === "offline") patch.lastOfflineAt = FieldValue.serverTimestamp();
  if (location) {
    const accuracy = Number(location.accuracyMeters || location.accuracy || 0);
    const gpsStatus = text(location.gpsStatus || location.locationStatus || (accuracy > 0 ? "active" : "unknown"));
    const updatedAt = Number(location.updatedAt || location.clientRecordedAt || now);
    patch.currentLocation = {
      latitude: Number(location.latitude),
      longitude: Number(location.longitude),
      accuracyMeters: accuracy,
      heading: Number(location.heading || 0),
      speed: Number(location.speed || 0),
      mocked: location.mocked === true || location.isMocked === true,
      updatedAt,
    };
    patch.lastLocationAt = updatedAt;
    patch.gpsStatus = gpsStatus;
    patch.gpsSignalQuality = text(location.gpsSignalQuality || signalQuality(accuracy));
    patch.locationPermission = text(location.permission || location.locationPermission || "");
    patch.backgroundTracking = text(location.backgroundTracking || "");
    patch.batteryOptimisation = text(location.batteryOptimisation || "");
    patch.connectionStatus = "connected";
    const gpsHealth = core.gpsHealthResult({presence: {...patch}, now});
    patch.dispatchEligible = gpsHealth.eligible;
    patch.gpsHealth = gpsHealth;
    console.info("[GPS_HEALTH] evaluated", {
      riderId,
      source: status === "available" ? "goOnline" : "heartbeat",
      provider: location.provider || "unknown",
      platform: location.platform || "unknown",
      browser: location.browser || "unknown",
      rawLatitude: location.latitude,
      rawLongitude: location.longitude,
      rawAccuracy: location.accuracyMeters || location.accuracy,
      rawTimestamp: location.updatedAt || location.clientRecordedAt,
      serverReceiveTime: now,
      ...gpsHealth,
    });
  } else if (status === "available") {
    patch.gpsStatus = "unknown";
    patch.dispatchEligible = false;
    patch.gpsHealth = {
      eligible: false,
      reason: "NO_LOCATION",
      ageMs: null,
      accuracy: null,
      latitude: null,
      longitude: null,
      timestamp: null,
    };
    console.info("[GPS_HEALTH] evaluated", {
      riderId,
      source: "goOnline",
      serverReceiveTime: now,
      ...patch.gpsHealth,
    });
  }
  return patch;
}

function signalQuality(accuracy) {
  if (!Number.isFinite(accuracy) || accuracy <= 0) return "unknown";
  if (accuracy <= 25) return "high";
  if (accuracy <= 80) return "medium";
  return "reduced";
}

exports.goOnline = functions.https.onCall(async (data, context) => {
  try {
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
    batch.set(db.collection("riderProfiles").doc(riderId), {
      status: "online",
      availabilityStatus: "available",
      isOnline: true,
      dispatchEligible: patch.dispatchEligible === true,
      lastHeartbeatAt: patch.lastHeartbeatAt,
      lastOnlineAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    batch.set(db.collection("riderOperationalAudit").doc(), {riderId, action: "go_online", founderOverride: founder, actorUid: riderId, createdAt: FieldValue.serverTimestamp()});
    await batch.commit();
    return {success: true, presence: {...patch, serverTimestampPending: true}};
  } catch (error) {
    if (error instanceof functions.https.HttpsError) throw error;
    console.error("goOnline unexpected failure", {
      riderId: context.auth && context.auth.uid,
      code: error && error.code,
      message: error && error.message,
    });
    throw new functions.https.HttpsError(
        "failed-precondition",
        "We could not switch you online. Check your connection and try again.",
    );
  }
});

exports.goOffline = functions.https.onCall(async (data, context) => {
  const riderId = requireAuth(context);
  const db = getFirestore();
  const current = await db.collection("riderPresence").doc(riderId).get();
  const presence = current.exists ? current.data() : {};
  const referencedId = text(presence.activeDeliveryId || presence.currentDeliveryId);
  let staleRepair = null;
  if (referencedId) {
    const referenced = await db.collection("deliveryRequests").doc(referencedId).get();
    const tracking = referenced.exists ? await referenced.ref.collection("tracking").doc("liveLocation").get() : null;
    const referencedData = referenced.exists ? {
      ...referenced.data(),
      _lastTrackingAt: tracking && tracking.exists ? tracking.data().updatedAt : null,
    } : null;
    const decision = staleCore.evaluateDeliveryLock(
        referencedData,
        {exists: referenced.exists},
    );
    if (decision.block) {
      const status = referenced.exists ? staleCore.statusOf(referencedData) : "unknown";
      throw new functions.https.HttpsError(
          "failed-precondition",
          `Delivery ${referencedId} is still ${status.replaceAll("_", " ")}. Resolve it before going offline.`,
          {deliveryId: referencedId, status, reason: decision.reason},
      );
    }
    staleRepair = {deliveryId: referencedId, reason: decision.reason};
  }
  const active = await activeDelivery(db, riderId);
  if (active) {
    const status = staleCore.statusOf(active.data());
    throw new functions.https.HttpsError(
        "failed-precondition",
        `Delivery ${active.id} is still ${status.replaceAll("_", " ")}. Complete or resolve it before going offline.`,
        {deliveryId: active.id, status, reason: `active_${status}`},
    );
  }
  const patch = presencePatch({riderId, status: "offline", busy: false, location: data && data.location});
  const batch = db.batch();
  batch.set(db.collection("riderPresence").doc(riderId), {
    ...patch,
    activeDeliveryId: FieldValue.delete(),
    currentDeliveryId: FieldValue.delete(),
    source: staleRepair ? "goOfflineStaleReferenceRepair" : "goOffline",
  }, {merge: true});
  batch.set(db.collection("riders").doc(riderId), {status: "offline", availabilityStatus: "offline", updatedAt: FieldValue.serverTimestamp()}, {merge: true});
  batch.set(db.collection("riderProfiles").doc(riderId), {
    status: "offline",
    availabilityStatus: "offline",
    isOnline: false,
    dispatchEligible: false,
    lastOfflineAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  batch.set(db.collection("riderOperationalAudit").doc(), {riderId, action: "go_offline", actorUid: riderId, createdAt: FieldValue.serverTimestamp()});
  if (staleRepair) {
    batch.set(db.collection("riderOperationalAudit").doc(), {
      riderId,
      deliveryId: staleRepair.deliveryId,
      action: "stale_active_delivery_reference_repaired",
      reason: staleRepair.reason,
      actorUid: riderId,
      createdAt: FieldValue.serverTimestamp(),
    });
  }
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
  const batch = db.batch();
  batch.set(current.ref, {
    ...patch,
    source: "heartbeat",
  }, {merge: true});
  batch.set(db.collection("riders").doc(riderId), {
    status: "online",
    availabilityStatus: status,
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  batch.set(db.collection("riderProfiles").doc(riderId), {
    status: "online",
    availabilityStatus: status,
    isOnline: true,
    dispatchEligible: patch.dispatchEligible === true,
    lastHeartbeatAt: patch.lastHeartbeatAt,
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  await batch.commit();
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
        status: "online",
        busy,
        availabilityStatus: next,
        activeDeliveryId: busy ? context.params.deliveryId : null,
        updatedAt: FieldValue.serverTimestamp(),
        source: "deliveryWrite",
      }, {merge: true});
      return null;
    });

async function forceOfflineWhenBlocked(change, context) {
  if (!change.after.exists) return null;
  const riderId = context.params.riderId;
  const db = getFirestore();
  const profile = await riderProfile(db, riderId);
  const founderTestAccount = await loadFounderTestAccount(db, riderId);
  if (founderTestAccount) profile.founderTestAccount = founderTestAccount;
  const reason = core.blockedReason(profile);
  if (!reason) return null;
  await db.collection("riderPresence").doc(riderId).set({
    riderId,
    isOnline: false,
    status: "offline",
    busy: false,
    availabilityStatus: "offline",
    connectionStatus: "offline",
    offlineReason: "admin_restriction",
    offlineDetail: reason,
    lastOfflineAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
    source: "adminRestriction",
  }, {merge: true});
  return null;
}

exports.onRiderRecordAvailabilityWrite = functions.firestore
    .document("riders/{riderId}")
    .onWrite(forceOfflineWhenBlocked);

exports.onRiderProfileAvailabilityWrite = functions.firestore
    .document("riderProfiles/{riderId}")
    .onWrite(forceOfflineWhenBlocked);

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
          status: "online",
          availabilityStatus: "connection_lost",
          connectionStatus: "lost",
          gpsStatus: "stale",
          dispatchEligible: false,
          staleAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
          source: "staleHeartbeat",
        }, {merge: true});
      });
      await batch.commit();
      return {markedConnectionLost: snapshot.size};
    });

exports.requireDispatchablePresence = async function(riderId, riderProfileData = {}) {
  const presenceDoc = await getFirestore().collection("riderPresence").doc(riderId).get();
  const presence = presenceDoc.exists ? presenceDoc.data() : {};
  if (!core.canReceiveDispatch({profile: riderProfileData, presence})) {
    throw new functions.https.HttpsError("failed-precondition", "Go online and remain available before accepting deliveries.");
  }
  return presence;
};
