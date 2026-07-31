/* eslint-disable max-len, require-jsdoc */
const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {getStorage} = require("firebase-admin/storage");
const {canonicalDocumentId, DOCUMENT_MATRIX} = require("./rider-certification-policy");

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
  const fullName = text(data.fullName || existing.fullName || existing.name || rider.name, 160);
  const phoneNumber = text(data.phoneNumber || data.phone || existing.phoneNumber || existing.phone, 60);
  const vehicleType = lower(data.vehicleType || existing.vehicleType || existing.typeOfVehicle || vehicleExisting.type, 80);
  const vehicleRegistration = text(data.vehicleRegistration || data.plateNumber || existing.vehicleRegistration || existing.plateNumber || vehicleExisting.registration || vehicleExisting.plateNumber, 40);
  const vehicle = {
    type: vehicleType,
    makeModel: text(data.vehicleMakeModel || existing.vehicleMakeModel || vehicleExisting.makeModel, 120),
    colour: text(data.vehicleColour || existing.vehicleColour || vehicleExisting.colour, 80),
    plateNumber: vehicleRegistration,
  };
  return {
    uid: rider.uid,
    riderId: rider.uid,
    fullName,
    phoneNumber,
    email: rider.email || text(data.email, 180),
    postcode: text(data.postcode || existing.postcode || existing.homePostcode, 40),
    dateOfBirth: text(data.dateOfBirth || existing.dateOfBirth, 40),
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
    availability: text(data.availability || existing.availability, 240),
    approvalStatus: existing.approvalStatus || "pending",
    onboardingStatus: existing.onboardingStatus || "not_started",
    verificationStatus: existing.verificationStatus || "pending",
    riderRank: "agent",
    trustPoints: 0,
    driverStatus: "active",
    role: "rider",
    roles: ["rider"],
    source: "cloud-functions",
    updatedAt: FieldValue.serverTimestamp(),
  };
}

function riderPatch(data, rider, existing = {}) {
  return {
    name: text(data.fullName || existing.fullName || existing.name || rider.name, 160),
    phone: text(data.phoneNumber || data.phone || existing.phoneNumber || existing.phone, 60),
    role: "delivery",
    status: text(existing.status || "offline", 40),
    rating: text(existing.rating || "0.00", 20),
    plateNumber: text(data.vehicleRegistration || data.plateNumber || existing.vehicleRegistration || existing.plateNumber, 40),
    typeOfVehicle: text(data.vehicleType || existing.vehicleType || existing.typeOfVehicle, 80),
    vehicleMakeModel: text(data.vehicleMakeModel || existing.vehicleMakeModel, 120),
    vehicleColour: text(data.vehicleColour || existing.vehicleColour, 80),
    verificationStatus: existing.verificationStatus || "pending",
    updatedAt: FieldValue.serverTimestamp(),
  };
}

function applicationPatchFromProfile(data, rider, profile) {
  const section = data.section ? cleanApplicationSection(data.section) : null;
  const now = FieldValue.serverTimestamp();
  return {
    id: rider.uid,
    riderId: rider.uid,
    fullName: profile.fullName,
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

exports.updateRiderProfile = functions.https.onCall(async (data, context) => {
  const rider = requireRider(context);
  const db = getFirestore();
  const profileRef = db.collection("riderProfiles").doc(rider.uid);
  const riderRef = db.collection("riders").doc(rider.uid);
  const applicationRef = db.collection("riderApplications").doc(rider.uid);
  const metricsRef = db.collection("driverPerformanceMetrics").doc(rider.uid);
  const eventRef = db.collection("riderOnboardingEvents").doc();

  await db.runTransaction(async (transaction) => {
    const [profileSnap, riderSnap, applicationSnap] = await Promise.all([
      transaction.get(profileRef),
      transaction.get(riderRef),
      transaction.get(applicationRef),
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
    transaction.set(metricsRef, {
      riderId: rider.uid,
      completedDeliveries: 0,
      cancelledDeliveries: 0,
      averageRating: 0,
      onTimeRate: 0,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    transaction.set(eventRef, audit("rider_profile_updated", rider, {
      changedFields: ["fullName", "phoneNumber", "vehicleType", "vehicleRegistration"],
    }));
  });

  return {ok: true, riderId: rider.uid};
});

exports.requestRiderEmailChange = functions.https.onCall(async (data, context) => {
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

exports.updateRiderPushToken = functions.https.onCall(async (data, context) => {
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

exports.updateRiderNotificationState = functions.https.onCall(async (data, context) => {
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

exports.recordRiderJobDecision = functions.https.onCall(async (data, context) => {
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

exports.ensureRiderRothWallet = functions.https.onCall(async (data, context) => {
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

exports.createWeightAdjustedNotification = functions.https.onCall(async (data, context) => {
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

exports.submitRiderApplication = functions.https.onCall(async (data, context) => {
  const rider = requireRider(context);
  if (data.rightToWorkConfirmed !== true || data.sealedPackageConsent !== true) {
    throw new functions.https.HttpsError("failed-precondition", "Rider confirmations are required.");
  }
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
      rightToWorkConfirmed: true,
      sealedPackageConsent: true,
      status: "submitted",
      source: "cloud-functions",
      updatedAt: now,
    };
    if (!application.fullName || !application.phoneNumber || !application.vehicleType) {
      throw new functions.https.HttpsError("invalid-argument", "Name, phone and vehicle type are required.");
    }
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

exports.updateRiderApplicationSection = functions.https.onCall(async (data, context) => {
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

exports.submitRiderDocument = functions.https.onCall(async (data, context) => {
  const rider = requireRider(context);
  const documentType = cleanDocumentType(data.documentType || data.type);
  const contentType = text(data.contentType, 120).toLowerCase();
  if (!ALLOWED_CONTENT_TYPES.has(contentType)) {
    throw new functions.https.HttpsError("invalid-argument", "Unsupported document file type.");
  }
  const fileBase64 = text(data.fileBase64, MAX_DOCUMENT_BYTES * 2);
  if (!fileBase64) {
    throw new functions.https.HttpsError("invalid-argument", "Document file is required.");
  }
  const bytes = Buffer.from(fileBase64, "base64");
  if (!bytes.length || bytes.length > MAX_DOCUMENT_BYTES) {
    throw new functions.https.HttpsError("invalid-argument", "Document file is too large.");
  }

  const db = getFirestore();
  const documentRef = db.collection("riderDocuments").doc();
  const fileName = safeFileName(data.fileName);
  const storagePath = `rider_documents/${rider.uid}/${Date.now()}_${documentRef.id}_${fileName}`;
  await getStorage().bucket().file(storagePath).save(bytes, {
    metadata: {
      contentType,
      metadata: {
        riderId: rider.uid,
        documentType,
        source: "submitRiderDocument",
      },
    },
    resumable: false,
  });

  const file = getStorage().bucket().file(storagePath);
  const [signedUrl] = await file.getSignedUrl({
    action: "read",
    expires: Date.now() + 1000 * 60 * 60 * 24 * 7,
  });

  const now = FieldValue.serverTimestamp();
  await db.runTransaction(async (transaction) => {
    transaction.set(documentRef, {
      documentId: documentRef.id,
      riderId: rider.uid,
      riderEmail: rider.email,
      type: documentType,
      notes: text(data.notes, 1000),
      fileName,
      storagePath,
      downloadUrl: signedUrl,
      fileUrl: signedUrl,
      contentType,
      sizeBytes: bytes.length,
      uploadedAt: now,
      status: "pending",
      verificationStatus: "pending",
      source: "cloud-functions",
      createdAt: now,
      updatedAt: now,
    });
    transaction.set(db.collection("riderProfiles").doc(rider.uid), {
      verificationStatus: "pending",
      verificationDocuments: {
        [documentType]: {
          type: documentType,
          fileUrl: signedUrl,
          storagePath,
          uploadedAt: new Date().toISOString(),
          status: "pending",
        },
      },
      lastDocumentUploadedAt: now,
      updatedAt: now,
    }, {merge: true});
    transaction.set(db.collection("riderOnboardingEvents").doc(), audit("rider_document_uploaded", rider, {
      documentId: documentRef.id,
      documentType,
      storagePath,
    }));
  });

  return {ok: true, documentId: documentRef.id, storagePath, downloadUrl: signedUrl};
});
