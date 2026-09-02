/* eslint-disable max-len, require-jsdoc */
const functions = require("firebase-functions/v1");
const crypto = require("node:crypto");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {getStorage} = require("firebase-admin/storage");
const {canonicalDocumentId, DOCUMENT_MATRIX} = require("./rider-certification-policy");
const {riderCallable} = require("./rider-app-check");

const ALLOWED_DOCUMENT_TYPES = new Set(Object.values(DOCUMENT_MATRIX).flat());
const ALLOWED_CONTENT_TYPES = new Set([
  "image/jpeg",
  "image/png",
  "image/webp",
  "application/pdf",
]);
const MAX_DOCUMENT_BYTES = 8 * 1024 * 1024;
const ALLOWED_APPLICATION_SECTIONS = new Set([
  "personal_details",
  "home_address",
  "contact_details",
  "identity_verification",
  "right_to_work",
  "vehicle_details",
  "vehicle_documents",
  "payout_details",
  "roth_wallet_setup",
  "application_messages",
  "review_status",
]);
const ALLOWED_SECTION_STATUSES = new Set([
  "not_started",
  "in_progress",
  "submitted",
  "needs_attention",
  "approved",
]);
const ONBOARDING_TRANSITIONS = new Map([
  ["account_created", new Set(["profile_started"])],
  ["not_started", new Set(["profile_started", "phone_verified", "email_verified", "profile_complete"])],
  ["profile_started", new Set(["phone_verified", "email_verified", "profile_complete"])],
  ["phone_verified", new Set(["email_verified", "profile_complete"])],
  ["email_verified", new Set(["profile_complete"])],
  ["profile_complete", new Set(["profile_complete"])],
]);
const PUBLIC_RIDER_ID_PREFIX = "CR";

function newPublicRiderId() {
  return `${PUBLIC_RIDER_ID_PREFIX}-${crypto.randomBytes(5).toString("hex").toUpperCase()}`;
}

function requireRider(context) {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Sign in as a Rider to continue.");
  }
  return {
    uid: context.auth.uid,
    email: context.auth.token.email || null,
    name: context.auth.token.name || null,
  };
}

function text(value, max = 500) {
  return `${value || ""}`.trim().slice(0, max);
}

function normalizeNotificationIds(value) {
  const raw = Array.isArray(value) ? value : [value];
  return raw.map((entry) => text(entry, 160)).filter(Boolean).slice(0, 100);
}

function lower(value, max = 500) {
  return text(value, max).toLowerCase();
}

function cleanDocumentType(value) {
  const normalized = canonicalDocumentId(
      lower(value, 80).replace(/[^a-z0-9]+/g, "_").replace(/^_+|_+$/g, ""),
  );
  if (!ALLOWED_DOCUMENT_TYPES.has(normalized)) {
    throw new functions.https.HttpsError("invalid-argument", "Unsupported Rider document type.");
  }
  return normalized;
}

function cleanApplicationSection(value) {
  const normalized = lower(value, 80).replace(/[^a-z0-9]+/g, "_").replace(/^_+|_+$/g, "");
  if (!ALLOWED_APPLICATION_SECTIONS.has(normalized)) {
    throw new functions.https.HttpsError("invalid-argument", "Unsupported Rider application section.");
  }
  return normalized;
}

function cleanSectionStatus(value) {
  const normalized = lower(value, 80).replace(/[^a-z0-9]+/g, "_").replace(/^_+|_+$/g, "");
  if (!ALLOWED_SECTION_STATUSES.has(normalized)) {
    throw new functions.https.HttpsError("invalid-argument", "Unsupported Rider application section status.");
  }
  return normalized;
}

function safeFileName(value) {
  return text(value || "rider-document", 180).replace(/[^A-Za-z0-9._-]/g, "_");
}

function normalizeRiderDocumentFiles(data, documentType) {
  const multipart = Array.isArray(data && data.files) ? data.files : null;
  const rawFiles = multipart || [{
    side: "primary",
    base64: data && data.fileBase64,
    mimeType: data && data.contentType,
    fileName: data && data.fileName,
  }];
  const files = rawFiles.map((entry) => {
    if (!entry || typeof entry !== "object") {
      throw new functions.https.HttpsError("invalid-argument", "Invalid document attachment.");
    }
    const side = lower(entry.side || "primary", 20);
    if (!new Set(["front", "back", "primary"]).has(side)) {
      throw new functions.https.HttpsError("invalid-argument", "Unsupported document side.");
    }
    const contentType = lower(entry.mimeType || entry.contentType, 120);
    if (!ALLOWED_CONTENT_TYPES.has(contentType)) {
      throw new functions.https.HttpsError("invalid-argument", "Unsupported document file type.");
    }
    const encoded = text(entry.base64 || entry.fileBase64, MAX_DOCUMENT_BYTES * 2);
    if (!encoded || !/^[A-Za-z0-9+/]*={0,2}$/.test(encoded) || encoded.length % 4 !== 0) {
      throw new functions.https.HttpsError("invalid-argument", "Document file is invalid.");
    }
    const bytes = Buffer.from(encoded, "base64");
    if (!bytes.length || bytes.length > MAX_DOCUMENT_BYTES ||
        bytes.toString("base64") !== encoded.replace(/\s/g, "")) {
      throw new functions.https.HttpsError("invalid-argument", "Document file is too large or invalid.");
    }
    return {side, contentType, bytes, fileName: safeFileName(entry.fileName)};
  });
  const requiresSides = documentType === "driving_licence" || documentType === "identity_document";
  if (requiresSides) {
    if (files.length !== 2 || files.filter((file) => file.side === "front").length !== 1 ||
        files.filter((file) => file.side === "back").length !== 1) {
      throw new functions.https.HttpsError("invalid-argument", "Front and back document files are required.");
    }
  } else if (files.length !== 1 || files[0].side !== "primary") {
    throw new functions.https.HttpsError("invalid-argument", "One document file is required.");
  }
  return files;
}

function audit(type, rider, extra = {}) {
  return {
    type,
    riderId: rider.uid,
    actorType: "rider",
    actorId: rider.uid,
    actorEmail: rider.email,
    source: "cloud-functions",
    createdAt: FieldValue.serverTimestamp(),
    ...extra,
  };
}

function profilePatch(data, rider, existing = {}) {
  const vehicleExisting = existing.vehicle && typeof existing.vehicle === "object" ? existing.vehicle : {};
  const legalFirstName = text(data.legalFirstName || existing.legalFirstName, 80);
  const legalSurname = text(data.legalSurname || existing.legalSurname, 80);
  const fullName = text(
      data.fullName || [legalFirstName, legalSurname].filter(Boolean).join(" ") ||
      existing.fullName || existing.name || rider.name, 160);
  const phoneNumber = text(data.phoneNumber || data.phone || existing.phoneNumber || existing.phone, 60);
  const vehicleType = lower(data.vehicleType || existing.vehicleType || existing.typeOfVehicle || vehicleExisting.type, 80);
  const vehicleRegistration = text(data.vehicleRegistration || data.plateNumber || existing.vehicleRegistration || existing.plateNumber || vehicleExisting.registration || vehicleExisting.plateNumber, 40);
  const vehicle = {
    type: vehicleType,
    makeModel: text(data.vehicleMakeModel || existing.vehicleMakeModel || vehicleExisting.makeModel, 120),
    colour: text(data.vehicleColour || existing.vehicleColour || vehicleExisting.colour, 80),
    plateNumber: vehicleRegistration,
  };
  const dateOfBirth = canonicalDateOfBirth(
      data.dateOfBirth || existing.dateOfBirth);
  const vehicles = Array.isArray(data.vehicles) ? data.vehicles.slice(0, 2) : existing.vehicles;
  return {
    uid: rider.uid,
    riderId: rider.uid,
    fullName,
    legalFirstName,
    legalSurname,
    preferredName: text(data.preferredName || existing.preferredName, 120),
    phoneNumber,
    email: rider.email || text(data.email, 180),
    postcode: text(data.postcode || existing.postcode || existing.homePostcode, 40),
    dateOfBirth,
    homeAddress: text(data.homeAddress || data.address || existing.homeAddress || existing.address, 500),
    address: text(data.address || data.homeAddress || existing.address || existing.homeAddress, 500),
    emergencyContactName: text(data.emergencyContactName || existing.emergencyContactName, 160),
    emergencyContactPhone: text(data.emergencyContactPhone || existing.emergencyContactPhone, 60),
    accessibilityNeeds: text(data.accessibilityNeeds || existing.accessibilityNeeds, 1000),
    vehicleType,
    vehicleMakeModel: vehicle.makeModel,
    vehicleColour: vehicle.colour,
    plateNumber: vehicleRegistration,
    vehicleRegistration,
    vehicle,
    ...(Array.isArray(vehicles) ? {vehicles} : {}),
    availability: text(data.availability || existing.availability, 240),
    approvalStatus: existing.approvalStatus || "pending",
    onboardingStatus: existing.onboardingStatus || "not_started",
    verificationStatus: existing.verificationStatus || "pending",
    riderRank: existing.riderRank || "agent",
    trustPoints: Number.isFinite(Number(existing.trustPoints)) ? Number(existing.trustPoints) : 0,
    driverStatus: "active",
    role: "rider",
    roles: ["rider"],
    source: "cloud-functions",
    updatedAt: FieldValue.serverTimestamp(),
  };
}

function canonicalDateOfBirth(value) {
  const raw = text(value, 40);
  if (!raw) return "";
  if (!/^\d{4}-\d{2}-\d{2}$/.test(raw)) {
    throw new functions.https.HttpsError("invalid-argument", "Date of birth must use YYYY-MM-DD.");
  }
  const [year, month, day] = raw.split("-").map(Number);
  const date = new Date(Date.UTC(year, month - 1, day));
  if (date.getUTCFullYear() !== year || date.getUTCMonth() !== month - 1 ||
      date.getUTCDate() !== day) {
    throw new functions.https.HttpsError("invalid-argument", "Date of birth is not a valid date.");
  }
  const today = new Date();
  const todayUtc = Date.UTC(today.getUTCFullYear(), today.getUTCMonth(), today.getUTCDate());
  if (date.getTime() > todayUtc) {
    throw new functions.https.HttpsError("invalid-argument", "Date of birth cannot be in the future.");
  }
  let age = today.getUTCFullYear() - year;
  if (today.getUTCMonth() < month - 1 ||
      (today.getUTCMonth() === month - 1 && today.getUTCDate() < day)) age--;
  if (age < 18) {
    throw new functions.https.HttpsError("invalid-argument", "Riders must be at least 18 years old.");
  }
  return raw;
}

function riderPatch(data, rider, existing = {}) {
  const vehicles = Array.isArray(data.vehicles) ? data.vehicles.slice(0, 2) : existing.vehicles;
  return {
    name: text(data.fullName || existing.fullName || existing.name || rider.name, 160),
    legalFirstName: text(data.legalFirstName || existing.legalFirstName, 80),
    legalSurname: text(data.legalSurname || existing.legalSurname, 80),
    preferredName: text(data.preferredName || existing.preferredName, 120),
    dateOfBirth: canonicalDateOfBirth(data.dateOfBirth || existing.dateOfBirth),
    phone: text(data.phoneNumber || data.phone || existing.phoneNumber || existing.phone, 60),
    role: "delivery",
    status: text(existing.status || "offline", 40),
    rating: text(existing.rating || "0.00", 20),
    plateNumber: text(data.vehicleRegistration || data.plateNumber || existing.vehicleRegistration || existing.plateNumber, 40),
    typeOfVehicle: text(data.vehicleType || existing.vehicleType || existing.typeOfVehicle, 80),
    ...(Array.isArray(vehicles) ? {vehicles} : {}),
    vehicleMakeModel: text(data.vehicleMakeModel || existing.vehicleMakeModel, 120),
    vehicleColour: text(data.vehicleColour || existing.vehicleColour, 80),
    verificationStatus: existing.verificationStatus || "pending",
    updatedAt: FieldValue.serverTimestamp(),
  };
}

function cleanPosition(value) {
  if (!value || typeof value !== "object") return null;
  const geopoint = value.geopoint || value;
  const latitude = Number(geopoint.latitude);
  const longitude = Number(geopoint.longitude);
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude) ||
      latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
    throw new functions.https.HttpsError("invalid-argument", "A valid location is required.");
  }
  return {
    geohash: text(value.geohash, 32),
    geopoint: {latitude, longitude},
  };
}

function nextOnboardingStatus(current, requested) {
  const normalizedCurrent = lower(current || "not_started", 80);
  const normalizedRequested = lower(requested, 80);
  if (!ONBOARDING_TRANSITIONS.has(normalizedCurrent) ||
      !ONBOARDING_TRANSITIONS.get(normalizedCurrent).has(normalizedRequested)) {
    throw new functions.https.HttpsError("failed-precondition", "Invalid Rider onboarding transition.");
  }
  return normalizedRequested;
}

exports.advanceRiderOnboarding = riderCallable(async (data, context) => {
  const rider = requireRider(context);
  const requestedStage = lower(data && data.stage, 80);
  const db = getFirestore();
  const riderRef = db.collection("riders").doc(rider.uid);
  const profileRef = db.collection("riderProfiles").doc(rider.uid);
  const eventRef = db.collection("riderOnboardingEvents").doc();
  let result;

  await db.runTransaction(async (transaction) => {
    const [riderSnap, profileSnap] = await Promise.all([
      transaction.get(riderRef),
      transaction.get(profileRef),
    ]);
    const existing = {...(profileSnap.data() || {}), ...(riderSnap.data() || {})};
    const onboardingStatus = nextOnboardingStatus(existing.onboardingStatus, requestedStage);
    const patch = {
      onboardingStatus,
      profileCompletionStatus: onboardingStatus === "profile_complete" ? "complete" : existing.profileCompletionStatus || "started",
      updatedAt: FieldValue.serverTimestamp(),
    };

    if (onboardingStatus === "profile_complete" && !existing.approvalStatus) {
      Object.assign(patch, {
        role: "rider",
        roles: ["rider"],
        approvalStatus: "pending",
        verificationStatus: "verification_pending",
        driverStatus: "offline",
        riderRank: "agent",
        rating: "0.0",
      });
    }

    if (onboardingStatus === "phone_verified") {
      const phone = context.auth.token.phone_number;
      if (!phone) throw new functions.https.HttpsError("failed-precondition", "Phone verification is required.");
      patch.phone = phone;
      patch.phoneVerified = true;
      patch.phoneVerifiedAt = FieldValue.serverTimestamp();
    }
    if (onboardingStatus === "email_verified") {
      if (context.auth.token.email_verified !== true) {
        throw new functions.https.HttpsError("failed-precondition", "Email verification is required.");
      }
      patch.emailVerified = true;
      patch.emailVerifiedAt = FieldValue.serverTimestamp();
    }
    if (data && data.name) patch.name = text(data.name, 160);
    if (data && data.locationEnabled === true) patch.locationEnabled = true;
    if (data && data.position) patch.position = cleanPosition(data.position);

    transaction.set(riderRef, patch, {merge: true});
    transaction.set(profileRef, patch, {merge: true});
    transaction.set(eventRef, audit("rider_onboarding_advanced", rider, {
      statusAfterEvent: onboardingStatus,
      changedFields: Object.keys(patch).filter((field) => field !== "updatedAt"),
    }));
    result = {onboardingStatus};
  });
  return {ok: true, riderId: rider.uid, ...result};
});

function applicationPatchFromProfile(data, rider, profile) {
  const section = data.section ? cleanApplicationSection(data.section) : null;
  const now = FieldValue.serverTimestamp();
  return {
    id: rider.uid,
    riderId: rider.uid,
    fullName: profile.fullName,
    legalFirstName: profile.legalFirstName,
    legalSurname: profile.legalSurname,
    preferredName: profile.preferredName,
    phoneNumber: profile.phoneNumber,
    email: profile.email,
    postcode: profile.postcode,
    homeAddress: profile.homeAddress,
    address: profile.address,
    dateOfBirth: profile.dateOfBirth,
    emergencyContactName: profile.emergencyContactName,
    emergencyContactPhone: profile.emergencyContactPhone,
    accessibilityNeeds: profile.accessibilityNeeds,
    vehicleType: profile.vehicleType,
    vehicleRegistration: profile.vehicleRegistration,
    vehicle: profile.vehicle,
    availability: profile.availability,
    source: "cloud-functions",
    updatedAt: now,
    ...(section ? {sectionStatus: {[section]: "submitted"}} : {}),
  };
}

exports.updateRiderProfile = riderCallable(async (data, context) => {
  const rider = requireRider(context);
  const db = getFirestore();
  const profileRef = db.collection("riderProfiles").doc(rider.uid);
  const riderRef = db.collection("riders").doc(rider.uid);
  const applicationRef = db.collection("riderApplications").doc(rider.uid);
  const metricsRef = db.collection("driverPerformanceMetrics").doc(rider.uid);
  const eventRef = db.collection("riderOnboardingEvents").doc();

  await db.runTransaction(async (transaction) => {
    const [profileSnap, riderSnap, applicationSnap, metricsSnap] = await Promise.all([
      transaction.get(profileRef),
      transaction.get(riderRef),
      transaction.get(applicationRef),
      transaction.get(metricsRef),
    ]);
    const existing = {
      ...(riderSnap.data() || {}),
      ...(profileSnap.data() || {}),
    };
    const profile = profilePatch(data || {}, rider, existing);
    const riderData = riderPatch(data || {}, rider, profile);
    transaction.set(profileRef, {
      ...profile,
      ...(profileSnap.exists ? {} : {createdAt: FieldValue.serverTimestamp()}),
    }, {merge: true});
    transaction.set(riderRef, riderData, {merge: true});
    transaction.set(applicationRef, {
      ...applicationPatchFromProfile(data || {}, rider, profile),
      ...(applicationSnap.exists ? {} : {createdAt: FieldValue.serverTimestamp()}),
    }, {merge: true});
    if (!metricsSnap.exists) {
      transaction.set(metricsRef, {
        riderId: rider.uid,
        completedDeliveries: 0,
        cancelledDeliveries: 0,
        averageRating: 0,
        onTimeRate: 0,
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    } else {
      transaction.set(metricsRef, {
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    }
    transaction.set(eventRef, audit("rider_profile_updated", rider, {
      changedFields: ["fullName", "phoneNumber", "vehicleType", "vehicleRegistration"],
    }));
  });

  return {ok: true, riderId: rider.uid};
});

exports.ensurePublicRiderId = riderCallable(async (data, context) => {
  const rider = requireRider(context);
  const db = getFirestore();
  const riderRef = db.collection("riders").doc(rider.uid);
  const profileRef = db.collection("riderProfiles").doc(rider.uid);

  for (let attempt = 0; attempt < 5; attempt += 1) {
    const candidate = newPublicRiderId();
    const reservationRef = db.collection("publicRiderIds").doc(candidate);
    try {
      return await db.runTransaction(async (transaction) => {
        const [riderSnap, profileSnap, reservationSnap] = await Promise.all([
          transaction.get(riderRef),
          transaction.get(profileRef),
          transaction.get(reservationRef),
        ]);
        const existing = text(
            (profileSnap.data() || {}).publicRiderId ||
            (riderSnap.data() || {}).publicRiderId,
            40,
        );
        if (existing) return {ok: true, publicRiderId: existing, created: false};
        if (reservationSnap.exists) throw new Error("public-rider-id-collision");
        const now = FieldValue.serverTimestamp();
        transaction.create(reservationRef, {riderId: rider.uid, createdAt: now});
        transaction.set(riderRef, {publicRiderId: candidate, updatedAt: now}, {merge: true});
        transaction.set(profileRef, {publicRiderId: candidate, updatedAt: now}, {merge: true});
        return {ok: true, publicRiderId: candidate, created: true};
      });
    } catch (error) {
      if (error.message === "public-rider-id-collision") continue;
      throw error;
    }
  }
  throw new functions.https.HttpsError(
      "internal",
      "Your Rider ID could not be prepared. Please try again.",
  );
});

exports.requestRiderEmailChange = riderCallable(async (data, context) => {
  const rider = requireRider(context);
  const pendingEmail = lower(data.pendingEmail || data.email, 180);
  if (!pendingEmail || !pendingEmail.includes("@")) {
    throw new functions.https.HttpsError("invalid-argument", "A valid email is required.");
  }
  const db = getFirestore();
  const profileRef = db.collection("riderProfiles").doc(rider.uid);
  const eventRef = db.collection("riderOnboardingEvents").doc();

  await db.runTransaction(async (transaction) => {
    transaction.set(profileRef, {
      pendingEmail,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    transaction.set(eventRef, audit("rider_email_change_requested", rider, {
      pendingEmail,
    }));
  });

  return {ok: true, riderId: rider.uid};
});

exports.updateRiderPushToken = riderCallable(async (data, context) => {
  const rider = requireRider(context);
  const fcmToken = text(data.fcmToken, 4096);
  if (!fcmToken) {
    throw new functions.https.HttpsError("invalid-argument", "Push token is required.");
  }
  const db = getFirestore();
  const now = FieldValue.serverTimestamp();
  await db.runTransaction(async (transaction) => {
    transaction.set(db.collection("riderProfiles").doc(rider.uid), {
      fcmToken,
      notificationTokenUpdatedAt: now,
      updatedAt: now,
    }, {merge: true});
    transaction.set(db.collection("riderOnboardingEvents").doc(), audit("rider_push_token_updated", rider));
  });
  return {ok: true};
});

exports.updateRiderNotificationState = riderCallable(async (data, context) => {
  const rider = requireRider(context);
  const action = lower(data.action, 40);
  const ids = normalizeNotificationIds(data.notificationIds || data.notificationId);
  if (!ids.length) {
    throw new functions.https.HttpsError("invalid-argument", "Notification id is required.");
  }
  const allowed = new Set(["mark_read", "archive", "delete"]);
  if (!allowed.has(action)) {
    throw new functions.https.HttpsError("invalid-argument", "Unsupported notification action.");
  }
  const db = getFirestore();
  const now = FieldValue.serverTimestamp();
  await db.runTransaction(async (transaction) => {
    const refs = ids.map((id) => db.collection("notifications").doc(id));
    const snaps = await Promise.all(refs.map((ref) => transaction.get(ref)));
    snaps.forEach((snap, index) => {
      if (!snap.exists) {
        throw new functions.https.HttpsError("not-found", "Notification not found.");
      }
      const notification = snap.data() || {};
      const recipient = text(notification.recipientId || notification.riderId, 180);
      const recipientRole = lower(notification.recipientRole || notification.role, 80);
      if (recipient !== rider.uid || (recipientRole && recipientRole !== "rider")) {
        throw new functions.https.HttpsError("permission-denied", "Notification does not belong to this Rider.");
      }
      const patch = action === "mark_read" ?
        {read: true, isRead: true, readAt: now} :
        action === "archive" ?
          {archived: true, archivedAt: now} :
          {deletedAt: now};
      transaction.set(refs[index], patch, {merge: true});
    });
    transaction.set(db.collection("riderNotificationEvents").doc(), audit("rider_notification_state_updated", rider, {
      action,
      notificationIds: ids,
    }));
  });
  return {ok: true, notificationIds: ids, action};
});

exports.recordRiderJobDecision = riderCallable(async (data, context) => {
  const rider = requireRider(context);
  const requestId = text(data.requestId || data.deliveryId, 180);
  const action = lower(data.action, 40);
  if (!requestId || !["reject", "ignore"].includes(action)) {
    throw new functions.https.HttpsError("invalid-argument", "A valid Rider job decision is required.");
  }
  const db = getFirestore();
  const deliveryRef = db.collection("deliveryRequests").doc(requestId);
  const now = FieldValue.serverTimestamp();
  await db.runTransaction(async (transaction) => {
    const snap = await transaction.get(deliveryRef);
    if (!snap.exists) {
      throw new functions.https.HttpsError("not-found", "Delivery request not found.");
    }
    const data = snap.data() || {};
    const assignedRider = text(data.riderId || data.driverId || data.assignedDriverId, 180);
    if (assignedRider && assignedRider !== rider.uid) {
      throw new functions.https.HttpsError("permission-denied", "Delivery is assigned to another Rider.");
    }
    const field = action === "reject" ? "rejectedByRiders" : "ignoredByRiders";
    const timestampField = action === "reject" ? "rejectedAt" : "ignoredAt";
    transaction.set(deliveryRef, {
      [field]: FieldValue.arrayUnion(rider.uid),
      [timestampField]: now,
      updatedAt: now,
    }, {merge: true});
    transaction.set(db.collection("riderOnboardingEvents").doc(), audit("rider_job_decision_recorded", rider, {
      requestId,
      action,
    }));
  });
  return {ok: true, requestId, action};
});

exports.ensureRiderRothWallet = riderCallable(async (data, context) => {
  const rider = requireRider(context);
  const requestedRiderId = text(data.riderId, 180);
  if (requestedRiderId && requestedRiderId !== rider.uid) {
    throw new functions.https.HttpsError("permission-denied", "Rider wallet access denied.");
  }
  const db = getFirestore();
  const riderRef = db.collection("riders").doc(rider.uid);
  const walletRef = db.collection("riderRothWallets").doc(rider.uid);
  const result = await db.runTransaction(async (transaction) => {
    const wallet = await transaction.get(walletRef);
    const now = FieldValue.serverTimestamp();
    if (wallet.exists) {
      transaction.set(riderRef, {
        rothOnboardingComplete: true,
        rothOnboardingStatus: "connected",
        rothWalletId: walletRef.id,
        rothWalletConnectedAt: now,
        updatedAt: now,
      }, {merge: true});
      transaction.set(db.collection("riderOnboardingEvents").doc(), audit("roth_wallet_connected", rider, {
        walletId: walletRef.id,
        statusAfterEvent: "connected",
      }));
      return {walletCreated: false, walletExisted: true};
    }
    transaction.set(walletRef, {
      riderId: rider.uid,
      email: rider.email || text(data.email, 180) || null,
      currency: "ROTH",
      balance: 0,
      available: 0,
      pending: 0,
      status: "active",
      createdAt: now,
      updatedAt: now,
      source: "ensureRiderRothWallet",
    });
    transaction.set(riderRef, {
      rothOnboardingComplete: true,
      rothOnboardingStatus: "wallet_created",
      rothWalletId: walletRef.id,
      rothWalletConnectedAt: now,
      updatedAt: now,
    }, {merge: true});
    transaction.set(db.collection("riderOnboardingEvents").doc(), audit("roth_wallet_created", rider, {
      walletId: walletRef.id,
      statusAfterEvent: "wallet_created",
    }));
    return {walletCreated: true, walletExisted: false};
  });
  return {ok: true, ...result};
});

exports.createWeightAdjustedNotification = riderCallable(async (data, context) => {
  const rider = requireRider(context);
  const requestId = text(data.requestId, 180);
  if (!requestId) {
    throw new functions.https.HttpsError("invalid-argument", "Delivery request is required.");
  }
  const db = getFirestore();
  const deliveryRef = db.collection("deliveryRequests").doc(requestId);
  const notificationRef = db.collection("notifications").doc();
  const eventRef = db.collection("riderOnboardingEvents").doc();

  await db.runTransaction(async (transaction) => {
    const deliverySnap = await transaction.get(deliveryRef);
    if (!deliverySnap.exists) {
      throw new functions.https.HttpsError("not-found", "Delivery request not found.");
    }
    const delivery = deliverySnap.data() || {};
    const assignedRider = text(
        delivery.riderId || delivery.driverId || delivery.assignedDriverId,
        180,
    );
    if (assignedRider !== rider.uid) {
      throw new functions.https.HttpsError("permission-denied", "Delivery is not assigned to this Rider.");
    }
    const recipientId = text(delivery.senderId || delivery.userId, 180);
    if (!recipientId) {
      throw new functions.https.HttpsError("failed-precondition", "Delivery has no Sender recipient.");
    }
    transaction.set(notificationRef, {
      recipientId,
      requestId,
      type: "weight_adjusted",
      title: "Parcel weight updated",
      message: "Parcel weight differs from original declaration. Pricing has been adjusted.",
      createdAt: FieldValue.serverTimestamp(),
      read: false,
      source: "createWeightAdjustedNotification",
    });
    transaction.set(eventRef, audit("rider_weight_adjustment_notified", rider, {
      requestId,
      recipientId,
      notificationId: notificationRef.id,
    }));
  });

  return {ok: true, notificationId: notificationRef.id};
});

exports.submitRiderApplication = riderCallable(async (data, context) => {
  const rider = requireRider(context);
  const db = getFirestore();
  const idempotencyKey = text(data.idempotencyKey, 180) || `rider_application_${rider.uid}`;
  const idempotencyRef = db.collection("riderApplicationIdempotency").doc(idempotencyKey.replace(/[/.#[\]]/g, "_"));
  const applicationRef = db.collection("riderApplications").doc(rider.uid);
  const riderRef = db.collection("riders").doc(rider.uid);
  const profileRef = db.collection("riderProfiles").doc(rider.uid);
  const eventRef = db.collection("riderOnboardingEvents").doc();

  const result = await db.runTransaction(async (transaction) => {
    const replay = await transaction.get(idempotencyRef);
    if (replay.exists) return {...replay.data(), idempotent: true};
    const [riderSnap, profileSnap, applicationSnap] = await Promise.all([
      transaction.get(riderRef),
      transaction.get(profileRef),
      transaction.get(applicationRef),
    ]);
    const riderData = riderSnap.data() || {};
    const profileData = profileSnap.data() || {};
    const applicationData = applicationSnap.data() || {};
    const existing = {...riderData, ...profileData, ...applicationData};
    const vehicle = existing.vehicle && typeof existing.vehicle === "object" ? existing.vehicle : {};

    const now = FieldValue.serverTimestamp();
    const application = {
      id: applicationRef.id,
      riderId: rider.uid,
      fullName: text(data.fullName || existing.fullName || existing.name || rider.name, 160),
      phoneNumber: text(data.phoneNumber || existing.phoneNumber || existing.phone, 60),
      email: rider.email || text(data.email || existing.email, 180),
      postcode: text(data.postcode || existing.postcode || existing.homePostcode, 40),
      homeAddress: text(data.homeAddress || data.address || existing.homeAddress || existing.address, 500),
      address: text(data.address || data.homeAddress || existing.address || existing.homeAddress, 500),
      dateOfBirth: text(data.dateOfBirth || existing.dateOfBirth, 40),
      emergencyContactName: text(data.emergencyContactName || existing.emergencyContactName, 160),
      emergencyContactPhone: text(data.emergencyContactPhone || existing.emergencyContactPhone, 60),
      accessibilityNeeds: text(data.accessibilityNeeds || existing.accessibilityNeeds, 1000),
      vehicleType: lower(data.vehicleType || existing.vehicleType || vehicle.type, 80),
      vehicleRegistration: text(data.vehicleRegistration || data.plateNumber || existing.vehicleRegistration || existing.plateNumber || vehicle.registration, 40),
      vehicle,
      availability: text(data.availability || existing.availability, 240),
      notes: text(data.notes, 1000),
      rightToWorkConfirmed: data.rightToWorkConfirmed === undefined ?
        existing.rightToWorkConfirmed === true : data.rightToWorkConfirmed === true,
      sealedPackageConsent: data.sealedPackageConsent === undefined ?
        existing.sealedPackageConsent === true : data.sealedPackageConsent === true,
      status: "submitted",
      source: "cloud-functions",
      updatedAt: now,
    };
    transaction.set(applicationRef, {
      ...application,
      ...(existing.sectionStatus ? {sectionStatus: existing.sectionStatus} : {}),
      ...(applicationSnap.exists ? {} : {createdAt: now}),
    }, {merge: true});
    transaction.set(profileRef, {
      fullName: application.fullName,
      email: application.email,
      phoneNumber: application.phoneNumber,
      vehicleType: application.vehicleType,
      vehicleRegistration: text(data.vehicleRegistration || data.plateNumber || existing.vehicleRegistration || existing.plateNumber || vehicle.registration, 40),
      onboardingStatus: "pending_review",
      approvalStatus: "pending",
      verificationStatus: "pending",
      riderRank: "agent",
      trustPoints: 0,
      onboardingSubmittedAt: now,
      termsAcceptedAt: now,
      updatedAt: now,
    }, {merge: true});
    transaction.set(eventRef, audit("rider_application_submitted", rider, {
      applicationId: applicationRef.id,
      status: "submitted",
    }));
    transaction.set(idempotencyRef, {
      applicationId: applicationRef.id,
      riderId: rider.uid,
      status: "submitted",
      createdAt: now,
    }, {merge: true});
    return {applicationId: applicationRef.id, status: "submitted", idempotent: false};
  });

  return result;
});

exports.updateRiderApplicationSection = riderCallable(async (data, context) => {
  const rider = requireRider(context);
  const section = cleanApplicationSection(data.section);
  const status = cleanSectionStatus(data.status || "in_progress");
  const db = getFirestore();
  const applicationRef = db.collection("riderApplications").doc(rider.uid);
  const eventRef = db.collection("riderOnboardingEvents").doc();
  const now = FieldValue.serverTimestamp();
  await db.runTransaction(async (transaction) => {
    const applicationSnap = await transaction.get(applicationRef);
    const existing = applicationSnap.data() || {};
    const currentStatus = text(existing.status);
    transaction.set(applicationRef, {
      id: rider.uid,
      riderId: rider.uid,
      email: rider.email,
      sectionStatus: {
        [section]: status,
      },
      status: currentStatus || (status === "needs_attention" ? "needs_information" : "draft"),
      source: "cloud-functions",
      updatedAt: now,
      ...(!applicationSnap.exists ? {createdAt: now} : {}),
    }, {merge: true});
    transaction.set(eventRef, audit("rider_application_section_updated", rider, {
      applicationId: rider.uid,
      section,
      status,
    }));
  });
  return {ok: true, applicationId: rider.uid, section, status};
});

exports.submitRiderDocument = riderCallable(async (data, context) => {
  const rider = requireRider(context);
  const documentType = cleanDocumentType(data.documentType || data.type);
  const files = normalizeRiderDocumentFiles(data, documentType);
  const idempotencyKey = text(data.idempotencyKey, 120);
  if (idempotencyKey && !/^[A-Za-z0-9_-]{8,120}$/.test(idempotencyKey)) {
    throw new functions.https.HttpsError("invalid-argument", "A valid upload request key is required.");
  }

  const db = getFirestore();
  const documentRef = idempotencyKey ? db.collection("riderDocuments").doc(
      crypto.createHash("sha256").update(`${rider.uid}:${idempotencyKey}`).digest("hex"),
  ) : db.collection("riderDocuments").doc();
  const existing = idempotencyKey ? await documentRef.get() : null;
  if (existing && existing.exists) {
    const record = existing.data() || {};
    if (record.riderId !== rider.uid || record.type !== documentType) {
      throw new functions.https.HttpsError("already-exists", "This upload request key is already in use.");
    }
    return {
      ok: true,
      documentId: documentRef.id,
      storagePath: record.storagePath,
      downloadUrl: record.downloadUrl,
      attachments: record.attachments || {},
      idempotentReplay: true,
    };
  }
  const uploaded = [];
  try {
    for (const attachment of files) {
      const storagePath = `rider_documents/${rider.uid}/${Date.now()}_${documentRef.id}_${attachment.side}_${attachment.fileName}`;
      const file = getStorage().bucket().file(storagePath);
      await file.save(attachment.bytes, {
        metadata: {
          contentType: attachment.contentType,
          metadata: {riderId: rider.uid, documentType, side: attachment.side, source: "submitRiderDocument"},
        },
        resumable: false,
      });
      const [signedUrl] = await file.getSignedUrl({action: "read", expires: Date.now() + 1000 * 60 * 60 * 24 * 7});
      uploaded.push({...attachment, storagePath, signedUrl});
    }

    const primary = uploaded.find((file) => file.side === "primary") || uploaded[0];
    const attachments = Object.fromEntries(uploaded.map((file) => [file.side, {
      storagePath: file.storagePath,
      fileUrl: file.signedUrl,
      downloadUrl: file.signedUrl,
      mimeType: file.contentType,
      sizeBytes: file.bytes.length,
    }]));
    const now = FieldValue.serverTimestamp();
    await db.runTransaction(async (transaction) => {
      transaction.set(documentRef, {
        documentId: documentRef.id,
        ...(idempotencyKey ? {idempotencyKey} : {}),
        riderId: rider.uid,
        riderEmail: rider.email,
        type: documentType,
        notes: text(data.notes, 1000),
        ...(primary ? {fileName: primary.fileName, storagePath: primary.storagePath, downloadUrl: primary.signedUrl, fileUrl: primary.signedUrl, contentType: primary.contentType, sizeBytes: primary.bytes.length} : {}),
        attachments,
        uploadedAt: now,
        status: "pending",
        verificationStatus: "pending",
        source: "cloud-functions",
        createdAt: now,
        updatedAt: now,
      });
      transaction.set(db.collection("riderProfiles").doc(rider.uid), {
        verificationStatus: "pending",
        verificationDocuments: {[documentType]: {type: documentType, ...(primary ? {fileUrl: primary.signedUrl, storagePath: primary.storagePath} : {}), attachments, uploadedAt: new Date().toISOString(), status: "pending"}},
        lastDocumentUploadedAt: now,
        updatedAt: now,
      }, {merge: true});
      transaction.set(db.collection("riderOnboardingEvents").doc(), audit("rider_document_uploaded", rider, {
        documentId: documentRef.id, documentType, storagePaths: uploaded.map((file) => file.storagePath),
      }));
    });
  } catch (error) {
    await Promise.all(uploaded.map((file) => getStorage().bucket().file(file.storagePath).delete().catch(() => null)));
    throw error;
  }
  const primary = uploaded.find((file) => file.side === "primary") || uploaded[0];
  return {ok: true, documentId: documentRef.id, storagePath: primary.storagePath, downloadUrl: primary.signedUrl, attachments: Object.fromEntries(uploaded.map((file) => [file.side, {storagePath: file.storagePath, downloadUrl: file.signedUrl}]))};
});

exports._test = {newPublicRiderId};
