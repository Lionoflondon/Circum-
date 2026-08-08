/* eslint-disable max-len, require-jsdoc */
"use strict";

const functions = require("firebase-functions/v1");
const crypto = require("crypto");
const {getFirestore, FieldValue, GeoPoint, Timestamp} = require("firebase-admin/firestore");
const {calculateWalletCheckout, roundMoney, minorUnits} = require("./wallet-core");
const {verifiedStripePaidGbpSession} = require("./roth-ledger-core");
const vanguardProtocol = require("./vanguard-protocol-core");
const {classifyIris, normalDispatchEligibilityForInput} = require("./iris-core");
const {verifiedPhotoAnalysis} = require("./iris-photo-analysis");
const {dispatchDeliveryRequest} = require("./send-package");
const {evaluateRoadCharges, ROAD_CHARGE_POLICY_VERSION} = require("./road-charges-core");
const {authoritativeRoadRouteFacts} = require("./road-charge-route-provider");

const BASE_FARE_GBP = 5;
const ADDITIONAL_FARE_PER_MILE_GBP = 1.5;
const SHORT_TRIP_FARE_FLOOR_MILES = 1.6;
const LONG_DISTANCE_THRESHOLD_MILES = 20;
const LONG_DISTANCE_MULTIPLIER = 1.2;
const EXPRESS_SURCHARGE_GBP = 5;
const VANGUARD_ADD_ON_GBP = 1.99;
const VEHICLE_SURCHARGES_GBP = {
  motorbike: 0,
  car: 2,
  van: 10,
};
const RIDER_DELIVERY_FARE_SHARE = 0.65;
const PLATFORM_DELIVERY_FARE_SHARE = 0.35;
const DRAFT_SCHEMA_VERSION = 1;
const DRAFT_RETENTION_DAYS = 30;
const DRAFT_INACTIVITY_MINUTES = 10;
const QUOTE_SCHEMA_VERSION = 2;
const QUOTE_RETENTION_MINUTES = 30;
const METERS_PER_MILE = 1609.344;
const MAX_DRAFT_BYTES = 32768;
const MAX_STRING_LENGTH = 1000;
const MAX_DEPTH = 6;
const ALLOWED_STEPS = new Set(["pickup", "dropoff", "recipient", "deliveryTime", "parcel", "iris", "options", "review", "payment"]);
const ALLOWED_TIMING_TYPES = new Set(["now", "scheduled"]);
const ALLOWED_OPTIONS = new Set(["Standard", "Express", "standard", "express"]);
const LEGACY_ALLOWED_OPTIONS = new Set(["Economy", "economy"]);
const FORBIDDEN_DRAFT_KEYS = [
  "cardnumber", "card_number", "cvc", "cvv", "securitycode", "password",
  "token", "authtoken", "accesstoken", "refreshtoken", "clientsecret",
  "client_secret", "paymentpayload", "applepay", "googlepay", "pin",
  "verificationpin", "receiverpin", "senderpin", "rawmedia", "base64",
  "blob", "bytes", "debug", "internal", "functionresponse",
];

function requireSender(context) {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Sign in to continue booking.");
  }
  return {
    uid: context.auth.uid,
    email: context.auth.token.email || "",
    name: context.auth.token.name || "",
  };
}

function assignedRiderId(delivery = {}) {
  return text(delivery.riderId || delivery.driverId || delivery.assignedRider ||
    delivery.assignedRiderId || delivery.assignedDriverId || delivery.courierId);
}

function hasCollectionProof(delivery = {}) {
  return delivery.collectionConfirmed === true ||
    delivery.collectionPinVerified === true ||
    delivery.pickupVerified === true ||
    delivery.parcelCollected === true ||
    Boolean(delivery.collectedAt || delivery.collectionConfirmedAt ||
      delivery.pickupCompletedAt || delivery.pickupVerifiedAt ||
      delivery.collectionTimestamp);
}

function text(value) {
  return `${value || ""}`.trim();
}

function money(value) {
  return roundMoney(Number(value || 0));
}

function finiteNumber(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function canonicalHashValue(value) {
  if (value === undefined || value === null) return null;
  if (Array.isArray(value)) return value.map(canonicalHashValue);
  if (typeof value === "object") {
    return Object.keys(value).sort().reduce((result, key) => {
      const normalized = canonicalHashValue(value[key]);
      if (normalized !== undefined) result[key] = normalized;
      return result;
    }, {});
  }
  if (typeof value === "number") return Number.isFinite(value) ? value : null;
  return value;
}

function canonicalQuoteHash(snapshot) {
  return crypto.createHash("sha256")
      .update(JSON.stringify(canonicalHashValue(snapshot)))
      .digest("hex");
}

function coordinateSnapshot(value = {}) {
  const source = cleanMap(value);
  const latitude = finiteNumber(source.latitude ?? source.lat);
  const longitude = finiteNumber(source.longitude ?? source.lng ?? source.lon);
  return {
    placeId: cleanString(source.placeId || source.providerPlaceId || "", 200) || null,
    provider: cleanString(source.provider || source.source || "", 80) || null,
    latitude: latitude == null ? null : Number(latitude.toFixed(6)),
    longitude: longitude == null ? null : Number(longitude.toFixed(6)),
  };
}

function addressSnapshot(value = {}, coordinates = {}) {
  const source = cleanMap(value);
  return {
    ...coordinateSnapshot(coordinates),
    address: cleanString(source.address || source.formattedAddress || "", 500) || null,
    locality: cleanString(source.locality || source.city || source.postcode || "", 160) || null,
  };
}

function buildCanonicalQuoteSnapshot({data = {}, quote = {}, routeFacts = {}, serverDistanceMiles}) {
  const parcel = cleanMap(data.parcel);
  const pickupCoordinates = data.pickupCoordinates || data.pickupPosition ||
    cleanMap(data.pickup).coordinates || {};
  const dropoffCoordinates = data.dropoffCoordinates || data.dropoffPosition ||
    cleanMap(data.dropoff).coordinates || {};
  const pickup = cleanMap(data.pickup);
  const dropoff = cleanMap(data.dropoff);
  const deliveryTime = cleanMap(data.deliveryTime);
  return {
    pickup: addressSnapshot(pickup, pickupCoordinates),
    dropoff: addressSnapshot(dropoff, dropoffCoordinates),
    route: {
      fingerprint: cleanString(routeFacts.routeFingerprint || "", 200) || null,
      provider: cleanString(routeFacts.provider || routeFacts.routeSource || "", 80) || null,
      distanceMeters: finiteNumber(routeFacts.routeDistanceMeters),
      distanceMiles: Number(Number(serverDistanceMiles || quote.distanceMiles || 0).toFixed(4)),
      durationSeconds: finiteNumber(routeFacts.routeDurationSeconds || routeFacts.durationSeconds),
    },
    vehicle: quote.selectedVehicle,
    speed: quote.selectedSpeed,
    weightKg: Number(Number(quote.weightKg || 0).toFixed(3)),
    parcel: {
      itemName: cleanString(parcel.itemName || "", 240) || null,
      description: cleanString(parcel.description || data.description || data.packageDescription || "", 600) || null,
      weightKg: finiteNumber(parcel.weightKg || data.weightKg),
      weightLabel: cleanString(parcel.weightLabel || "", 80) || null,
      highValue: parcel.highValue === true || data.highValue === true,
    },
    access: {
      pickup: cleanString(data.pickupAccess || pickup.access || "", 80) || null,
      dropoff: cleanString(data.dropoffAccess || dropoff.access || "", 80) || null,
    },
    vanguard: quote.vanguardProtocolEnabled === true,
    iris: {
      compliance: quote.irisComplianceStatus || null,
      serviceability: quote.irisServiceabilityStatus || null,
      normalCheckoutEligible: quote.normalCheckoutEligible === true,
      photoAnalysisId: quote.irisPhotoAnalysisId || null,
    },
    schedule: deliveryTime.type || deliveryTime.scheduledAt || deliveryTime.scheduledWindow ? {
      type: cleanString(deliveryTime.type || "", 40) || null,
      scheduledAt: cleanString(deliveryTime.scheduledAt || "", 80) || null,
      scheduledWindow: cleanString(deliveryTime.scheduledWindow || "", 120) || null,
    } : null,
    currency: quote.currency,
    roadChargePolicyVersion: quote.roadChargePolicyVersion,
    pricingSource: quote.pricingSource,
    lineItems: quote.lineItems,
    total: quote.total,
    amountDue: quote.amountDue,
  };
}

function quoteComparablePayload(payload = {}) {
  const parcel = cleanMap(payload.parcel);
  const pickup = cleanMap(payload.pickup);
  const dropoff = cleanMap(payload.dropoff);
  return {
    pickup: coordinateSnapshot(payload.pickupCoordinates || payload.pickupPosition || pickup.coordinates),
    dropoff: coordinateSnapshot(payload.dropoffCoordinates || payload.dropoffPosition || dropoff.coordinates),
    vehicle: canonicalVehicle(payload.selectedVehicle || payload.vehicleType || payload.recommendedVehicle),
    speed: speedKey(payload.selectedSpeed || payload.selectedOption || payload.selectedServiceLevel),
    weightKg: finiteNumber(payload.weightKg || parcel.weightKg),
    parcel: {
      itemName: cleanString(parcel.itemName || "", 240) || null,
      description: cleanString(parcel.description || payload.description || payload.packageDescription || "", 600) || null,
      weightKg: finiteNumber(parcel.weightKg || payload.weightKg),
      highValue: parcel.highValue === true || payload.highValue === true,
    },
    access: {
      pickup: cleanString(payload.pickupAccess || pickup.access || "", 80) || null,
      dropoff: cleanString(payload.dropoffAccess || dropoff.access || "", 80) || null,
    },
    vanguard: payload.vanguardProtocolEnabled === true || payload.vanguard === true,
  };
}

function assertQuotePayloadMatchesSnapshot(quote, payload) {
  const snapshot = quote.canonicalQuoteSnapshot;
  if (!snapshot || quote.canonicalQuoteSnapshotHash !== canonicalQuoteHash(snapshot)) {
    throw new functions.https.HttpsError("failed-precondition", "This quote must be refreshed before payment.", {reason: "invalid_quote_snapshot"});
  }
  const candidate = quoteComparablePayload(payload);
  const expected = {
    pickup: coordinateSnapshot(snapshot.pickup),
    dropoff: coordinateSnapshot(snapshot.dropoff),
    vehicle: snapshot.vehicle,
    speed: snapshot.speed,
    weightKg: snapshot.weightKg,
    parcel: {
      itemName: snapshot.parcel.itemName,
      description: snapshot.parcel.description,
      weightKg: snapshot.parcel.weightKg,
      highValue: snapshot.parcel.highValue,
    },
    access: snapshot.access,
    vanguard: snapshot.vanguard,
  };
  if (JSON.stringify(canonicalHashValue(candidate)) !== JSON.stringify(canonicalHashValue(expected))) {
    throw new functions.https.HttpsError("failed-precondition", "The booking changed after its quote was issued. Please recalculate.", {reason: "quote_input_mismatch"});
  }
  return snapshot;
}

function canonicalVehicle(value) {
  const normalized = text(value).toLowerCase();
  if (/(van|luton|transit|sprinter)/.test(normalized)) return "van";
  if (/(car|estate|suv|4x4|sedan|saloon|hatchback)/.test(normalized)) return "car";
  if (/(motorbike|motorcycle|moped|scooter|bike|bicycle|cycle|ebike|e-bike|electric bike)/.test(normalized)) {
    return "motorbike";
  }
  return "motorbike";
}

function vehicleSurcharge(value) {
  return money(VEHICLE_SURCHARGES_GBP[canonicalVehicle(value)] || 0);
}

function vehicleLabel(value) {
  const vehicle = canonicalVehicle(value);
  return vehicle === "van" ? "Van" : vehicle === "car" ? "Car" : "Motorbike";
}

function firstMoney(...values) {
  for (const value of values) {
    const parsed = Number(value);
    if (Number.isFinite(parsed) && parsed > 0) return money(parsed);
  }
  return 0;
}

function senderDraftRef(db, uid) {
  return db.collection("senderBookingDrafts").doc(uid);
}

function cleanString(value, maxLength = 600) {
  return text(value).slice(0, Math.min(maxLength, MAX_STRING_LENGTH));
}

function cleanBoolean(value) {
  return value === true;
}

function cleanMap(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {};
}

function stripUndefined(value) {
  if (Array.isArray(value)) {
    return value
        .map((item) => stripUndefined(item))
        .filter((item) => item !== undefined);
  }
  if (value && typeof value === "object" &&
      !(value instanceof Date) &&
      !(value instanceof GeoPoint) &&
      !(value instanceof Timestamp)) {
    return Object.fromEntries(
        Object.entries(value)
            .filter(([, item]) => item !== undefined)
            .map(([key, item]) => [key, stripUndefined(item)])
            .filter(([, item]) => item !== undefined),
    );
  }
  return value;
}

function cleanNumber(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function rejectSensitiveDraftKeys(value, path = "", depth = 0) {
  if (depth > MAX_DEPTH) {
    throw new functions.https.HttpsError("invalid-argument", "Draft data is too deeply nested.");
  }
  if (Array.isArray(value)) {
    if (value.length > 20) {
      throw new functions.https.HttpsError("invalid-argument", "Draft data contains too many items.");
    }
    value.forEach((item, index) => rejectSensitiveDraftKeys(item, `${path}[${index}]`, depth + 1));
    return;
  }
  if (!value || typeof value !== "object") return;
  Object.keys(value).forEach((key) => {
    const compact = key.toLowerCase().replace(/[^a-z0-9_]/g, "");
    if (FORBIDDEN_DRAFT_KEYS.some((forbidden) => compact.includes(forbidden))) {
      console.warn(`Rejected Sender draft forbidden field at ${path ? `${path}.` : ""}${key}`);
      throw new functions.https.HttpsError("invalid-argument", "Draft contains payment or verification data that cannot be stored.");
    }
    rejectSensitiveDraftKeys(value[key], path ? `${path}.${key}` : key, depth + 1);
  });
}

function payloadBytes(value) {
  return Buffer.byteLength(JSON.stringify(value || {}), "utf8");
}

function assertKnownTopLevelKeys(input, allowed) {
  Object.keys(input).forEach((key) => {
    if (!allowed.has(key)) {
      throw new functions.https.HttpsError("invalid-argument", `Unsupported draft field: ${key}`);
    }
  });
}

function normalizeIncomingDraft(raw) {
  const input = cleanMap(raw);
  assertKnownTopLevelKeys(input, new Set(["schemaVersion", "baseRevision", "draft", "version", "step", "status", "completed", "draftId", "pickup", "dropoff", "recipient", "deliveryTime", "parcel", "iris", "deliveryOptions", "review", "paymentMethod"]));
  const schemaVersion = Number(input.schemaVersion || input.version || DRAFT_SCHEMA_VERSION);
  if (schemaVersion > DRAFT_SCHEMA_VERSION) {
    throw new functions.https.HttpsError("failed-precondition", "This saved draft was created by a newer version of Circum. Please update the app.");
  }
  if (schemaVersion < 1) {
    throw new functions.https.HttpsError("invalid-argument", "Unsupported draft version.");
  }
  const draft = cleanMap(input.draft);
  return {
    schemaVersion: DRAFT_SCHEMA_VERSION,
    baseRevision: Number.isFinite(Number(input.baseRevision)) ? Number(input.baseRevision) : 0,
    draft: Object.prototype.hasOwnProperty.call(input, "draft") ? draft : input,
  };
}

function sanitizeSenderDraftPayload(raw) {
  if (payloadBytes(raw) > MAX_DRAFT_BYTES) {
    throw new functions.https.HttpsError("invalid-argument", "Draft is too large to save.");
  }
  rejectSensitiveDraftKeys(raw);
  const normalized = normalizeIncomingDraft(raw);
  const input = cleanMap(normalized.draft);
  assertKnownTopLevelKeys(input, new Set(["version", "schemaVersion", "step", "status", "completed", "draftId", "pickup", "dropoff", "recipient", "deliveryTime", "parcel", "iris", "deliveryOptions", "review", "paymentMethod"]));
  const pickup = cleanMap(input.pickup);
  const dropoff = cleanMap(input.dropoff);
  const recipient = cleanMap(input.recipient);
  const deliveryTime = cleanMap(input.deliveryTime);
  const parcel = cleanMap(input.parcel);
  const iris = cleanMap(input.iris);
  const deliveryOptions = cleanMap(input.deliveryOptions);
  const review = cleanMap(input.review);
  const paymentMethod = cleanMap(input.paymentMethod);

  const step = cleanString(input.step, 60) || "pickup";
  const timingType = cleanString(deliveryTime.type, 40) || "now";
  const selectedOptionRaw = cleanString(deliveryOptions.selectedOption, 80) || "Standard";
  const selectedOption =
    speedKey(selectedOptionRaw) === "express" ? "Express" : "Standard";
  if (!ALLOWED_STEPS.has(step)) {
    throw new functions.https.HttpsError("invalid-argument", "Draft step is not supported.");
  }
  if (!ALLOWED_TIMING_TYPES.has(timingType)) {
    throw new functions.https.HttpsError("invalid-argument", "Delivery time type is not supported.");
  }
  if (!ALLOWED_OPTIONS.has(selectedOptionRaw) &&
      !LEGACY_ALLOWED_OPTIONS.has(selectedOptionRaw)) {
    throw new functions.https.HttpsError("invalid-argument", "Delivery option is not supported.");
  }

  const draft = {
    schemaVersion: DRAFT_SCHEMA_VERSION,
    status: "draft",
    completed: false,
    draftId: cleanString(input.draftId, 120),
    step,
    pickup: {
      address: cleanString(pickup.address, 1000),
      subAddress: cleanString(pickup.subAddress, 300),
      locality: cleanString(pickup.locality, 200),
    },
    dropoff: {
      address: cleanString(dropoff.address, 1000),
      subAddress: cleanString(dropoff.subAddress, 300),
      locality: cleanString(dropoff.locality, 200),
    },
    recipient: {
      name: cleanString(recipient.name, 200),
      phone: cleanString(recipient.phone, 80),
      email: cleanString(recipient.email, 320),
      deliveryNotes: cleanString(recipient.deliveryNotes, 1000),
    },
    deliveryTime: {
      type: timingType,
      scheduledDate: cleanString(deliveryTime.scheduledDate, 40),
      scheduledWindow: cleanString(deliveryTime.scheduledWindow, 80),
      customWindowStart: cleanString(deliveryTime.customWindowStart, 20),
      customWindowEnd: cleanString(deliveryTime.customWindowEnd, 20),
      summary: cleanString(deliveryTime.summary, 160),
    },
    parcel: {
      itemName: cleanString(parcel.itemName, 200),
      description: cleanString(parcel.description, 1000),
      weightLabel: cleanString(parcel.weightLabel, 80),
      fragile: cleanBoolean(parcel.fragile),
      highValue: cleanBoolean(parcel.highValue),
    },
    iris: {
      itemName: cleanString(iris.itemName, 200),
      confidence: cleanString(iris.confidence, 80),
      recommendedVehicle: cleanString(iris.recommendedVehicle, 120),
      category: cleanString(iris.category, 120),
      source: cleanString(iris.source, 120),
    },
    deliveryOptions: {
      selectedOption,
      vanguard: cleanBoolean(deliveryOptions.vanguard),
    },
    review: {
      amountDue: cleanNumber(review.amountDue),
      quoteId: cleanString(review.quoteId, 160),
    },
    paymentMethod: {
      type: cleanString(paymentMethod.type, 80),
      paymentMethodId: cleanString(paymentMethod.paymentMethodId, 200),
      label: cleanString(paymentMethod.label, 200),
      rothEnabled: cleanBoolean(paymentMethod.rothEnabled),
    },
  };
  if (payloadBytes(draft) > MAX_DRAFT_BYTES) {
    throw new functions.https.HttpsError("invalid-argument", "Draft is too large to save.");
  }
  return {
    schemaVersion: DRAFT_SCHEMA_VERSION,
    baseRevision: normalized.baseRevision,
    draft,
  };
}

function draftExpiresAt() {
  return Timestamp.fromDate(new Date(Date.now() + DRAFT_RETENTION_DAYS * 24 * 60 * 60 * 1000));
}

function timestampMillis(value) {
  if (!value) return null;
  if (value instanceof Timestamp) return value.toMillis();
  if (typeof value.toMillis === "function") return value.toMillis();
  const parsed = Date.parse(`${value}`);
  return Number.isFinite(parsed) ? parsed : null;
}

function draftExpired(record) {
  if (!record || !record.expiresAt) return false;
  const expiresAt = timestampMillis(record.expiresAt);
  return expiresAt != null && expiresAt <= Date.now();
}

function draftInactive(record) {
  if (!record) return false;
  const activityAt = timestampMillis(
      record.lastActivityAt || record.updatedAt || record.lastOpenedAt || record.createdAt,
  );
  if (activityAt == null) return false;
  return Date.now() - activityAt > DRAFT_INACTIVITY_MINUTES * 60 * 1000;
}

function canonicalDraftResponse(record) {
  if (!record) return {exists: false};
  const draft = record.draft ? record.draft : sanitizeSenderDraftPayload(record).draft;
  return {
    exists: true,
    schemaVersion: record.schemaVersion || DRAFT_SCHEMA_VERSION,
    revision: Number(record.revision || 0),
    draftId: record.draftId || draft.draftId || "",
    status: record.status || "draft",
    expiresAt: record.expiresAt || null,
    draft,
  };
}

exports.saveSenderDraft = functions.https.onCall(async (data, context) => {
  const sender = requireSender(context);
  const db = getFirestore();
  const ref = senderDraftRef(db, sender.uid);
  const safe = sanitizeSenderDraftPayload(data || {});
  let savedRecord = null;

  await db.runTransaction(async (transaction) => {
    const existing = await transaction.get(ref);
    const current = existing.exists ? existing.data() || {} : {};
    const currentRevision = Number(current.revision || 0);
    if (existing.exists && safe.baseRevision !== currentRevision) {
      throw new functions.https.HttpsError(
          "aborted",
          "Your draft was updated on another device. We refreshed it with the latest version.",
          {currentRevision},
      );
    }
    const nextRevision = currentRevision + 1;
    const now = FieldValue.serverTimestamp();
    const draftId = safe.draft.draftId || current.draftId || ref.id;
    savedRecord = {
      schemaVersion: DRAFT_SCHEMA_VERSION,
      revision: nextRevision,
      uid: sender.uid,
      draftId,
      status: "draft",
      draft: {...safe.draft, draftId},
      completed: false,
      createdAt: existing.exists ? current.createdAt || now : now,
      updatedAt: now,
      lastActivityAt: now,
      lastOpenedAt: now,
      expiresAt: draftExpiresAt(),
    };
    transaction.set(ref, savedRecord, {merge: false});
  });

  return {ok: true, ...canonicalDraftResponse(savedRecord)};
});

exports.loadSenderDraft = functions.https.onCall(async (_data, context) => {
  const sender = requireSender(context);
  const snapshot = await senderDraftRef(getFirestore(), sender.uid).get();
  if (!snapshot.exists) {
    return {exists: false};
  }
  const record = snapshot.data() || {};
  if (record.completed === true || record.status === "completed" || record.status === "converting") {
    return {exists: false};
  }
  if (draftExpired(record) || draftInactive(record)) {
    await snapshot.ref.delete();
    return {exists: false};
  }
  await snapshot.ref.set({
    lastOpenedAt: FieldValue.serverTimestamp(),
    expiresAt: draftExpiresAt(),
  }, {merge: true});
  return canonicalDraftResponse(record);
});

exports.deleteSenderDraft = functions.https.onCall(async (_data, context) => {
  const sender = requireSender(context);
  await senderDraftRef(getFirestore(), sender.uid).delete();
  return {ok: true};
});

exports.cleanupExpiredSenderDrafts = functions.pubsub.schedule("every 24 hours").onRun(async () => {
  const db = getFirestore();
  const now = Timestamp.now();
  const snapshot = await db.collection("senderBookingDrafts")
      .where("expiresAt", "<=", now)
      .where("status", "==", "draft")
      .limit(300)
      .get();
  if (snapshot.empty) return {deleted: 0};
  const batch = db.batch();
  snapshot.docs.forEach((doc) => batch.delete(doc.ref));
  await batch.commit();
  return {deleted: snapshot.size};
});

async function verifiedBusinessContext(db, sender, rawContext) {
  const businessId = text(rawContext && rawContext.businessId);
  if (!businessId) return null;
  const accountSnap = await db.collection("businessAccounts").doc(businessId).get();
  if (!accountSnap.exists) {
    throw new functions.https.HttpsError("not-found", "Business account not found.");
  }
  const account = accountSnap.data() || {};
  const email = sender.email.trim().toLowerCase();
  const members = Array.isArray(account.teamMemberIds) ?
    account.teamMemberIds.map((item) => `${item}`.trim().toLowerCase()) : [];
  const allowed = account.createdByUserId === sender.uid ||
    members.includes(sender.uid.toLowerCase()) || (email && members.includes(email));
  if (!allowed) {
    throw new functions.https.HttpsError("permission-denied", "Business account access is required.");
  }
  return {
    businessId,
    businessAccountId: businessId,
    businessName: text(account.businessName || account.name),
    billingEmail: text(account.billingEmail || account.contactEmail),
    billingSource: "business_finance",
    paymentProfileSource: "shared_payment_profile",
    businessMode: true,
  };
}

function speedKey(value) {
  const normalized = text(value).toLowerCase();
  if (normalized === "express") return "express";
  return "standard";
}

function weightSurcharge(weightKg) {
  const weight = Math.max(0, Number(weightKg || 0));
  if (weight > 40) return 25;
  if (weight > 20) return 15;
  if (weight > 10) return 7;
  if (weight > 5) return 3;
  return 0;
}

function distanceFare(distanceMiles) {
  const distance = Math.max(0, Number(distanceMiles || 0));
  if (distance < SHORT_TRIP_FARE_FLOOR_MILES) return 0;
  const multiplier = distance > LONG_DISTANCE_THRESHOLD_MILES ? LONG_DISTANCE_MULTIPLIER : 1;
  return money(distance * ADDITIONAL_FARE_PER_MILE_GBP * multiplier);
}

function speedAdjustment(subtotal, speed) {
  if (speed === "express") return Math.max(EXPRESS_SURCHARGE_GBP, money(subtotal * 0.2));
  return 0;
}

function riderEligibleFareFromQuote(quote = {}) {
  if (Array.isArray(quote.lineItems)) {
    const eligible = quote.lineItems
        .filter((item) => !["vanguard", "road_toll", "daily_zone_charge"].includes(`${item && item.key || ""}`.toLowerCase()))
        .reduce((sum, item) => sum + Number(item && item.amount || 0), 0);
    if (Number.isFinite(eligible) && eligible > 0) return money(eligible);
  }
  const total = money(quote.total || quote.finalAmount || quote.amountDue);
  const vanguard = quote.vanguardProtocolEnabled === true || quote.vanguardRequired === true ?
    VANGUARD_ADD_ON_GBP : 0;
  return money(Math.max(0, total - vanguard));
}

function riderPayoutFromQuote(quote = {}) {
  return firstMoney(
      quote.riderEarning,
      quote.riderPayout,
      quote.driverPayout,
      quote.totalRiderEarnings,
      money(riderEligibleFareFromQuote(quote) * RIDER_DELIVERY_FARE_SHARE),
  );
}

function safeStripeCheckoutError(error) {
  const code = text(error && (error.code || error.type || error.rawType)) || "stripe_checkout_failed";
  const message = text(error && error.message);
  const parameter = text(error && error.param);
  console.error("Sender Stripe checkout creation failed", {
    code,
    type: text(error && error.type),
    statusCode: error && error.statusCode || null,
    requestId: error && error.requestId || null,
    parameter: parameter || null,
    message,
    declineCode: error && error.decline_code || null,
    paymentIntent: error && error.payment_intent && error.payment_intent.id || null,
  });
  if (code === "parameter_unknown") {
    return parameter ?
      `Stripe checkout configuration rejected ${parameter}. Please contact support.` :
      "Stripe checkout configuration was rejected. Please contact support.";
  }
  if (code === "rate_limit") {
    return "Stripe is temporarily busy. Please wait a moment and try again.";
  }
  if (code === "authentication_error") {
    return "Stripe API authentication failed. Please contact support.";
  }
  if (code === "api_connection_error") {
    return "Unable to contact Stripe. Please try again.";
  }
  if (message.toLowerCase().includes("no such customer")) {
    return "Your saved payment profile needs to be refreshed. Please try again.";
  }
  if (message.toLowerCase().includes("api key")) {
    return "Stripe checkout is not available right now. Please contact support.";
  }
  return "Stripe checkout could not be started. Please try again.";
}

function safePaymentFinalizationError(error) {
  const message = text(error && error.message);
  const lower = message.toLowerCase();
  console.error("Sender payment finalization failed", {
    code: text(error && (error.code || error.type || error.rawType)),
    statusCode: error && error.statusCode || null,
    requestId: error && error.requestId || null,
    message,
  });
  if (lower.includes("must be confirmed") || lower.includes("could not be verified")) {
    return "Payment could not be confirmed yet. Please try again.";
  }
  if (lower.includes("requires review") || lower.includes("review before normal dispatch")) {
    return "This delivery requires review before normal dispatch.";
  }
  if (lower.includes("ownership") || lower.includes("belong")) {
    return "This payment session does not belong to this account.";
  }
  if (lower.includes("not found")) {
    return "Payment session could not be found. Please restart checkout.";
  }
  if (lower.includes("timeout") || lower.includes("network")) {
    return "Unable to contact payment service. Please try again.";
  }
  return "Stripe payment could not be confirmed. Please try again.";
}

function logSenderPaymentStage(stage, fields = {}) {
  console.info("sender_payment_flow", {
    stage,
    surface: "sender",
    ...fields,
  });
}

function wait(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function retrievePaidCheckoutSession(stripe, sessionId, paymentSessionId) {
  let latest = null;
  for (let attempt = 1; attempt <= 3; attempt += 1) {
    latest = await stripe.checkout.sessions.retrieve(sessionId);
    logSenderPaymentStage("stripe_checkout_session_retrieved", {
      paymentSessionId,
      checkoutSessionId: sessionId,
      attempt,
      paymentStatus: latest.payment_status || null,
      status: latest.status || null,
      amountTotal: latest.amount_total || null,
      currency: latest.currency || null,
    });
    if (`${latest.payment_status || ""}`.toLowerCase() === "paid") {
      return latest;
    }
    await wait(attempt * 750);
  }
  return latest;
}

function safeDeliveryCreationError(error) {
  const message = text(error && error.message);
  const sourceCode = text(error && error.code);
  const lower = message.toLowerCase();
  console.error("Sender paid delivery creation failed", {
    code: sourceCode,
    message,
    details: error && error.details || null,
  });
  if (sourceCode === "unauthenticated" || lower.includes("auth")) {
    return {
      code: "unauthenticated",
      message: "Please sign in again before paying.",
      reason: "authentication_required",
    };
  }
  if (sourceCode === "permission-denied" || lower.includes("permission")) {
    return {
      code: "permission-denied",
      message: "Payment could not create this delivery for your account.",
      reason: "delivery_write_denied",
    };
  }
  if (lower.includes("wallet is frozen")) {
    return {
      code: "failed-precondition",
      message: "Roth balance is frozen. Please choose another payment method.",
      reason: "roth_wallet_frozen",
    };
  }
  if (lower.includes("wallet balance is too low") || lower.includes("insufficient roth")) {
    return {
      code: "failed-precondition",
      message: "Insufficient Roth balance. Please add Roth or choose card payment.",
      reason: "insufficient_roth_balance",
    };
  }
  if (lower.includes("stripe payment must be confirmed")) {
    return {
      code: "failed-precondition",
      message: "Card payment must be confirmed before delivery creation.",
      reason: "stripe_payment_unconfirmed",
    };
  }
  if (lower.includes("payment session") && lower.includes("not found")) {
    return {
      code: "not-found",
      message: "Payment session could not be found. Please restart checkout.",
      reason: "payment_session_missing",
    };
  }
  if (lower.includes("idempotency") || lower.includes("duplicate")) {
    return {
      code: "already-exists",
      message: "This payment is already being processed. Please refresh your delivery status.",
      reason: "duplicate_delivery_payment",
    };
  }
  if (lower.includes("payload") || lower.includes("missing") || lower.includes("invalid")) {
    return {
      code: "invalid-argument",
      message: "Some delivery details are incomplete. Please review the booking and try again.",
      reason: "invalid_delivery_payload",
    };
  }
  if (lower.includes("deadline") || lower.includes("timeout") || lower.includes("network")) {
    return {
      code: "deadline-exceeded",
      message: "Delivery creation timed out. No Roth was deducted. Please try again.",
      reason: "delivery_creation_timeout",
    };
  }
  return {
    code: sourceCode && sourceCode !== "internal" ? sourceCode : "failed-precondition",
    message: "Delivery could not be created safely. No Roth was deducted. Please try again.",
    reason: "delivery_creation_failed",
  };
}

function walletRefsForSender(db, sender) {
  const walletId = (sender.email || sender.uid).trim().toLowerCase();
  return {
    walletId,
    walletRef: db.collection("wallets").doc(walletId),
    senderWalletRef: db.collection("senderWallets").doc(sender.uid),
  };
}

function riderDisplayAliases({quote = {}, data = {}, vanguardFields = {}} = {}) {
  const distanceMiles = Number(quote.distanceMiles || data.distanceMiles || 0);
  const durationMinutes = Number(
      quote.estimatedDurationMinutes ||
      data.estimatedDurationMinutes ||
      data.durationMinutes ||
      0,
  );
  const deliveryTime = cleanMap(data.deliveryTime);
  const pickupWindow = text(
      deliveryTime.scheduledWindow ||
      deliveryTime.customWindow ||
      deliveryTime.summary ||
      data.pickupWindow ||
      data.scheduledPickupWindow,
  );
  const riderPayout = riderPayoutFromQuote(quote);
  return {
    driverPayout: riderPayout,
    riderPayout,
    riderEarning: riderPayout,
    distanceText: distanceMiles > 0 ? `${distanceMiles.toFixed(1)} mi` : null,
    durationText: durationMinutes > 0 ? `${Math.round(durationMinutes)} min` : null,
    requiresVanguard: vanguardFields.vanguardProtocolEnabled === true ||
      quote.vanguardRequired === true ||
      quote.vanguardProtocolEnabled === true,
    pickupWindow: pickupWindow || null,
  };
}

function quotePayload(data, uid, serverPhotoAnalysis = null, serverRoadChargeFacts = null) {
  const selectedSpeed = speedKey(data.selectedSpeed || data.selectedOption);
  const authoritativeDistanceMiles = finiteNumber(data.authoritativeDistanceMiles);
  const clientWeightKg = Number(data.weightKg || data.parcel && data.parcel.weightKg || 0.5);
  const photoWeightKg = Number(serverPhotoAnalysis && serverPhotoAnalysis.estimatedWeightKg || 0);
  const weightKg = Math.max(0.5, clientWeightKg, photoWeightKg);
  const base = BASE_FARE_GBP;
  const distance = distanceFare(authoritativeDistanceMiles == null ? data.distanceMiles : authoritativeDistanceMiles);
  const weight = weightSurcharge(weightKg);
  const selectedVehicle = canonicalVehicle(
      data.selectedVehicle ||
      data.vehicleType ||
      data.recommendedVehicle ||
      data.iris && (data.iris.recommendedVehicle || data.iris.vehicleType),
  );
  const vehicle = vehicleSurcharge(selectedVehicle);
  const subtotal = money(base + distance + weight + vehicle);
  const speed = money(speedAdjustment(subtotal, selectedSpeed));
  const parcelData = cleanMap(data.parcel);
  const parcelDescription = text(parcelData.description || parcelData.itemName || data.description || data.packageDescription);
  const irisEligibility = normalDispatchEligibilityForInput({
    description: parcelDescription,
    declaredWeightText: parcelData.weightLabel || parcelData.weightKg || data.weightKg || "",
    photoEstimatedWeightKg: photoWeightKg || null,
    distanceMiles: authoritativeDistanceMiles == null ? data.distanceMiles || 0 : authoritativeDistanceMiles,
    speed: selectedSpeed,
    vehicleType: selectedVehicle,
    workflow: data.sourceModule || data.serviceType || data.type,
  });
  const highValueParcel = data.highValue === true || parcelData.highValue === true;
  const surfaceText = text(data.sourceModule || data.serviceType || data.type).toLowerCase();
  const businessDelivery = data.businessMode === true ||
    text(data.businessId || data.businessAccountId).length > 0;
  const healthDelivery = surfaceText.includes("health");
  const giftDelivery = surfaceText.includes("gift");
  const vanguardSelected = data.vanguardProtocolEnabled === true || data.vanguard === true;
  const irisVanguardRequired = data.iris && data.iris.vanguardRequired === true;
  const vanguardRequired = irisVanguardRequired || highValueParcel ||
    businessDelivery || healthDelivery || giftDelivery;
  const vanguardIncluded = vanguardRequired;
  const vanguard = !vanguardIncluded && vanguardSelected ? VANGUARD_ADD_ON_GBP : 0;
  const vanguardRequiredReason = highValueParcel ?
    "Vanguard is required for high-value deliveries." :
    businessDelivery ?
      "Vanguard is required for business deliveries." :
      healthDelivery ?
        "Vanguard is required for Health+ deliveries." :
        giftDelivery ?
          "Vanguard is required for Gifts deliveries." :
          data.iris && data.iris.vanguardRequiredReason || "";
  const roadChargeBreakdown = evaluateRoadCharges({
    routeFacts: serverRoadChargeFacts,
    selectedVehicle,
    at: data.roadChargeAt || new Date(),
    liabilityState: data.roadChargeLiabilityState || {},
  });
  const roadChargeCustomerContribution = money(roadChargeBreakdown.customerContribution);
  const roadChargeRiderReimbursement = money(roadChargeBreakdown.riderReimbursement);
  const roadChargeCircumContribution = money(roadChargeBreakdown.circumContribution);
  const roadChargeCircumRevenue = money(roadChargeBreakdown.circumRevenue);
  const roadChargeMaximumSettlementPence = roadChargeBreakdown.charges.reduce((total, charge) => {
    if (charge.type === "daily_zone_charge") {
      return total + Number(charge.amountPence || 0);
    }
    if (charge.type === "route_toll") {
      return total + Number(charge.riderReimbursementPence || charge.amountPence || 0);
    }
    return total;
  }, 0);
  const total = money(Math.max(0, subtotal + speed + vanguard + roadChargeCustomerContribution));
  const riderBaseShare = money(Math.max(0, subtotal + speed) * RIDER_DELIVERY_FARE_SHARE);
  const platformBaseShare = money(Math.max(0, subtotal + speed) * PLATFORM_DELIVERY_FARE_SHARE);
  const totalRiderEarnings = riderBaseShare;
  const estimatedTotalRiderEarnings = money(riderBaseShare + roadChargeRiderReimbursement);
  const totalCircumRevenue = money(platformBaseShare + roadChargeCircumRevenue + vanguard);
  const quoteId = text(data.quoteId) || `sender_quote_${uid}_${Date.now()}`;
  const speedOptions = ["standard", "express"].map((speedOption) => {
    const optionSpeed = money(speedAdjustment(subtotal, speedOption));
    const optionTotal = money(Math.max(0, subtotal + optionSpeed + vanguard + roadChargeCustomerContribution));
    return {
      speed: `${speedOption[0].toUpperCase()}${speedOption.slice(1)}`,
      total: optionTotal,
      speedAdjustment: optionSpeed,
      roadChargeCustomerContribution,
      description: speedOption === "express" ?
        "Priority rider matching and urgent pickup." :
        "Regular rider matching.",
      currency: "GBP",
    };
  });
  return {
    quoteId,
    userId: uid,
    currency: "GBP",
    selectedSpeed,
    distanceMiles: authoritativeDistanceMiles == null ? Number(data.distanceMiles || 0) : authoritativeDistanceMiles,
    weightKg,
    selectedVehicle,
    vehicleType: selectedVehicle,
    vehicleSurcharge: vehicle,
    vanguardProtocolEnabled: vanguardIncluded || vanguard > 0,
    vanguardIncluded,
    vanguardRequired,
    vanguardRequiredReason,
    lineItems: [
      {key: "base_delivery", label: "Base delivery", amount: base},
      {key: "distance", label: "Distance", amount: distance},
      {key: "weight", label: "Parcel weight", amount: weight},
      ...(vehicle > 0 ? [{key: "vehicle", label: `${vehicleLabel(selectedVehicle)} vehicle`, amount: vehicle}] : []),
      {key: "speed_adjustment", label: selectedSpeed === "express" ? "Express priority" : `${selectedSpeed[0].toUpperCase()}${selectedSpeed.slice(1)} service`, amount: speed},
      ...(vanguardIncluded ? [{key: "vanguard", label: "Vanguard Included", amount: 0}] : []),
      ...(!vanguardIncluded && vanguard > 0 ? [{key: "vanguard", label: "Vanguard Protection", amount: vanguard}] : []),
      ...roadChargeBreakdown.charges
          .filter((charge) => charge.customerContributionPence > 0)
          .map((charge) => ({
            key: charge.type === "route_toll" ? "road_toll" : "daily_zone_charge",
            label: charge.chargeId === "congestion_charge" ? "Central London fee" :
              "Road charge",
            ...(charge.chargeId === "congestion_charge" ? {
              supportingCopy: "Applies to eligible deliveries within the Congestion Charge Zone.",
            } : {}),
            amount: charge.customerContribution,
          })),
    ],
    total,
    finalAmount: total,
    amountDue: total,
    speedOptions,
    driverPayout: totalRiderEarnings,
    riderPayout: totalRiderEarnings,
    riderEarning: totalRiderEarnings,
    riderBaseShare,
    riderLabourShare: 0,
    circumBaseShare: platformBaseShare,
    circumLabourShare: 0,
    totalRiderEarnings,
    estimatedRoadChargeRecovery: roadChargeRiderReimbursement,
    estimatedTotalRiderEarnings,
    totalCircumRevenue,
    roadChargePolicyVersion: ROAD_CHARGE_POLICY_VERSION,
    roadChargeBreakdown,
    roadChargeCustomerContribution,
    roadChargeRiderReimbursement,
    roadChargeCircumContribution,
    roadChargeCircumRevenue,
    roadChargeMaximumSettlementPence,
    roadChargeFinancialReservation: {
      status: roadChargeBreakdown.authoritativePricingComplete ? "reserved" : "unresolved",
      maximumRiderObligationPence: roadChargeMaximumSettlementPence,
      customerRoadFeesPence: roadChargeBreakdown.customerContributionPence,
      policyVersion: ROAD_CHARGE_POLICY_VERSION,
    },
    roadChargeFactsSource: serverRoadChargeFacts ? "authoritative_route" : "unavailable",
    roadChargeRouteFacts: serverRoadChargeFacts || null,
    roadChargePricingComplete: serverRoadChargeFacts ?
      roadChargeBreakdown.authoritativePricingComplete === true : false,
    quotedVehicleClass: selectedVehicle,
    requiredVehicleClass: selectedVehicle,
    driverShare: RIDER_DELIVERY_FARE_SHARE,
    platformShare: PLATFORM_DELIVERY_FARE_SHARE,
    pricingSource: "sender_backend_quote_v1",
    normalCheckoutEligible: irisEligibility.normalCheckoutEligible,
    irisComplianceStatus: irisEligibility.compliance,
    irisServiceabilityStatus: irisEligibility.serviceability,
    irisCheckoutBlockReason: irisEligibility.normalCheckoutEligible ? null : "not_allowed_for_normal_dispatch",
    ...(serverPhotoAnalysis ? {
      irisPhotoAnalysisId: serverPhotoAnalysis.analysisId,
      photoEstimatedWeightKg: photoWeightKg,
      photoAnalysis: {
        analysisId: serverPhotoAnalysis.analysisId,
        source: serverPhotoAnalysis.source,
        serverAuthored: true,
        confidence: serverPhotoAnalysis.confidence,
        confidenceScore: serverPhotoAnalysis.confidenceScore,
        estimatedWeightKg: photoWeightKg,
        weightClass: serverPhotoAnalysis.weightClass,
        inferredItemName: serverPhotoAnalysis.inferredItemName,
        inferredCategory: serverPhotoAnalysis.inferredCategory,
        width: serverPhotoAnalysis.width,
        height: serverPhotoAnalysis.height,
        imageQuality: serverPhotoAnalysis.imageQuality,
        needsHumanReview: serverPhotoAnalysis.needsHumanReview === true,
      },
    } : {}),
  };
}

function normalDispatchEligibilityForDeliveryPayload(payload = {}) {
  const parcel = payload.parcel && typeof payload.parcel === "object" ? payload.parcel : {};
  return normalDispatchEligibilityForInput({
    description: text(parcel.description || parcel.itemName || payload.description || payload.packageDescription),
    declaredWeightText: parcel.weightLabel || parcel.weightKg || payload.weightKg || "",
    photoEstimatedWeightKg: payload.photoEstimatedWeightKg || null,
    distanceMiles: payload.distanceMiles || 0,
    speed: payload.selectedSpeed || payload.selectedServiceLevel || payload.serviceLevel || payload.speed || "",
    vehicleType: payload.vehicleType || payload.recommendedVehicle || null,
    workflow: payload.sourceModule || payload.serviceType || payload.type,
  });
}

async function recordIneligiblePaidCheckoutReview(db, {
  paymentSessionId,
  quoteId,
  userId,
  reason,
  eligibility,
}) {
  const reviewReason = reason || eligibility.reason || "server_iris_blocked";
  await db.collection("senderPaymentSessions").doc(paymentSessionId).set({
    status: "review_required",
    paymentStatus: "review_required",
    reviewStatus: "manual_review",
    reviewReason,
    normalCheckoutEligible: false,
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  await db.collection("adminAuditLogs").add({
    actionType: "sender_paid_checkout_review_required",
    recordType: "senderPaymentSessions",
    recordId: paymentSessionId,
    paymentSessionId,
    quoteId,
    userId,
    reason: reviewReason,
    compliance: eligibility.compliance || null,
    serviceability: eligibility.serviceability || null,
    createdAt: FieldValue.serverTimestamp(),
  });
}

async function walletBalanceForSender(sender) {
  const db = getFirestore();
  const {walletId, walletRef, senderWalletRef} = walletRefsForSender(db, sender);
  const [legacySnap, projectionSnap] = await Promise.all([
    walletRef.get(),
    senderWalletRef.get(),
  ]);
  const legacy = legacySnap.exists ? legacySnap.data() || {} : {};
  const projection = projectionSnap.exists ? projectionSnap.data() || {} : {};
  const legacyBalance = legacy.balance == null ? legacy.rothCredit : legacy.balance;
  const projectionBalance = projection.balance == null ?
    projection.rothCredit : projection.balance;
  const candidates = [legacyBalance, projectionBalance]
      .map((value) => Number(value))
      .filter((value) => Number.isFinite(value) && value >= 0);
  const balance = candidates.length ? Math.max(...candidates) : 0;
  if (legacySnap.exists && projectionSnap.exists &&
      money(Number(legacyBalance || 0)) !== money(Number(projectionBalance || 0))) {
    console.warn("Sender wallet projection drift detected during payment", {
      userId: sender.uid,
      walletId,
      legacyBalance: money(Number(legacyBalance || 0)),
      projectionBalance: money(Number(projectionBalance || 0)),
      resolvedBalance: money(balance),
    });
  }
  return money(balance);
}

async function ensureStripeCustomerForSender(stripe, sender) {
  const db = getFirestore();
  const userRef = db.collection("users").doc(sender.uid);
  const userSnap = await userRef.get();
  const user = userSnap.exists ? userSnap.data() : {};
  const existingCustomerId = text(user.stripeCustomerId || user.customerId);
  if (existingCustomerId) {
    try {
      const existingCustomer = await stripe.customers.retrieve(existingCustomerId);
      if (existingCustomer && !existingCustomer.deleted) {
        return existingCustomerId;
      }
    } catch (error) {
      const code = text(error && (error.code || error.type || error.rawType));
      if (code !== "resource_missing") {
        throw error;
      }
      console.warn("Refreshing missing Sender Stripe customer", {
        userId: sender.uid,
        customerId: existingCustomerId,
        code,
      });
    }
  }
  const customer = await stripe.customers.create({
    email: sender.email || undefined,
    name: sender.name || undefined,
    metadata: {userId: sender.uid, source: "sender_booking"},
  });
  await userRef.set({
    stripeCustomerId: customer.id,
    customerId: customer.id,
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  return customer.id;
}

exports.getSenderRothBalance = functions.https.onCall(async (_, context) => {
  const sender = requireSender(context);
  const balance = await walletBalanceForSender(sender);
  return {
    balance,
    availableRoth: balance,
    currency: "ROTH",
    source: "canonical_backend_wallet",
  };
});

exports.createSenderBookingQuote = functions.runWith({
  secrets: ["GOOGLE_ROUTES_API_KEY"],
}).https.onCall(async (data, context) => {
  const sender = requireSender(context);
  const db = getFirestore();
  const businessContext = await verifiedBusinessContext(db, sender, data && data.businessContext);
  const parcel = data && data.parcel && typeof data.parcel === "object" ? data.parcel : {};
  const parcelDescription = text(data && (data.description || data.packageDescription) || parcel.description || parcel.itemName || "");
  const serverPhotoAnalysis = await verifiedPhotoAnalysis({
    db,
    uid: sender.uid,
    analysisId: data && data.irisPhotoAnalysisId,
    description: parcelDescription,
  });
  const serverRoadChargeFacts = await authoritativeRoadRouteFacts({
    db,
    pickup: data && (data.pickupCoordinates || data.pickupPosition),
    dropoff: data && (data.dropoffCoordinates || data.dropoffPosition),
  });
  if (serverRoadChargeFacts.known !== true) {
    throw new functions.https.HttpsError(
        "failed-precondition",
        "Road-charge exposure could not be established safely. Please recalculate the route.",
        {reason: serverRoadChargeFacts.reason || "authoritative_route_unavailable"},
    );
  }
  const routeDistanceMeters = finiteNumber(serverRoadChargeFacts.routeDistanceMeters);
  if (routeDistanceMeters == null || routeDistanceMeters <= 0) {
    throw new functions.https.HttpsError(
        "failed-precondition",
        "A server-calculated route distance is required before quoting.",
        {reason: "authoritative_route_distance_unavailable"},
    );
  }
  const serverDistanceMiles = routeDistanceMeters / METERS_PER_MILE;
  const quote = quotePayload({
    ...(data || {}),
    ...(businessContext || {}),
    authoritativeDistanceMiles: serverDistanceMiles,
  }, sender.uid, serverPhotoAnalysis, serverRoadChargeFacts);
  const canonicalQuoteSnapshot = buildCanonicalQuoteSnapshot({
    data: {...(data || {}), ...(businessContext || {})},
    quote,
    routeFacts: serverRoadChargeFacts,
    serverDistanceMiles,
  });
  const canonicalQuoteSnapshotHash = canonicalQuoteHash(canonicalQuoteSnapshot);
  const quoteRef = db.collection("senderBookingQuotes").doc();
  quote.quoteId = quoteRef.id;
  quote.quoteSchemaVersion = QUOTE_SCHEMA_VERSION;
  quote.canonicalQuoteSnapshot = canonicalQuoteSnapshot;
  quote.canonicalQuoteSnapshotHash = canonicalQuoteSnapshotHash;
  quote.quoteExpiresAt = Timestamp.fromDate(new Date(Date.now() + QUOTE_RETENTION_MINUTES * 60 * 1000));
  const clientDisplayQuote = cleanMap(data && data.clientDisplayQuote);
  const clientDisplayedAmount = cleanNumber(clientDisplayQuote.amount);
  const clientDisplayedAmountPence = cleanNumber(clientDisplayQuote.amountPence);
  const clientDisplayAmount = clientDisplayedAmount != null ?
    money(clientDisplayedAmount) :
    clientDisplayedAmountPence != null ? money(clientDisplayedAmountPence / 100) : null;
  const discrepancy = clientDisplayAmount == null ? null :
    money(clientDisplayAmount - money(quote.total));
  await quoteRef.set({
    ...quote,
    ...(businessContext || {}),
    clientDisplayQuote: clientDisplayAmount == null ? null : {
      amount: clientDisplayAmount,
      amountPence: minorUnits(clientDisplayAmount, "gbp"),
      currency: text(clientDisplayQuote.currency || "GBP").toUpperCase(),
    },
    pricingDiscrepancy: discrepancy,
    pricingDiscrepancyPence: discrepancy == null ? null : minorUnits(discrepancy, "gbp"),
    createdAt: FieldValue.serverTimestamp(),
    immutable: true,
  });
  return {
    ...quote,
    clientDisplayQuote: clientDisplayAmount == null ? null : {
      amount: clientDisplayAmount,
      amountPence: minorUnits(clientDisplayAmount, "gbp"),
      currency: text(clientDisplayQuote.currency || "GBP").toUpperCase(),
    },
    pricingDiscrepancy: discrepancy,
  };
});

exports.createSenderPaymentSession = (stripe) => functions.https.onCall(async (data, context) => {
  const sender = requireSender(context);
  const quoteId = text(data.quoteId);
  if (!quoteId) {
    throw new functions.https.HttpsError("invalid-argument", "A backend quote is required before payment.");
  }
  const db = getFirestore();
  const quoteSnap = await db.collection("senderBookingQuotes").doc(quoteId).get();
  if (!quoteSnap.exists || quoteSnap.data().userId !== sender.uid) {
    throw new functions.https.HttpsError("not-found", "Booking quote not found.");
  }
  const quote = quoteSnap.data();
  if (quote.currency !== "GBP" || quote.quoteSchemaVersion !== QUOTE_SCHEMA_VERSION) {
    throw new functions.https.HttpsError("failed-precondition", "This quote must be refreshed before payment.", {reason: "quote_schema_invalid"});
  }
  const expiresAt = quote.quoteExpiresAt && typeof quote.quoteExpiresAt.toDate === "function" ?
    quote.quoteExpiresAt.toDate() : null;
  if (!expiresAt || expiresAt.getTime() <= Date.now()) {
    throw new functions.https.HttpsError("failed-precondition", "This quote has expired. Please recalculate.", {reason: "quote_expired"});
  }
  const total = money(quote.total || quote.finalAmount || quote.amountDue);
  const rothEnabled = data.rothEnabled === true;
  const rothBalance = rothEnabled ? await walletBalanceForSender(sender) : 0;
  const savedPaymentMethodId = text(data.paymentMethodId);
  const requestedFallback = text(data.fallbackMethod) || "card";
  const checkoutMode = text(data.checkoutMode);
  const webCheckout = checkoutMode === "web_checkout";
  const deliveryPayload = cleanMap(data.deliveryPayload);
  assertQuotePayloadMatchesSnapshot(quote, deliveryPayload);
  const payloadEligibility = normalDispatchEligibilityForDeliveryPayload(deliveryPayload);
  if (quote.normalCheckoutEligible !== true || payloadEligibility.normalCheckoutEligible !== true) {
    throw new functions.https.HttpsError(
        "failed-precondition",
        "This delivery requires review before normal payment and dispatch.",
        {
          reason: quote.irisCheckoutBlockReason || payloadEligibility.reason || "not_allowed_for_normal_dispatch",
          compliance: payloadEligibility.compliance,
          serviceability: payloadEligibility.serviceability,
        },
    );
  }
  if (quote.roadChargeFactsSource === "authoritative_route" && quote.roadChargePricingComplete !== true) {
    throw new functions.https.HttpsError(
        "failed-precondition",
        "Road-charge pricing requires review before payment.",
        {reason: "authoritative_road_charge_pricing_incomplete"},
    );
  }
  const split = calculateWalletCheckout({
    orderTotalGbp: total,
    walletBalanceGbp: rothEnabled ? rothBalance : 0,
    selectedCurrency: "gbp",
  });
  const requestedSessionKey = stableId(JSON.stringify({
    rothEnabled,
    walletContributionGbp: split.walletContributionGbp,
    remainingGbp: split.remainingGbp,
    fallbackMethod: requestedFallback,
    savedPaymentMethodId,
    checkoutMode: webCheckout ? "web_checkout" : "payment_intent",
  }));
  const sessionRef = db.collection("senderPaymentSessions").doc(quoteId);
  const existingSessionSnap = await sessionRef.get();
  if (existingSessionSnap.exists) {
    const existingSession = existingSessionSnap.data() || {};
    if (existingSession.userId !== sender.uid || existingSession.quoteId !== quoteId) {
      throw new functions.https.HttpsError("permission-denied", "Payment session ownership mismatch.");
    }
    if (existingSession.paymentStatus === "succeeded" || existingSession.status === "succeeded") {
      return {
        paymentSessionId: sessionRef.id,
        quoteId,
        userId: sender.uid,
        amountDue: total,
        rothEnabled: existingSession.rothEnabled === true,
        rothAppliedAmount: money(existingSession.rothAppliedAmount || 0),
        remainingAmount: money(existingSession.remainingAmount || 0),
        currency: "GBP",
        status: "succeeded",
        paymentStatus: "succeeded",
        paymentMethod: text(existingSession.paymentMethod || "card"),
        idempotent: true,
      };
    }
    const sameRequestedSession = existingSession.checkoutKey === requestedSessionKey ||
      existingSession.paymentSessionKey === requestedSessionKey;
    if (webCheckout && existingSession.checkoutSessionId) {
      logSenderPaymentStage("web_checkout_retry_forces_fresh_session", {
        userId: sender.uid,
        quoteId,
        paymentSessionId: sessionRef.id,
        previousCheckoutSessionId: existingSession.checkoutSessionId,
        previousStatus: text(existingSession.paymentStatus || existingSession.status),
      });
    }
    if (!webCheckout && sameRequestedSession && existingSession.clientSecret && existingSession.stripeCustomerId) {
      const existingEphemeralKey = await stripe.ephemeralKeys.create(
          {customer: existingSession.stripeCustomerId},
          {apiVersion: "2020-08-27"},
      );
      return {
        paymentSessionId: sessionRef.id,
        quoteId,
        userId: sender.uid,
        amountDue: total,
        rothEnabled,
        rothAppliedAmount: split.walletContributionGbp,
        remainingAmount: split.remainingGbp,
        currency: "GBP",
        status: text(existingSession.status || existingSession.paymentStatus),
        paymentStatus: text(existingSession.paymentStatus || existingSession.status),
        paymentMethod: requestedFallback,
        savedPaymentMethodId: savedPaymentMethodId || null,
        stripePaymentIntentId: existingSession.stripePaymentIntentId || null,
        clientSecret: existingSession.clientSecret,
        customerId: existingSession.stripeCustomerId,
        ephemeralKeySecret: existingEphemeralKey.secret,
        idempotent: true,
      };
    }
  }
  const sessionBase = {
    paymentSessionId: sessionRef.id,
    quoteId,
    userId: sender.uid,
    userEmail: sender.email,
    ...(quote.businessMode === true ? {
      businessMode: true,
      businessId: quote.businessId,
      businessAccountId: quote.businessAccountId,
      billingEmail: quote.billingEmail,
      billingSource: quote.billingSource,
      paymentProfileSource: quote.paymentProfileSource,
    } : {}),
    amountDue: total,
    authoritativeQuote: quote,
    clientDisplayQuote: quote.clientDisplayQuote || null,
    pricingDiscrepancy: quote.pricingDiscrepancy || null,
    pricingDiscrepancyPence: quote.pricingDiscrepancyPence || null,
    rothEnabled,
    rothAppliedAmount: split.walletContributionGbp,
    remainingAmount: split.remainingGbp,
    currency: "GBP",
    paymentSessionKey: requestedSessionKey,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };
  if (!split.stripeRequired) {
    if (!deliveryPayload.pickup || !deliveryPayload.dropoff || !deliveryPayload.parcel || !deliveryPayload.recipient) {
      throw new functions.https.HttpsError("invalid-argument", "Delivery details are required before Roth payment.");
    }
    const requestId = text(data.requestId) || `sender_${stableId(`${sender.uid}:${quoteId}:${sessionRef.id}`)}`;
    const draftId = text(data.draftId);
    const idempotencyKey = text(data.idempotencyKey) ||
      stableId(`${sender.uid}:${draftId || "roth"}:${quoteId}:${sessionRef.id}:${requestedSessionKey}`);
    logSenderPaymentStage("roth_only_session_authorized", {
      userId: sender.uid,
      quoteId,
      paymentSessionId: sessionRef.id,
      rothAppliedAmount: split.walletContributionGbp,
      remainingAmount: split.remainingGbp,
      requestId,
    });
    await sessionRef.set({
      ...sessionBase,
      status: "payment_processing",
      paymentStatus: "payment_processing",
      paymentMethod: "roth",
      rothDebitStatus: "pending_delivery_creation",
      checkoutMode: webCheckout ? "web_checkout" : "payment_intent",
      requestId,
      draftId: draftId || null,
      idempotencyKey,
      deliveryPayload,
      updatedAt: FieldValue.serverTimestamp(),
    });
    try {
      const delivery = await createPaidDeliveryFromSession(stripe, sender, {
        ...deliveryPayload,
        requestId,
        quoteId,
        paymentSessionId: sessionRef.id,
        draftId: draftId || null,
        idempotencyKey,
      });
      await sessionRef.set({
        status: "succeeded",
        paymentStatus: "succeeded",
        deliveryId: delivery.deliveryId || delivery.requestId || requestId,
        requestId: delivery.requestId || requestId,
        confirmedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
      logSenderPaymentStage("roth_only_delivery_committed", {
        userId: sender.uid,
        quoteId,
        paymentSessionId: sessionRef.id,
        requestId: delivery.requestId || requestId,
        deliveryId: delivery.deliveryId || requestId,
      });
      return {
        paymentSessionId: sessionRef.id,
        quoteId,
        userId: sender.uid,
        amountDue: total,
        rothEnabled,
        rothAppliedAmount: split.walletContributionGbp,
        remainingAmount: split.remainingGbp,
        currency: "GBP",
        status: "succeeded",
        paymentStatus: "succeeded",
        paymentMethod: "roth",
        requestId: delivery.requestId || requestId,
        deliveryId: delivery.deliveryId || delivery.requestId || requestId,
        idempotencyKey,
      };
    } catch (error) {
      const safe = safeDeliveryCreationError(error);
      await sessionRef.set({
        status: "delivery_creation_failed",
        paymentStatus: "delivery_creation_failed",
        rothDebitStatus: "rolled_back_not_debited",
        lastFailure: {
          code: safe.code,
          reason: safe.reason,
          message: safe.message,
          originalMessage: text(error && error.message),
          stage: "roth_only_delivery_creation",
          updatedAt: FieldValue.serverTimestamp(),
        },
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
      logSenderPaymentStage("roth_only_delivery_failed_rolled_back", {
        userId: sender.uid,
        quoteId,
        paymentSessionId: sessionRef.id,
        requestId,
        reason: safe.reason,
      });
      throw new functions.https.HttpsError(safe.code, safe.message, {
        reason: safe.reason,
        paymentSessionId: sessionRef.id,
        quoteId,
        requestId,
        rollback: "roth_not_debited",
      });
    }
  }
  let customerId;
  try {
    customerId = await ensureStripeCustomerForSender(stripe, sender);
  } catch (error) {
    throw new functions.https.HttpsError(
        text(error && error.code) === "rate_limit" ? "resource-exhausted" : "failed-precondition",
        safeStripeCheckoutError(error),
        {code: text(error && (error.code || error.type || error.rawType))},
    );
  }
  if (savedPaymentMethodId && !customerId) {
    throw new functions.https.HttpsError("failed-precondition", "Saved payment method is unavailable.");
  }
  if (webCheckout) {
    if (!deliveryPayload.pickup || !deliveryPayload.dropoff || !deliveryPayload.parcel || !deliveryPayload.recipient) {
      throw new functions.https.HttpsError("invalid-argument", "Delivery details are required before web checkout.");
    }
    const requestId = text(data.requestId) || `sender_${stableId(`${sender.uid}:${quoteId}:${sessionRef.id}`)}`;
    const draftId = text(data.draftId);
    const checkoutAttempt = existingSessionSnap.exists ?
      Number(existingSessionSnap.data().checkoutAttempt || 0) + 1 :
      1;
    const idempotencyKey = stableId(`${sender.uid}:${draftId || "web"}:${quoteId}:${sessionRef.id}:${requestedSessionKey}:${checkoutAttempt}`);
    const baseUrl = text(data.returnUrl) || "https://circum-2797c.web.app/send";
    const separator = baseUrl.includes("?") ? "&" : "?";
    let checkoutSession;
    try {
      checkoutSession = await stripe.checkout.sessions.create({
        mode: "payment",
        payment_method_types: ["card"],
        client_reference_id: sender.uid,
        customer: customerId,
        line_items: [{
          quantity: 1,
          price_data: {
            currency: "gbp",
            unit_amount: minorUnits(split.customerPaymentAmount, "gbp"),
            product_data: {
              name: "Circum delivery",
              description: "Trusted Circum delivery booking.",
            },
          },
        }],
        success_url: `${baseUrl}${separator}sender_payment=success&paymentSessionId=${sessionRef.id}&checkoutSessionId={CHECKOUT_SESSION_ID}`,
        cancel_url: `${baseUrl}${separator}sender_payment=cancelled&paymentSessionId=${sessionRef.id}`,
        payment_intent_data: {
          setup_future_usage: "off_session",
          metadata: {
            paymentType: "delivery",
            type: "sender_delivery_payment",
            userId: sender.uid,
            userEmail: sender.email,
            quoteId,
            paymentSessionId: sessionRef.id,
            rothAppliedAmount: `${split.walletContributionGbp}`,
            remainingAmount: `${split.remainingGbp}`,
            orderTotalGbp: `${split.orderTotalGbp}`,
            fallbackMethod: requestedFallback,
            billingSource: quote.businessMode === true ? "business_finance" : "sender_finance",
          },
        },
        metadata: {
          type: "sender_delivery_payment",
          userId: sender.uid,
          userEmail: sender.email,
          quoteId,
          paymentSessionId: sessionRef.id,
          requestId,
          idempotencyKey,
          rothAppliedAmount: `${split.walletContributionGbp}`,
          remainingAmount: `${split.remainingGbp}`,
          orderTotalGbp: `${split.orderTotalGbp}`,
          returnUrl: baseUrl,
        },
      }, {idempotencyKey: `sender_checkout_${idempotencyKey}`});
    } catch (error) {
      throw new functions.https.HttpsError(
          "failed-precondition",
          safeStripeCheckoutError(error),
          {code: text(error && (error.code || error.type || error.rawType))},
      );
    }
    await sessionRef.set({
      ...sessionBase,
      status: "checkout_created",
      paymentStatus: "checkout_created",
      paymentMethod: requestedFallback,
      checkoutMode: "web_checkout",
      checkoutKey: requestedSessionKey,
      checkoutAttempt,
      checkoutUrl: checkoutSession.url,
      checkoutSessionId: checkoutSession.id,
      stripeCustomerId: customerId,
      requestId,
      draftId: draftId || null,
      idempotencyKey,
      deliveryPayload,
    });
    return {
      paymentSessionId: sessionRef.id,
      quoteId,
      userId: sender.uid,
      amountDue: total,
      rothEnabled,
      rothAppliedAmount: split.walletContributionGbp,
      remainingAmount: split.remainingGbp,
      currency: "GBP",
      status: "checkout_created",
      paymentStatus: "checkout_created",
      paymentMethod: requestedFallback,
      checkoutMode: "web_checkout",
      checkoutUrl: checkoutSession.url,
      checkoutSessionId: checkoutSession.id,
      requestId,
      idempotencyKey,
    };
  }
  if (savedPaymentMethodId) {
    const method = await stripe.paymentMethods.retrieve(savedPaymentMethodId);
    if (method.customer !== customerId) {
      throw new functions.https.HttpsError("permission-denied", "Saved payment method does not belong to this Sender.");
    }
  }
  const idempotencyKey = `sender_booking_${quoteId}`;
  let ephemeralKey;
  let intent;
  try {
    ephemeralKey = await stripe.ephemeralKeys.create(
        {customer: customerId},
        {apiVersion: "2020-08-27"},
    );
    intent = await stripe.paymentIntents.create({
      amount: minorUnits(split.customerPaymentAmount, "gbp"),
      currency: "gbp",
      automatic_payment_methods: {enabled: true},
      customer: customerId,
      payment_method: savedPaymentMethodId || undefined,
      setup_future_usage: savedPaymentMethodId ? undefined : "off_session",
      metadata: {
        paymentType: "delivery",
        userId: sender.uid,
        userEmail: sender.email,
        quoteId,
        paymentSessionId: sessionRef.id,
        rothAppliedAmount: `${split.walletContributionGbp}`,
        remainingAmount: `${split.remainingGbp}`,
        orderTotalGbp: `${split.orderTotalGbp}`,
        fallbackMethod: requestedFallback,
        savedPaymentMethodId,
        billingSource: quote.businessMode === true ? "business_finance" : "sender_finance",
      },
    }, {idempotencyKey});
  } catch (error) {
    throw new functions.https.HttpsError(
        text(error && error.code) === "rate_limit" ? "resource-exhausted" : "failed-precondition",
        safeStripeCheckoutError(error),
        {code: text(error && (error.code || error.type || error.rawType))},
    );
  }
  await sessionRef.set({
    ...sessionBase,
    status: intent.status,
    paymentStatus: intent.status,
    paymentMethod: requestedFallback,
    savedPaymentMethodId: savedPaymentMethodId || null,
    stripeCustomerId: customerId,
    stripePaymentIntentId: intent.id,
    clientSecret: intent.client_secret,
    idempotencyKey,
  });
  return {
    paymentSessionId: sessionRef.id,
    quoteId,
    userId: sender.uid,
    amountDue: total,
    rothEnabled,
    rothAppliedAmount: split.walletContributionGbp,
    remainingAmount: split.remainingGbp,
    currency: "GBP",
    status: intent.status,
    paymentStatus: intent.status,
    paymentMethod: requestedFallback,
    savedPaymentMethodId: savedPaymentMethodId || null,
    stripeCustomerId: customerId,
    customerId,
    ephemeralKeySecret: ephemeralKey.secret,
    stripePaymentIntentId: intent.id,
    clientSecret: intent.client_secret,
  };
});

async function updateSenderPaymentIntentStatus(stripe, intent, eventId = "") {
  const metadata = intent.metadata || {};
  const sessionId = text(metadata.paymentSessionId);
  if (!sessionId) return {updated: false, reason: "missing_session"};
  const db = getFirestore();
  const sessionRef = db.collection("senderPaymentSessions").doc(sessionId);
  const status = text(intent.status);
  const succeeded = status === "succeeded";
  await db.runTransaction(async (transaction) => {
    const snap = await transaction.get(sessionRef);
    if (!snap.exists) return;
    const current = snap.data() || {};
    const alreadyFinal = current.paymentStatus === "succeeded";
    const patch = {
      status,
      paymentStatus: status,
      stripePaymentIntentId: intent.id,
      stripeAmount: Number(intent.amount || 0) / 100,
      stripeCurrency: `${intent.currency || "gbp"}`.toUpperCase(),
      stripeLatestChargeId: typeof intent.latest_charge === "string" ? intent.latest_charge : null,
      lastStripeEventId: eventId || current.lastStripeEventId || null,
      updatedAt: FieldValue.serverTimestamp(),
    };
    if (succeeded) {
      patch.confirmedAt = current.confirmedAt || FieldValue.serverTimestamp();
    }
    transaction.set(sessionRef, patch, {merge: true});
    const paymentRecordRef = db.collection("senderPaymentRecords").doc(intent.id);
    transaction.set(paymentRecordRef, {
      paymentIntentId: intent.id,
      paymentSessionId: sessionId,
      quoteId: metadata.quoteId || current.quoteId || null,
      userId: metadata.userId || current.userId || null,
      userEmail: metadata.userEmail || current.userEmail || null,
      customerId: intent.customer || current.stripeCustomerId || null,
      amount: Number(intent.amount || 0) / 100,
      currency: `${intent.currency || "gbp"}`.toUpperCase(),
      walletAmount: Number(metadata.rothAppliedAmount || current.rothAppliedAmount || 0),
      rothAmount: Number(metadata.rothAppliedAmount || current.rothAppliedAmount || 0),
      stripeAmount: Number(metadata.remainingAmount || current.remainingAmount || 0),
      paymentMethod: metadata.fallbackMethod || current.paymentMethod || "card",
      status,
      paymentStatus: status,
      latestChargeId: typeof intent.latest_charge === "string" ? intent.latest_charge : null,
      provider: "stripe",
      lastStripeEventId: eventId || null,
      createdAt: current.createdAt || FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    if (succeeded && !alreadyFinal && Number(metadata.rothAppliedAmount || current.rothAppliedAmount || 0) > 0) {
      const walletTxRef = db.collection("senderPaymentWalletDebits").doc(sessionId);
      transaction.set(walletTxRef, {
        paymentSessionId: sessionId,
        paymentIntentId: intent.id,
        userId: metadata.userId || current.userId || null,
        userEmail: metadata.userEmail || current.userEmail || null,
        amount: Number(metadata.rothAppliedAmount || current.rothAppliedAmount || 0),
        status: "pending_wallet_debit",
        createdAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    }
  });
  const amount = Number(metadata.rothAppliedAmount || 0);
  if (succeeded && amount > 0) {
    logSenderPaymentStage("roth_debit_deferred_until_delivery_creation", {
      userId: metadata.userId,
      quoteId: metadata.quoteId || null,
      paymentSessionId: sessionId,
      stripePaymentIntentId: intent.id,
      amount,
    });
  }
  return {updated: true, status};
}

async function handleSenderPaymentIntent(stripe, intent, eventId = "") {
  const metadata = intent && intent.metadata ? intent.metadata : {};
  const paymentType = text(metadata.paymentType || metadata.type);
  const sessionId = text(metadata.paymentSessionId);
  if (paymentType !== "delivery" && paymentType !== "sender_delivery_payment") {
    return {handled: false, reason: "not_sender_delivery_payment"};
  }
  if (!sessionId) return {handled: false, reason: "missing_payment_session"};
  const db = getFirestore();
  const sessionRef = db.collection("senderPaymentSessions").doc(sessionId);
  const sessionSnap = await sessionRef.get();
  if (!sessionSnap.exists) {
    throw new Error("Sender payment session was not found.");
  }
  const payment = sessionSnap.data() || {};
  if (intent.status === "succeeded") {
    const expectedAmount = money(payment.remainingAmount || metadata.remainingAmount || 0);
    const paidAmount = money(Number(intent.amount || 0) / 100);
    const expectedCurrency = text(payment.currency || metadata.currency || "gbp").toLowerCase();
    const paidCurrency = text(intent.currency || "gbp").toLowerCase();
    const expectedUserId = text(payment.userId || metadata.userId);
    const metadataUserId = text(metadata.userId || payment.userId);
    if (!expectedUserId || expectedUserId !== metadataUserId) {
      throw new Error("Sender PaymentIntent metadata does not match payment session owner.");
    }
    if (paidCurrency !== expectedCurrency) {
      throw new Error("Sender PaymentIntent currency does not match payment session.");
    }
    if (paidAmount !== expectedAmount) {
      throw new Error("Sender PaymentIntent amount does not match payment session.");
    }
  }
  const statusResult = await updateSenderPaymentIntentStatus(
      stripe,
      intent,
      eventId,
  );
  if (intent.status !== "succeeded") {
    return {
      handled: true,
      status: intent.status,
      paymentSessionId: sessionId,
      updated: statusResult.updated,
    };
  }
  const sender = {
    uid: payment.userId || metadata.userId,
    email: payment.userEmail || metadata.userEmail || "",
    name: payment.userName || "",
  };
  if (!sender.uid) {
    throw new Error("Sender payment session owner is missing.");
  }
  const delivery = await createPaidDeliveryFromSession(stripe, sender, {
    ...(payment.deliveryPayload || {}),
    requestId: payment.requestId || metadata.requestId,
    quoteId: payment.quoteId || metadata.quoteId,
    paymentSessionId: sessionId,
    draftId: payment.draftId || null,
    idempotencyKey: payment.idempotencyKey || metadata.idempotencyKey,
  });
  await db.collection("senderPaymentSessions").doc(sessionId).set({
    status: "succeeded",
    paymentStatus: "succeeded",
    deliveryId: delivery.deliveryId || delivery.requestId || null,
    requestId: delivery.requestId || null,
    webhookCompletedAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  return {
    handled: true,
    status: intent.status,
    paymentSessionId: sessionId,
    requestId: delivery.requestId || null,
    deliveryId: delivery.deliveryId || delivery.requestId || null,
    idempotent: delivery.idempotent === true,
  };
}

function geoData(point = {}) {
  const lat = Number(point.lat || point.latitude || 0);
  const lng = Number(point.lng || point.longitude || 0);
  return {
    geopoint: new GeoPoint(lat, lng),
    geohash: "",
  };
}

function stableId(value) {
  return crypto.createHash("sha256").update(`${value || ""}`).digest("hex").slice(0, 32);
}

function sixDigitPin() {
  return `${crypto.randomInt(100000, 1000000)}`;
}

function privateVanguardPinFields(vanguardFields) {
  if (vanguardFields.vanguardProtocolEnabled !== true) return null;
  const collectionPin = sixDigitPin();
  let deliveryPin = sixDigitPin();
  while (deliveryPin === collectionPin) deliveryPin = sixDigitPin();
  return {
    vanguardProtocolEnabled: true,
    vanguardProtection: {
      enabled: true,
      collectionPin,
      deliveryPin,
    },
    collectionPin,
    deliveryPin,
    collectionPinAttemptCount: 0,
    deliveryPinAttemptCount: 0,
    vanguardReviewRequired: false,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };
}

async function createPaidDeliveryFromSession(stripe, sender, data) {
  const quoteId = text(data.quoteId);
  const paymentSessionId = text(data.paymentSessionId);
  logSenderPaymentStage("delivery_creation_started", {
    userId: sender.uid,
    quoteId,
    paymentSessionId,
    hasStripe: Boolean(stripe),
  });
  if (!quoteId || !paymentSessionId) {
    throw new functions.https.HttpsError("invalid-argument", "Confirmed payment and quote are required.");
  }
  const db = getFirestore();
  const [quoteSnap, paymentSnap] = await Promise.all([
    db.collection("senderBookingQuotes").doc(quoteId).get(),
    db.collection("senderPaymentSessions").doc(paymentSessionId).get(),
  ]);
  if (!quoteSnap.exists || quoteSnap.data().userId !== sender.uid) {
    throw new functions.https.HttpsError("not-found", "Booking quote not found.");
  }
  if (!paymentSnap.exists || paymentSnap.data().userId !== sender.uid) {
    throw new functions.https.HttpsError("not-found", "Payment session not found.");
  }
  if (paymentSnap.data().quoteId !== quoteId) {
    throw new functions.https.HttpsError("failed-precondition", "Payment and quote do not match.", {reason: "payment_quote_mismatch"});
  }
  let payment = paymentSnap.data();
  const rothOnlyPayment = payment.paymentMethod === "roth" &&
    Number(payment.remainingAmount || 0) <= 0 &&
    Number(payment.rothAppliedAmount || 0) > 0 &&
    !payment.stripePaymentIntentId &&
    !payment.checkoutSessionId;
  const rothOnlyPaymentAuthorized = rothOnlyPayment &&
    `${payment.paymentStatus || payment.status}` === "payment_processing";
  if (`${payment.paymentStatus || payment.status}` !== "succeeded" && payment.stripePaymentIntentId) {
    const intent = await stripe.paymentIntents.retrieve(payment.stripePaymentIntentId);
    if (intent.status === "succeeded") {
      await updateSenderPaymentIntentStatus(stripe, intent, `callable_${paymentSessionId}`);
      payment = {...payment, status: "succeeded", paymentStatus: "succeeded"};
    }
  }
  if (`${payment.paymentStatus || payment.status}` !== "succeeded" &&
      !rothOnlyPaymentAuthorized) {
    const message = rothOnlyPayment ?
      "Roth payment session must be authorised before delivery creation." :
      "Stripe payment must be confirmed before delivery creation.";
    throw new functions.https.HttpsError("failed-precondition", message, {
      reason: rothOnlyPayment ? "roth_session_unconfirmed" : "stripe_payment_unconfirmed",
      paymentSessionId,
      quoteId,
    });
  }
  const quote = quoteSnap.data();
  const deliveryPayload = {
    ...data,
    parcel: data.parcel || {},
  };
  const quoteSnapshot = assertQuotePayloadMatchesSnapshot(quote, deliveryPayload);
  const eligibility = normalDispatchEligibilityForDeliveryPayload(deliveryPayload);
  if (eligibility.normalCheckoutEligible !== true) {
    await recordIneligiblePaidCheckoutReview(db, {
      paymentSessionId,
      quoteId,
      userId: sender.uid,
      reason: eligibility.reason,
      eligibility,
    });
    throw new functions.https.HttpsError(
        "failed-precondition",
        "This paid booking requires review before normal dispatch.",
        {
          reason: eligibility.reason,
          compliance: eligibility.compliance,
          serviceability: eligibility.serviceability,
        },
    );
  }
  const draftId = text(data.draftId);
  const idempotencyKey = text(data.idempotencyKey) ||
    stableId(`${sender.uid}:${draftId || "no-draft"}:${quoteId}:${paymentSessionId}`);
  const idempotencyRef = db.collection("senderDeliveryIdempotency").doc(idempotencyKey);
  const replay = await idempotencyRef.get();
  if (replay.exists) {
    const existing = replay.data() || {};
    return {
      requestId: existing.requestId,
      deliveryId: existing.deliveryId || existing.requestId,
      idempotent: true,
      idempotencyKey,
    };
  }
  const requestId = text(data.requestId) || `sender_${stableId(`${sender.uid}:${draftId || quoteId}:${paymentSessionId}`)}`;
  const deliveryRef = db.collection("deliveryRequests").doc(requestId);
  const rothAppliedAmount = money(payment.rothAppliedAmount || 0);
  const walletDebitRequired = rothAppliedAmount > 0 &&
    payment.rothDebitStatus !== "completed";
  const walletDebitRef = db.collection("walletTransactions").doc(`wallet_delivery_${paymentSessionId}`);
  const {walletId, walletRef, senderWalletRef} = walletRefsForSender(db, sender);
  const pickup = data.pickup || {};
  const dropoff = data.dropoff || {};
  const parcel = data.parcel || {};
  const clientIris = data.iris || {};
  const forcedVanguardRequired = quote.vanguardRequired === true ||
    quote.businessMode === true ||
    text(quote.sourceModule || quote.serviceType || quote.type)
        .toLowerCase()
        .includes("health") ||
    text(quote.sourceModule || quote.serviceType || quote.type)
        .toLowerCase()
        .includes("gift");
  const vanguardFields = vanguardProtocol.initialProtocolFields({
    selected: quote.vanguardProtocolEnabled === true,
    required: forcedVanguardRequired,
    irisRequired: forcedVanguardRequired,
    irisRequiredReason: quote.vanguardRequiredReason,
    itemName: parcel.itemName,
    description: parcel.description,
    category: clientIris.category,
  });
  const privateVanguardFields = privateVanguardPinFields(vanguardFields);
  await db.runTransaction(async (transaction) => {
    const reads = [
      transaction.get(deliveryRef),
      transaction.get(idempotencyRef),
    ];
    if (walletDebitRequired) {
      reads.push(transaction.get(walletRef));
      reads.push(transaction.get(walletDebitRef));
      reads.push(transaction.get(senderWalletRef));
    }
    const [existingDelivery, existingIdem, walletSnap, existingDebitSnap, senderWalletSnap] =
      await Promise.all(reads);
    if (existingIdem.exists) return;
    if (existingDelivery.exists) {
      transaction.set(idempotencyRef, {
        idempotencyKey,
        requestId,
        deliveryId: deliveryRef.id,
        userId: sender.uid,
        quoteId,
        paymentSessionId,
        replayedExistingDelivery: true,
        createdAt: FieldValue.serverTimestamp(),
      }, {merge: true});
      return;
    }
    let walletBalanceBefore = null;
    let walletBalanceAfter = null;
    if (walletDebitRequired) {
      if (existingDebitSnap && existingDebitSnap.exists) {
        throw new Error("Roth debit exists without a completed delivery. Please contact support.");
      }
      const wallet = walletSnap && walletSnap.exists ? walletSnap.data() || {} : {};
      const senderWallet = senderWalletSnap && senderWalletSnap.exists ?
        senderWalletSnap.data() || {} : {};
      if (wallet.isFrozen === true) throw new Error("Wallet is frozen.");
      if (senderWallet.status === "frozen" || senderWallet.frozen === true) {
        throw new Error("Wallet is frozen.");
      }
      const legacyBalance = Number(wallet.balance == null ? wallet.rothCredit : wallet.balance);
      const projectionBalance = Number(senderWallet.balance == null ?
        senderWallet.rothCredit : senderWallet.balance);
      const availableBalances = [legacyBalance, projectionBalance]
          .filter((value) => Number.isFinite(value) && value >= 0);
      walletBalanceBefore = money(availableBalances.length ? Math.max(...availableBalances) : 0);
      if (walletBalanceBefore < rothAppliedAmount) {
        throw new Error("Insufficient Roth balance.");
      }
      walletBalanceAfter = money(walletBalanceBefore - rothAppliedAmount);
      logSenderPaymentStage("roth_debit_validated", {
        userId: sender.uid,
        quoteId,
        paymentSessionId,
        amount: rothAppliedAmount,
        walletBalanceBefore,
        walletBalanceAfter,
      });
    }
    const selectedServiceLevel = `${quote.selectedSpeed || "standard"}`.toLowerCase();
    const expressDelivery = selectedServiceLevel === "express";
    const parcelDescription = parcel.description || parcel.itemName || "Parcel";
    const quotePhotoAnalysis = quote.photoAnalysis || null;
    const iris = {
      ...classifyIris({
        description: parcelDescription,
        declaredWeightText: parcel.weightLabel || parcel.weightKg || quote.weightKg || "",
        photoEstimatedWeightKg: quote.photoEstimatedWeightKg || null,
        distanceMiles: quote.distanceMiles || data.distanceMiles || 0,
        speed: selectedServiceLevel,
        vehicleType: clientIris.recommendedVehicle || clientIris.vehicleType || null,
      }),
      serverAuthored: true,
      authority: "backend",
      source: "createSenderPaidDelivery",
      ...(quotePhotoAnalysis ? {photoAnalysis: quotePhotoAnalysis} : {}),
    };
    const irisWeightKg =
      Number(iris.recommendation && iris.recommendation.estimatedWeightKg || parcel.weightKg || 0) || null;
    const riderAliases = riderDisplayAliases({quote, data, vanguardFields});

    transaction.set(deliveryRef, stripUndefined({
      requestId,
      deliveryId: requestId,
      role: "user",
      userId: sender.uid,
      senderId: sender.uid,
      senderName: sender.name,
      senderEmail: sender.email,
      ...(quote.businessMode === true ? {
        businessMode: true,
        businessId: quote.businessId,
        businessAccountId: quote.businessAccountId,
        businessName: quote.businessName,
        billingEmail: quote.billingEmail,
        billingSource: quote.billingSource,
        paymentProfileSource: quote.paymentProfileSource,
      } : {}),
      pickupDetails: {
        fullname: pickup.fullname || sender.name || "Sender",
        phone: "",
        contactMethod: "circum_relay",
        position: geoData(pickup.coordinates),
        moreInformation: pickup.instructions || "",
        locality: pickup.locality || "",
        address: pickup.address || "",
        subAddress: pickup.subAddress || "",
      },
      dropoffDetails: {
        fullname: dropoff.fullname || data.recipient && data.recipient.name || "",
        phone: "",
        contactMethod: "circum_relay",
        position: geoData(dropoff.coordinates),
        moreInformation: dropoff.instructions || data.recipient && data.recipient.deliveryNotes || "",
        locality: dropoff.locality || "",
        address: dropoff.address || "",
        subAddress: dropoff.subAddress || "",
      },
      pickupPosition: geoData(pickup.coordinates),
      pickupAddress: pickup.address || "",
      pickupLocality: pickup.locality || "",
      dropoffAddress: dropoff.address || "",
      dropoffLocality: dropoff.locality || "",
      receiverName: data.recipient && data.recipient.name || dropoff.fullname || "",
      receiverPhone: "",
      recipient: {
        ...(data.recipient || {}),
        phone: "",
        contactMethod: "circum_relay",
      },
      contactMethod: "circum_relay",
      maskedCommunicationOnly: true,
      deliveryTime: data.deliveryTime || {},
      parcel,
      packageDescription: parcelDescription,
      originalDescription: parcelDescription,
      normalizedItemName: parcel.itemName || parcelDescription,
      iris,
      irisDeliveryEstimateId: requestId,
      irisDeliveryEstimate: iris,
      irisEstimatedWeight: irisWeightKg,
      ...(quotePhotoAnalysis ? {
        irisPhotoAnalysisId: quotePhotoAnalysis.analysisId,
        irisPhotoAnalysis: quotePhotoAnalysis,
        photoEstimatedWeightKg: quote.photoEstimatedWeightKg || null,
      } : {}),
      selectedSpeed: quote.selectedSpeed,
      selectedServiceLevel,
      serviceLevel: selectedServiceLevel,
      selectedTier: selectedServiceLevel,
      priority: expressDelivery,
      urgent: expressDelivery,
      riderUrgency: expressDelivery ? "urgent" : "normal",
      riderAlert: expressDelivery ?
        "Express delivery: urgent pickup requested." :
        "",
      matchingPriority: expressDelivery ? "express" : "standard",
      quoteId,
      quoteSchemaVersion: quote.quoteSchemaVersion,
      canonicalQuoteSnapshotHash: quote.canonicalQuoteSnapshotHash,
      quotedAmount: quote.total,
      quotedCurrency: quote.currency,
      authoritativeRouteDistanceMiles: quoteSnapshot.route.distanceMiles,
      paymentSessionId,
      price: quote.total,
      ...riderAliases,
      paidAmount: quote.total,
      paymentStatus: "paid",
      paymentMethod: payment.paymentMethod,
      stripePaymentIntentId: payment.stripePaymentIntentId || null,
      stripeCustomerId: payment.stripeCustomerId || null,
      stripeLatestChargeId: payment.stripeLatestChargeId || null,
      rothAppliedAmount: payment.rothAppliedAmount || 0,
      remainingAmount: payment.remainingAmount || 0,
      pricingBreakdown: quote,
      roadChargePolicyVersion: quote.roadChargePolicyVersion || ROAD_CHARGE_POLICY_VERSION,
      roadChargeBreakdown: quote.roadChargeBreakdown || null,
      roadChargeCustomerContribution: quote.roadChargeCustomerContribution || 0,
      estimatedRoadChargeRecovery: quote.estimatedRoadChargeRecovery || 0,
      roadChargeReimbursement: 0,
      roadChargeCircumContribution: quote.roadChargeCircumContribution || 0,
      roadChargeCircumRevenue: quote.roadChargeCircumRevenue || 0,
      roadChargeMaximumSettlementPence: quote.roadChargeMaximumSettlementPence || 0,
      roadChargeFinancialReservation: quote.roadChargeFinancialReservation || null,
      roadChargeLiabilityKeys: quote.roadChargeBreakdown && quote.roadChargeBreakdown.liabilityKeys || [],
      roadChargeRouteFacts: quote.roadChargeRouteFacts || null,
      quotedVehicleClass: quote.quotedVehicleClass || quote.selectedVehicle,
      requiredVehicleClass: quote.requiredVehicleClass || quote.selectedVehicle,
      currency: "GBP",
      status: "requested",
      deliveryStatus: "requested",
      flowStatus: "requested",
      currentStep: "tracking",
      dispatchStatus: "requested",
      matchingStatus: "available",
      trackingUrl: `/?app=sender&deliveryId=${requestId}`,
      ...vanguardFields,
      dispatchProtocol: {
        vanguard: vanguardFields.vanguardProtocolEnabled === true,
      },
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }));
    if (walletDebitRequired) {
      const now = FieldValue.serverTimestamp();
      const senderWallet = senderWalletSnap && senderWalletSnap.exists ?
        senderWalletSnap.data() || {} : {};
      transaction.set(walletRef, {
        userId: walletId,
        uid: sender.uid,
        userEmail: sender.email,
        normalizedEmail: sender.email,
        balance: walletBalanceAfter,
        rothCredit: walletBalanceAfter,
        currency: "GBP",
        isFrozen: false,
        createdAt: walletSnap && walletSnap.exists ? walletSnap.data().createdAt || now : now,
        updatedAt: now,
      }, {merge: true});
      transaction.set(senderWalletRef, {
        userId: sender.uid,
        balance: walletBalanceAfter,
        rothCredit: walletBalanceAfter,
        currency: "ROTH",
        status: "active",
        frozen: false,
        version: Number(senderWallet.version || 0) + 1,
        createdAt: senderWallet.createdAt || now,
        updatedAt: now,
      }, {merge: true});
      transaction.set(walletDebitRef, {
        id: walletDebitRef.id,
        userId: walletId,
        uid: sender.uid,
        userEmail: sender.email,
        normalizedEmail: sender.email,
        walletId,
        type: "delivery_payment",
        amount: -rothAppliedAmount,
        direction: "debit",
        walletType: "sender",
        balanceType: "rothCredit",
        balanceBefore: walletBalanceBefore,
        balanceAfter: walletBalanceAfter,
        referenceId: paymentSessionId,
        relatedEntityId: requestId,
        notes: "Roth applied to Circum delivery payment.",
        description: "Roth applied to Circum delivery payment.",
        idempotencyKey: walletDebitRef.id,
        createdBy: "system",
        status: "completed",
        paymentProvider: "roth_internal",
        createdAt: now,
        metadata: {
          quoteId,
          paymentSessionId,
          deliveryId: requestId,
          service: "delivery",
          source: "sender_booking_delivery_creation",
        },
      });
      transaction.set(db.collection("senderPaymentSessions").doc(paymentSessionId), {
        rothDebitStatus: "completed",
        rothDebitTransactionId: walletDebitRef.id,
        deliveryId: requestId,
        requestId,
        updatedAt: now,
      }, {merge: true});
    }
    transaction.set(db.collection("deliveryRequestsPrivate").doc(deliveryRef.id), {
      deliveryId: deliveryRef.id,
      requestId,
      senderId: sender.uid,
      privateContactDetails: stripUndefined({
        pickupPhone: pickup.phone || "",
        dropoffPhone: dropoff.phone || data.recipient && data.recipient.phone || "",
        receiverPhone: data.recipient && data.recipient.phone || dropoff.phone || "",
      }),
      ...(privateVanguardFields || {}),
    }, {merge: false});
    transaction.set(idempotencyRef, {
      idempotencyKey,
      requestId,
      deliveryId: deliveryRef.id,
      userId: sender.uid,
      quoteId,
      paymentSessionId,
      draftId: draftId || null,
      createdAt: FieldValue.serverTimestamp(),
    }, {merge: false});
    if (draftId) {
      transaction.set(senderDraftRef(db, sender.uid), {
        status: "converting",
        completed: false,
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    }
  });
  logSenderPaymentStage("delivery_creation_completed", {
    userId: sender.uid,
    quoteId,
    paymentSessionId,
    requestId,
    rothAppliedAmount,
    rothDebitStatus: walletDebitRequired ? "completed" : payment.rothDebitStatus || "not_required",
  });
  let dispatchResult = null;
  try {
    dispatchResult = await dispatchDeliveryRequest({
      db,
      requestId,
      uid: sender.uid,
      source: "createSenderPaidDelivery",
    });
    logSenderPaymentStage("delivery_dispatch_attempted", {
      userId: sender.uid,
      quoteId,
      paymentSessionId,
      requestId,
      deliveryId: deliveryRef.id,
      matchedRiders: Array.isArray(dispatchResult.closestRiders) ?
        dispatchResult.closestRiders.length : 0,
    });
  } catch (error) {
    await db.collection("dispatchInspections").doc(deliveryRef.id).set({
      deliveryId: deliveryRef.id,
      requestId,
      status: "dispatch_failed",
      source: "createSenderPaidDelivery",
      error: text(error && error.message),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    console.error("Sender paid delivery dispatch failed", {
      userId: sender.uid,
      quoteId,
      paymentSessionId,
      requestId,
      deliveryId: deliveryRef.id,
      message: text(error && error.message),
      code: text(error && error.code),
    });
  }
  return {
    requestId,
    deliveryId: deliveryRef.id,
    idempotencyKey,
    dispatchStatus: dispatchResult ? "attempted" : "failed",
  };
}

exports.createSenderPaidDelivery = (stripe) => functions.https.onCall(async (data, context) => {
  try {
    return await createPaidDeliveryFromSession(stripe, requireSender(context), data || {});
  } catch (error) {
    if (error instanceof functions.https.HttpsError) throw error;
    const safe = safeDeliveryCreationError(error);
    throw new functions.https.HttpsError(safe.code, safe.message, {
      reason: safe.reason,
      originalMessage: text(error && error.message),
    });
  }
});

async function finalizeSenderCheckoutSession(stripe, sessionData, eventId = "") {
  const metadata = sessionData.metadata || {};
  const paymentSessionId = text(metadata.paymentSessionId);
  const quoteId = text(metadata.quoteId);
  if (!paymentSessionId || !quoteId) {
    throw new Error("Sender checkout session metadata is incomplete.");
  }
  const db = getFirestore();
  const sessionRef = db.collection("senderPaymentSessions").doc(paymentSessionId);
  const sessionSnap = await sessionRef.get();
  if (!sessionSnap.exists) {
    throw new Error("Sender payment session was not found.");
  }
  const payment = sessionSnap.data() || {};
  if (payment.quoteId !== quoteId || payment.checkoutSessionId !== sessionData.id) {
    throw new Error("Sender checkout session ownership mismatch.");
  }
  const verified = verifiedStripePaidGbpSession(sessionData, {
    ownerId: payment.userId || metadata.userId,
    ownerEmail: payment.userEmail || metadata.userEmail,
    expectedAmountGBP: payment.remainingAmount,
  });
  const sender = {
    uid: payment.userId || metadata.userId,
    email: payment.userEmail || metadata.userEmail || "",
    name: payment.userName || "",
  };
  const payload = payment.deliveryPayload || {};
  const eligibility = normalDispatchEligibilityForDeliveryPayload(payload);
  if (eligibility.normalCheckoutEligible !== true) {
    await recordIneligiblePaidCheckoutReview(db, {
      paymentSessionId,
      quoteId,
      userId: sender.uid,
      reason: eligibility.reason,
      eligibility,
    });
    throw new Error("Paid checkout requires review before normal dispatch.");
  }
  await sessionRef.set({
    status: "succeeded",
    paymentStatus: "succeeded",
    stripeCheckoutSessionId: sessionData.id,
    checkoutSessionId: sessionData.id,
    stripePaymentIntentId: sessionData.payment_intent || payment.stripePaymentIntentId || null,
    stripeAmount: verified.amountGBP,
    stripeCurrency: verified.currency,
    confirmedAt: FieldValue.serverTimestamp(),
    lastStripeEventId: eventId || payment.lastStripeEventId || null,
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  if (Number(payment.rothAppliedAmount || 0) > 0) {
    logSenderPaymentStage("roth_debit_deferred_until_delivery_creation", {
      userId: payment.userId || metadata.userId,
      quoteId,
      paymentSessionId,
      stripeCheckoutSessionId: sessionData.id,
      stripePaymentIntentId: sessionData.payment_intent || null,
      amount: Number(payment.rothAppliedAmount || 0),
    });
  }
  return createPaidDeliveryFromSession(stripe, sender, {
    ...payload,
    requestId: payment.requestId || metadata.requestId,
    quoteId,
    paymentSessionId,
    draftId: payment.draftId || null,
    idempotencyKey: payment.idempotencyKey || metadata.idempotencyKey,
  });
}

exports.finalizeSenderWebCheckout = (stripe) => functions.https.onCall(async (data, context) => {
  const sender = requireSender(context);
  const sessionId = text(data.checkoutSessionId || data.sessionId);
  const paymentSessionId = text(data.paymentSessionId);
  if (!sessionId || !paymentSessionId) {
    throw new functions.https.HttpsError("invalid-argument", "Confirmed checkout session is required.");
  }
  const sessionSnap = await getFirestore().collection("senderPaymentSessions").doc(paymentSessionId).get();
  if (!sessionSnap.exists || sessionSnap.data().userId !== sender.uid) {
    throw new functions.https.HttpsError("not-found", "Sender payment session not found.");
  }
  const sessionData = await retrievePaidCheckoutSession(stripe, sessionId, paymentSessionId);
  try {
    return await finalizeSenderCheckoutSession(stripe, sessionData, `callable_${paymentSessionId}`);
  } catch (error) {
    throw new functions.https.HttpsError("failed-precondition", safePaymentFinalizationError(error));
  }
});

exports.recoverIneligibleSenderDelivery = functions.https.onCall(async (data, context) => {
  const sender = requireSender(context);
  const deliveryId = text(data && (data.deliveryId || data.requestId));
  if (!deliveryId) {
    throw new functions.https.HttpsError("invalid-argument", "Delivery reference is required.");
  }

  const db = getFirestore();
  const deliveryRef = db.collection("deliveryRequests").doc(deliveryId);
  let recovery = null;
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(deliveryRef);
    if (!snapshot.exists) {
      throw new functions.https.HttpsError("not-found", "Delivery was not found.");
    }
    const delivery = snapshot.data() || {};
    const ownerId = text(delivery.senderId || delivery.userId || delivery.customerId);
    if (ownerId !== sender.uid) {
      throw new functions.https.HttpsError("permission-denied", "This delivery does not belong to this account.");
    }

    const currentStatus = text(delivery.status || delivery.deliveryStatus).toLowerCase();
    if (currentStatus === "review_required") {
      recovery = {status: currentStatus, alreadyReview: true};
      return;
    }
    if (["delivered", "completed", "cancelled", "canceled", "failed", "refunded", "archived"].includes(currentStatus)) {
      recovery = {status: currentStatus, alreadyTerminal: true};
      return;
    }
    if (assignedRiderId(delivery) || hasCollectionProof(delivery)) {
      throw new functions.https.HttpsError("failed-precondition", "This delivery has progressed beyond automatic review recovery.");
    }

    const payloadEligibility = normalDispatchEligibilityForDeliveryPayload(delivery);
    if (payloadEligibility.normalCheckoutEligible === true) {
      throw new functions.https.HttpsError("failed-precondition", "This delivery is eligible for normal dispatch.");
    }

    const reason = payloadEligibility.reason || "server_iris_blocked";
    transaction.update(deliveryRef, {
      status: "review_required",
      deliveryStatus: "review_required",
      flowStatus: "review_required",
      dispatchStatus: "review_required",
      matchingStatus: "review_required",
      normalDispatchEligible: false,
      reviewStatus: "manual_review",
      reviewReason: reason,
      reviewRequiredAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    recovery = {status: "review_required", reason, alreadyTerminal: false};
  });

  if (recovery && recovery.status === "review_required" && recovery.alreadyReview !== true) {
    await db.collection("adminAuditLogs").add({
      actionType: "sender_ineligible_delivery_review_recovered",
      recordType: "deliveryRequests",
      recordId: deliveryId,
      deliveryId,
      userId: sender.uid,
      reason: recovery.reason,
      createdAt: FieldValue.serverTimestamp(),
    });
  }
  return {deliveryId, ...recovery};
});

exports.handleSenderCheckoutSession = async (stripe, sessionData, eventId = null) => {
  return finalizeSenderCheckoutSession(stripe, sessionData, eventId || "");
};

exports.updateSenderPaymentIntentStatus = updateSenderPaymentIntentStatus;
exports.handleSenderPaymentIntent = handleSenderPaymentIntent;
exports._private = {
  sanitizeSenderDraftPayload,
  draftExpired,
  draftInactive,
  stableId,
  quotePayload,
  buildCanonicalQuoteSnapshot,
  canonicalQuoteHash,
  quoteComparablePayload,
  assertQuotePayloadMatchesSnapshot,
  QUOTE_SCHEMA_VERSION,
  riderDisplayAliases,
  riderPayoutFromQuote,
  DRAFT_RETENTION_DAYS,
  DRAFT_INACTIVITY_MINUTES,
};
