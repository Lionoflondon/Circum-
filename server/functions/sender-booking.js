/* eslint-disable max-len, require-jsdoc */
"use strict";

const functions = require("firebase-functions/v1");
const crypto = require("crypto");
const {getFirestore, FieldValue, GeoPoint, Timestamp} = require("firebase-admin/firestore");
const {calculateWalletCheckout, roundMoney, minorUnits} = require("./wallet-core");
const rothLedger = require("./roth-ledger");
const vanguardProtocol = require("./vanguard-protocol-core");

const BASE_FARE_GBP = 5;
const ADDITIONAL_FARE_PER_MILE_GBP = 1.5;
const SHORT_TRIP_FARE_FLOOR_MILES = 1.6;
const LONG_DISTANCE_THRESHOLD_MILES = 20;
const LONG_DISTANCE_MULTIPLIER = 1.2;
const VANGUARD_ADD_ON_GBP = 1.99;
const DRAFT_SCHEMA_VERSION = 1;
const DRAFT_RETENTION_DAYS = 30;
const MAX_DRAFT_BYTES = 32768;
const MAX_STRING_LENGTH = 1000;
const MAX_DEPTH = 6;
const ALLOWED_STEPS = new Set(["pickup", "dropoff", "recipient", "deliveryTime", "parcel", "iris", "options", "review", "payment"]);
const ALLOWED_TIMING_TYPES = new Set(["now", "scheduled"]);
const ALLOWED_OPTIONS = new Set(["Economy", "Standard", "Express", "economy", "standard", "express"]);
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

function text(value) {
  return `${value || ""}`.trim();
}

function money(value) {
  return roundMoney(Number(value || 0));
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
  const selectedOption = cleanString(deliveryOptions.selectedOption, 80) || "Standard";
  if (!ALLOWED_STEPS.has(step)) {
    throw new functions.https.HttpsError("invalid-argument", "Draft step is not supported.");
  }
  if (!ALLOWED_TIMING_TYPES.has(timingType)) {
    throw new functions.https.HttpsError("invalid-argument", "Delivery time type is not supported.");
  }
  if (!ALLOWED_OPTIONS.has(selectedOption)) {
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
  if (normalized === "economy") return "economy";
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
  if (speed === "economy") return -1.5;
  if (speed === "express") return Math.max(2.99, money(subtotal * 0.2));
  return 0;
}

function quotePayload(data, uid) {
  const selectedSpeed = speedKey(data.selectedSpeed || data.selectedOption);
  const weightKg = Math.max(0.5, Number(data.weightKg || data.parcel && data.parcel.weightKg || 0.5));
  const base = BASE_FARE_GBP;
  const distance = distanceFare(data.distanceMiles);
  const weight = weightSurcharge(weightKg);
  const subtotal = money(base + distance + weight);
  const speed = money(speedAdjustment(subtotal, selectedSpeed));
  const vanguardSelected = data.vanguardProtocolEnabled === true || data.vanguard === true;
  const vanguardRequired = data.iris && data.iris.vanguardRequired === true;
  const vanguard = vanguardSelected || vanguardRequired ? VANGUARD_ADD_ON_GBP : 0;
  const total = money(Math.max(0, subtotal + speed + vanguard));
  const quoteId = text(data.quoteId) || `sender_quote_${uid}_${Date.now()}`;
  return {
    quoteId,
    userId: uid,
    currency: "GBP",
    selectedSpeed,
    weightKg,
    vanguardProtocolEnabled: vanguard > 0,
    vanguardRequired,
    vanguardRequiredReason: data.iris && data.iris.vanguardRequiredReason || "",
    lineItems: [
      {key: "base_delivery", label: "Base delivery", amount: base},
      {key: "distance", label: "Distance", amount: distance},
      {key: "weight", label: "Parcel weight", amount: weight},
      {key: "speed_adjustment", label: `${selectedSpeed[0].toUpperCase()}${selectedSpeed.slice(1)} priority`, amount: speed},
      ...(vanguard > 0 ? [{key: "vanguard", label: "Vanguard Protection", amount: vanguard}] : []),
    ],
    total,
    finalAmount: total,
    amountDue: total,
    pricingSource: "sender_backend_quote_v1",
  };
}

async function walletBalanceForSender(sender) {
  const walletId = (sender.email || sender.uid).trim().toLowerCase();
  const snap = await getFirestore().collection("wallets").doc(walletId).get();
  const wallet = snap.exists ? snap.data() : {};
  return money(wallet.balance == null ? wallet.rothCredit : wallet.balance);
}

async function ensureStripeCustomerForSender(stripe, sender) {
  const db = getFirestore();
  const userRef = db.collection("users").doc(sender.uid);
  const userSnap = await userRef.get();
  const user = userSnap.exists ? userSnap.data() : {};
  if (user.stripeCustomerId || user.customerId) {
    return user.stripeCustomerId || user.customerId;
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

exports.createSenderBookingQuote = functions.https.onCall(async (data, context) => {
  const sender = requireSender(context);
  const db = getFirestore();
  const businessContext = await verifiedBusinessContext(db, sender, data && data.businessContext);
  const quote = quotePayload(data || {}, sender.uid);
  await db.collection("senderBookingQuotes").doc(quote.quoteId).set({
    ...quote,
    ...(businessContext || {}),
    createdAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  return quote;
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
  const total = money(quote.total || quote.finalAmount || quote.amountDue);
  const rothEnabled = data.rothEnabled === true;
  const rothBalance = rothEnabled ? await walletBalanceForSender(sender) : 0;
  const savedPaymentMethodId = text(data.paymentMethodId);
  const requestedFallback = text(data.fallbackMethod) || "card";
  const split = calculateWalletCheckout({
    orderTotalGbp: total,
    walletBalanceGbp: rothEnabled ? rothBalance : 0,
    selectedCurrency: "gbp",
  });
  const sessionRef = db.collection("senderPaymentSessions").doc();
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
    rothEnabled,
    rothAppliedAmount: split.walletContributionGbp,
    remainingAmount: split.remainingGbp,
    currency: "GBP",
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };
  if (!split.stripeRequired) {
    await rothLedger.applyWalletDebit({
      userId: sender.uid,
      userEmail: sender.email,
      amount: split.walletContributionGbp,
      type: "delivery_payment",
      referenceId: sessionRef.id,
      notes: "Roth applied to Circum delivery payment.",
      transactionId: `wallet_delivery_${sessionRef.id}`,
      metadata: {quoteId, service: "delivery", source: "sender_booking_payment"},
    });
    await sessionRef.set({
      ...sessionBase,
      status: "succeeded",
      paymentStatus: "succeeded",
      paymentMethod: "roth",
      confirmedAt: FieldValue.serverTimestamp(),
    });
    return {
      ...sessionBase,
      status: "succeeded",
      paymentStatus: "succeeded",
      paymentMethod: "roth",
    };
  }
  const customerId = await ensureStripeCustomerForSender(stripe, sender);
  if (savedPaymentMethodId && !customerId) {
    throw new functions.https.HttpsError("failed-precondition", "Saved payment method is unavailable.");
  }
  if (savedPaymentMethodId) {
    const method = await stripe.paymentMethods.retrieve(savedPaymentMethodId);
    if (method.customer !== customerId) {
      throw new functions.https.HttpsError("permission-denied", "Saved payment method does not belong to this Sender.");
    }
  }
  const ephemeralKey = await stripe.ephemeralKeys.create(
      {customer: customerId},
      {apiVersion: "2020-08-27"},
  );
  const idempotencyKey = `sender_booking_${quoteId}_${sessionRef.id}`;
  const intent = await stripe.paymentIntents.create({
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
    ...sessionBase,
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
    await rothLedger.applyWalletDebit({
      userId: metadata.userId,
      userEmail: metadata.userEmail,
      amount,
      type: "delivery_payment",
      referenceId: sessionId,
      notes: "Roth applied to Circum delivery payment.",
      transactionId: `wallet_delivery_${sessionId}`,
      metadata: {
        quoteId: metadata.quoteId || null,
        service: "delivery",
        stripePaymentIntentId: intent.id,
        stripeEventId: eventId || null,
      },
    });
  }
  return {updated: true, status};
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

exports.createSenderPaidDelivery = (stripe) => functions.https.onCall(async (data, context) => {
  const sender = requireSender(context);
  const quoteId = text(data.quoteId);
  const paymentSessionId = text(data.paymentSessionId);
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
  let payment = paymentSnap.data();
  if (`${payment.paymentStatus || payment.status}` !== "succeeded" && payment.stripePaymentIntentId) {
    const intent = await stripe.paymentIntents.retrieve(payment.stripePaymentIntentId);
    if (intent.status === "succeeded") {
      await updateSenderPaymentIntentStatus(stripe, intent, `callable_${paymentSessionId}`);
      payment = {...payment, status: "succeeded", paymentStatus: "succeeded"};
    }
  }
  if (`${payment.paymentStatus || payment.status}` !== "succeeded") {
    throw new functions.https.HttpsError("failed-precondition", "Stripe payment must be confirmed before delivery creation.");
  }
  const quote = quoteSnap.data();
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
  const pickup = data.pickup || {};
  const dropoff = data.dropoff || {};
  const parcel = data.parcel || {};
  const iris = data.iris || {};
  const vanguardFields = vanguardProtocol.initialProtocolFields({
    selected: quote.vanguardProtocolEnabled === true,
    required: quote.vanguardRequired === true,
    irisRequired: quote.vanguardRequired === true,
    irisRequiredReason: quote.vanguardRequiredReason,
    itemName: parcel.itemName,
    description: parcel.description,
    category: iris.category,
  });
  await db.runTransaction(async (transaction) => {
    const [existingDelivery, existingIdem] = await Promise.all([
      transaction.get(deliveryRef),
      transaction.get(idempotencyRef),
    ]);
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
    const selectedServiceLevel = `${quote.selectedSpeed || "standard"}`.toLowerCase();
    const parcelDescription = parcel.description || parcel.itemName || "Parcel";
    const irisWeightKg =
      Number(iris.finalBillableWeightKg || iris.irisWeightKg || iris.totalWeightKg || parcel.weightKg || 0) || null;

    transaction.set(deliveryRef, {
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
      phone: pickup.phone || "",
      position: geoData(pickup.coordinates),
      moreInformation: pickup.instructions || "",
      locality: pickup.locality || "",
      address: pickup.address || "",
      subAddress: pickup.subAddress || "",
    },
    dropoffDetails: {
      fullname: dropoff.fullname || data.recipient && data.recipient.name || "",
      phone: dropoff.phone || data.recipient && data.recipient.phone || "",
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
    receiverPhone: data.recipient && data.recipient.phone || dropoff.phone || "",
    recipient: data.recipient || {},
    deliveryTime: data.deliveryTime || {},
    parcel,
    packageDescription: parcelDescription,
    originalDescription: parcelDescription,
    normalizedItemName: parcel.itemName || parcelDescription,
    iris,
    irisDeliveryEstimateId: requestId,
    irisDeliveryEstimate: iris,
    irisEstimatedWeight: irisWeightKg,
    selectedSpeed: quote.selectedSpeed,
    selectedServiceLevel,
    serviceLevel: selectedServiceLevel,
    selectedTier: selectedServiceLevel,
    quoteId,
    paymentSessionId,
    price: quote.total,
    paidAmount: quote.total,
    paymentStatus: "paid",
    paymentMethod: payment.paymentMethod,
    stripePaymentIntentId: payment.stripePaymentIntentId || null,
    stripeCustomerId: payment.stripeCustomerId || null,
    stripeLatestChargeId: payment.stripeLatestChargeId || null,
    rothAppliedAmount: payment.rothAppliedAmount || 0,
    remainingAmount: payment.remainingAmount || 0,
    pricingBreakdown: quote,
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
    });
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
  return {requestId, deliveryId: deliveryRef.id, idempotencyKey};
});

exports.updateSenderPaymentIntentStatus = updateSenderPaymentIntentStatus;
exports._private = {
  sanitizeSenderDraftPayload,
  stableId,
  DRAFT_RETENTION_DAYS,
};
