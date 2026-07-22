/* eslint-disable max-len */
/* eslint-disable require-jsdoc */
const functions = require("firebase-functions/v1");
const {getFirestore} = require("firebase-admin/firestore");
const {getAuth} = require("firebase-admin/auth");
const {FieldValue} = require("firebase-admin/firestore");
const stripeConfig = functions.config().stripe || {};
const {resolveStripeRuntimeConfig} = require("./stripe-config");
const stripe = require("stripe")(resolveStripeRuntimeConfig({config: stripeConfig}).secretKey);
const {
  calculateAuthoritativeHealthPlusPricing,
  healthPlusPricingInputFromBooking,
  buildHealthPlusCheckoutParams,
  buildAdminStatusUpdate,
} = require("./health-plus-core");

function allowCors(res) {
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Headers", "Content-Type, Authorization");
  res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
}

const ADMIN_ROLES = [
  "super_admin",
  "operations_admin",
  "support_agent",
  "finance_admin",
  "driver_manager",
  "owner",
  "admin",
  "support",
  "operations",
];

async function verifyAdminRequest(req) {
  const header = req.headers.authorization || "";
  if (!header.startsWith("Bearer ")) {
    throw new functions.https.HttpsError(
        "unauthenticated",
        "Admin authentication is required.",
    );
  }

  const token = header.substring("Bearer ".length);
  const decoded = await getAuth().verifyIdToken(token);
  const claimsRoles = Array.isArray(decoded.roles) ? decoded.roles : [];
  const claimRole = decoded.role || decoded.adminRole;
  const roles = claimRole ? claimsRoles.concat([claimRole]) : claimsRoles;
  const hasClaimRole = decoded.admin === true ||
    roles.some((role) => ADMIN_ROLES.includes(role));

  if (hasClaimRole) {
    return {
      uid: decoded.uid,
      email: decoded.email || null,
      role: claimRole || roles[0] || "admin",
    };
  }

  const adminDoc = await getFirestore()
      .collection("adminUsers")
      .doc(decoded.uid)
      .get();
  if (!adminDoc.exists) {
    throw new functions.https.HttpsError(
        "permission-denied",
        "Admin access is required.",
    );
  }

  const adminData = adminDoc.data();
  const status = adminData.status || "inactive";
  const role = adminData.role;
  if (status !== "active" || !ADMIN_ROLES.includes(role)) {
    throw new functions.https.HttpsError(
        "permission-denied",
        "Active admin access is required.",
    );
  }

  return {
    uid: decoded.uid,
    email: decoded.email || adminData.email || null,
    role,
  };
}

function sendHttpsError(res, error) {
  if (!(error instanceof functions.https.HttpsError)) {
    return false;
  }
  const status = error.code === "unauthenticated" ? 401 : 403;
  res.status(status).send({error: error.message, code: error.code});
  return true;
}

async function verifySenderRequest(req) {
  const header = req.headers.authorization || "";
  if (!header.startsWith("Bearer ")) {
    throw new functions.https.HttpsError(
        "unauthenticated",
        "Sender authentication is required.",
    );
  }
  const decoded = await getAuth().verifyIdToken(header.substring("Bearer ".length));
  return {
    uid: decoded.uid,
    email: decoded.email || null,
  };
}

function ownsBooking(sender, booking) {
  return booking.senderId === sender.uid || booking.userId === sender.uid;
}

function checkoutBlockedStatus(status) {
  return [
    "cancelled",
    "completed",
    "delivered",
    "expired",
    "paid",
    "failed",
  ].includes(`${status || ""}`.trim().toLowerCase());
}

function submittedAmountPence(breakdown = {}) {
  const total = Number(breakdown.total);
  return Number.isFinite(total) ? Math.round(total * 100) : null;
}

function text(value) {
  return `${value || ""}`.trim();
}

function safeDocId(value) {
  return text(value).replace(/[/.#[\]]/g, "_").slice(0, 900);
}

function requireCallableSender(context) {
  const uid = context.auth && context.auth.uid;
  if (!uid) {
    throw new functions.https.HttpsError("unauthenticated", "Sign in to manage Health+.");
  }
  return {
    uid,
    email: context.auth.token.email || null,
  };
}

function senderOwnsHealthRecord(sender, record = {}) {
  return record.senderId === sender.uid ||
    record.userId === sender.uid ||
    record.profileId === sender.uid;
}

function serverHealthPricingInput(data = {}) {
  const pricingInputs = data.pricingInputs || {};
  return {
    distanceMiles: pricingInputs.distanceMiles,
    medicationWeightKg: pricingInputs.medicationWeightKg,
    frequency: data.frequency,
    subscriptionPlan: data.subscriptionPlan || data.healthPlusPlan,
  };
}

function healthPlusAudit(type, sender, extra = {}) {
  return {
    type,
    actorType: "sender",
    actorId: sender.uid,
    actorEmail: sender.email || null,
    source: "cloud-functions",
    createdAt: new Date(),
    ...extra,
  };
}

exports.createHealthPlusBooking = functions.https.onCall(async (data, context) => {
  const sender = requireCallableSender(context);
  if (data.consentConfirmed !== true) {
    throw new functions.https.HttpsError("failed-precondition", "Prescription consent is required.");
  }

  const fullName = text(data.fullName || context.auth.token.name);
  const email = text(data.email || sender.email).toLowerCase();
  const phoneNumber = text(data.phoneNumber);
  const pharmacyName = text(data.pharmacyName);
  const pharmacyAddress = text(data.pharmacyAddress);
  const deliveryAddress = text(data.deliveryAddress);
  const prescriptionType = text(data.prescriptionType);
  const subscriptionPlan = text(data.subscriptionPlan || data.healthPlusPlan);
  const preferredDay = text(data.preferredDay || data.preferredPickupDay);
  const preferredPickupTime = text(data.preferredPickupTime);
  const frequency = text(data.frequency || "one_off");
  if (!fullName || !email || !email.includes("@") || !phoneNumber || !pharmacyAddress || !deliveryAddress || !preferredPickupTime) {
    throw new functions.https.HttpsError("invalid-argument", "Complete the Health+ profile, pharmacy, delivery address and preferred time.");
  }

  let authoritative;
  try {
    authoritative = calculateAuthoritativeHealthPlusPricing(serverHealthPricingInput(data));
  } catch (error) {
    throw new functions.https.HttpsError("failed-precondition", "Health+ booking requires route distance and medication weight before checkout.");
  }

  const db = getFirestore();
  const idempotencyKey = safeDocId(data.idempotencyKey) ||
    safeDocId(`healthplus_booking_${sender.uid}_${frequency}_${preferredPickupTime}`);
  const idempotencyRef = db.collection("healthPlusBookingIdempotency").doc(idempotencyKey);
  const profileId = sender.uid;
  const profileRef = db.collection("healthPlusProfiles").doc(profileId);
  const pickupRef = db.collection("prescriptionPickups").doc();
  const scheduleRef = frequency === "one_off" ? null : db.collection("recurringPickupSchedules").doc();
  const paymentRef = db.collection("healthPlusPayments").doc(pickupRef.id);

  const result = await db.runTransaction(async (transaction) => {
    const replay = await transaction.get(idempotencyRef);
    if (replay.exists) {
      return {...replay.data(), idempotent: true};
    }

    const now = FieldValue.serverTimestamp();
    const profile = {
      id: profileId,
      senderId: sender.uid,
      userId: sender.uid,
      fullName,
      phoneNumber,
      email,
      pharmacyName,
      pharmacyAddress,
      deliveryAddress,
      notes: text(data.notes),
      prescriptionNotes: text(data.notes),
      prescriptionType,
      subscriptionPlan,
      healthPlusPlan: subscriptionPlan,
      preferredDay,
      preferredPickupDay: preferredDay,
      preferredPickupTime,
      frequency,
      consentConfirmed: true,
      consentAccepted: true,
      source: "cloud-functions",
      updatedAt: now,
    };
    const pickup = {
      id: pickupRef.id,
      profileId,
      senderId: sender.uid,
      userId: sender.uid,
      scheduleId: scheduleRef ? scheduleRef.id : null,
      fullName,
      phoneNumber,
      email,
      pharmacyName,
      pharmacyAddress,
      deliveryAddress,
      notes: text(data.notes),
      prescriptionNotes: text(data.notes),
      prescriptionType,
      subscriptionPlan,
      healthPlusPlan: subscriptionPlan,
      preferredDay,
      preferredTime: preferredPickupTime,
      preferredPickupDay: preferredDay,
      preferredPickupTime,
      scheduledPickupDate: preferredDay,
      scheduledPickupWindow: preferredPickupTime,
      scheduledDropoffDate: preferredDay,
      scheduledDropoffWindow: preferredPickupTime,
      frequency,
      recurring: scheduleRef != null,
      customSchedule: text(data.customSchedule),
      priorityRiderMatching: subscriptionPlan === "priority",
      consentAccepted: true,
      status: "scheduled",
      price: authoritative.amountPence / 100,
      amountPence: authoritative.amountPence,
      currency: "GBP",
      authoritativePricing: authoritative,
      pricingInputs: {
        distanceMiles: authoritative.distanceMiles,
        medicationWeightKg: authoritative.medicationWeightKg,
      },
      type: "health_plus_prescription_pickup",
      source: "cloud-functions",
      auditHistory: [healthPlusAudit("health_plus_pickup_created", sender, {status: "scheduled"})],
      createdAt: now,
      updatedAt: now,
    };
    const payment = {
      id: pickupRef.id,
      profileId,
      pickupId: pickupRef.id,
      senderId: sender.uid,
      userId: sender.uid,
      amount: authoritative.amountPence / 100,
      amountPence: authoritative.amountPence,
      currency: "GBP",
      status: "pending_secure_checkout",
      savedPaymentMethod: data.savedPaymentMethod !== false,
      authoritativePricing: authoritative,
      createdAt: now,
      updatedAt: now,
    };

    transaction.set(profileRef, {...profile, createdAt: now}, {merge: true});
    transaction.set(pickupRef, pickup, {merge: true});
    transaction.set(paymentRef, payment, {merge: true});
    if (scheduleRef) {
      transaction.set(scheduleRef, {
        id: scheduleRef.id,
        profileId,
        senderId: sender.uid,
        userId: sender.uid,
        frequency,
        pharmacyName,
        pharmacyAddress,
        deliveryAddress,
        prescriptionType,
        subscriptionPlan,
        healthPlusPlan: subscriptionPlan,
        preferredDay,
        preferredTime: preferredPickupTime,
        preferredPickupDay: preferredDay,
        preferredPickupTime,
        preferredDayTime: preferredPickupTime,
        prescriptionNotes: text(data.notes),
        consentAccepted: true,
        scheduledPickupDate: preferredDay,
        scheduledPickupWindow: preferredPickupTime,
        scheduledDropoffDate: preferredDay,
        scheduledDropoffWindow: preferredPickupTime,
        customSchedule: text(data.customSchedule),
        paused: false,
        status: "active",
        nextPickupAt: preferredPickupTime,
        createdAt: now,
        updatedAt: now,
        auditHistory: [healthPlusAudit("health_plus_schedule_created", sender, {status: "active"})],
      }, {merge: true});
    }
    transaction.set(db.collection("healthPlusNotifications").doc(), {
      profileId,
      pickupId: pickupRef.id,
      senderId: sender.uid,
      userId: sender.uid,
      type: "pickup_scheduled",
      title: "Health+ pickup scheduled",
      body: "Your prescription pickup has been scheduled.",
      source: "health_plus",
      read: false,
      createdAt: now,
    });
    transaction.set(db.collection("healthPlusUsageEvents").doc(), healthPlusAudit("pickup_created", sender, {
      profileId,
      pickupId: pickupRef.id,
      scheduleId: scheduleRef ? scheduleRef.id : null,
      status: "scheduled",
      amount: authoritative.amountPence / 100,
      currency: "GBP",
    }));
    const replayPayload = {
      profileId,
      pickupId: pickupRef.id,
      scheduleId: scheduleRef ? scheduleRef.id : null,
      amount: authoritative.amountPence / 100,
      amountPence: authoritative.amountPence,
      status: "scheduled",
    };
    transaction.set(idempotencyRef, {
      ...replayPayload,
      senderId: sender.uid,
      createdAt: now,
    }, {merge: true});
    return {...replayPayload, idempotent: false};
  });

  return result;
});

exports.updateSenderHealthPlusBooking = functions.https.onCall(async (data, context) => {
  const sender = requireCallableSender(context);
  const action = text(data.action);
  const db = getFirestore();
  const idempotencyKey = safeDocId(data.idempotencyKey) ||
    safeDocId(`healthplus_${action}_${sender.uid}_${text(data.pickupId || data.scheduleId)}`);
  const idempotencyRef = db.collection("healthPlusBookingIdempotency").doc(idempotencyKey);

  const result = await db.runTransaction(async (transaction) => {
    const replay = await transaction.get(idempotencyRef);
    if (replay.exists) return {...replay.data(), idempotent: true};

    const now = FieldValue.serverTimestamp();
    if (action === "pause_schedule" || action === "resume_schedule" || action === "cancel_schedule") {
      const scheduleId = text(data.scheduleId);
      if (!scheduleId) throw new functions.https.HttpsError("invalid-argument", "Schedule is required.");
      const scheduleRef = db.collection("recurringPickupSchedules").doc(scheduleId);
      const scheduleSnap = await transaction.get(scheduleRef);
      if (!scheduleSnap.exists || !senderOwnsHealthRecord(sender, scheduleSnap.data())) {
        throw new functions.https.HttpsError("permission-denied", "Health+ schedule not found.");
      }
      const paused = action === "pause_schedule" || action === "cancel_schedule";
      const status = action === "cancel_schedule" ? "cancelled" : paused ? "paused" : "active";
      const eventType = action === "cancel_schedule" ? "recurring_pickup_cancelled" :
        paused ? "recurring_pickup_paused" : "recurring_pickup_resumed";
      transaction.set(scheduleRef, {
        paused,
        status,
        ...(action === "cancel_schedule" ? {cancelledAt: now} : {}),
        updatedAt: now,
        auditHistory: FieldValue.arrayUnion(healthPlusAudit(eventType, sender, {
          scheduleId,
          status,
        })),
      }, {merge: true});
      transaction.set(db.collection("healthPlusUsageEvents").doc(), healthPlusAudit(eventType, sender, {
        scheduleId,
        status,
      }));
      transaction.set(idempotencyRef, {status, scheduleId, senderId: sender.uid, createdAt: now}, {merge: true});
      return {status, scheduleId, idempotent: false};
    }

    if (action === "cancel_pickup") {
      const pickupId = text(data.pickupId);
      if (!pickupId) throw new functions.https.HttpsError("invalid-argument", "Pickup is required.");
      const pickupRef = db.collection("prescriptionPickups").doc(pickupId);
      const pickupSnap = await transaction.get(pickupRef);
      if (!pickupSnap.exists || !senderOwnsHealthRecord(sender, pickupSnap.data())) {
        throw new functions.https.HttpsError("permission-denied", "Health+ pickup not found.");
      }
      const pickup = pickupSnap.data();
      if (["collected", "out_for_delivery", "delivered"].includes(`${pickup.status || ""}`)) {
        throw new functions.https.HttpsError("failed-precondition", "This Health+ pickup can no longer be cancelled here.");
      }
      transaction.set(pickupRef, {
        status: "cancelled",
        updatedAt: now,
        auditHistory: FieldValue.arrayUnion(healthPlusAudit("pickup_cancelled", sender, {pickupId, status: "cancelled"})),
      }, {merge: true});
      transaction.set(db.collection("healthPlusUsageEvents").doc(), healthPlusAudit("pickup_cancelled", sender, {
        profileId: pickup.profileId || null,
        pickupId,
        scheduleId: pickup.scheduleId || null,
        status: "cancelled",
      }));
      transaction.set(idempotencyRef, {status: "cancelled", pickupId, senderId: sender.uid, createdAt: now}, {merge: true});
      return {status: "cancelled", pickupId, idempotent: false};
    }

    throw new functions.https.HttpsError("invalid-argument", "Unsupported Health+ action.");
  });

  return result;
});

exports.createHealthPlusCheckoutSession = functions.https.onRequest(async (req, res) => {
  allowCors(res);
  if (req.method === "OPTIONS") return res.status(204).send("");
  if (req.method !== "POST") return res.status(405).send({error: "POST required"});

  try {
    const sender = await verifySenderRequest(req);
    const {
      bookingId,
      profileId,
      email,
      priceBreakdown,
      successUrl,
      cancelUrl,
    } = req.body;

    if (!bookingId || !profileId) {
      return res.status(400).send({error: "bookingId and profileId are required"});
    }

    const db = getFirestore();
    const bookingRef = db.collection("prescriptionPickups").doc(bookingId);
    const profileRef = db.collection("healthPlusProfiles").doc(profileId);
    const paymentRef = db.collection("healthPlusPayments").doc(bookingId);
    const [bookingSnap, profileSnap, paymentSnap] = await Promise.all([
      bookingRef.get(),
      profileRef.get(),
      paymentRef.get(),
    ]);
    if (!bookingSnap.exists) {
      throw new functions.https.HttpsError("not-found", "Health+ booking not found.");
    }
    const booking = bookingSnap.data();
    const profile = profileSnap.exists ? profileSnap.data() : {};
    if (booking.profileId !== profileId) {
      throw new functions.https.HttpsError("permission-denied", "Health+ profile mismatch.");
    }
    if (!ownsBooking(sender, booking) && !ownsBooking(sender, profile)) {
      throw new functions.https.HttpsError("permission-denied", "Health+ booking not found.");
    }
    if (checkoutBlockedStatus(booking.status)) {
      throw new functions.https.HttpsError("failed-precondition", "This Health+ booking cannot be paid.");
    }
    const existingPayment = paymentSnap.exists ? paymentSnap.data() : {};
    if (["paid", "succeeded", "checkout_completed"].includes(`${existingPayment.status || ""}`)) {
      throw new functions.https.HttpsError("failed-precondition", "This Health+ booking has already been paid.");
    }
    if (existingPayment.checkoutSessionId && existingPayment.checkoutUrl) {
      return res.send({
        checkoutUrl: existingPayment.checkoutUrl,
        sessionId: existingPayment.checkoutSessionId,
        amountPence: existingPayment.amountPence,
        recurring: existingPayment.recurring === true,
        idempotent: true,
      });
    }

    let authoritative;
    try {
      authoritative = calculateAuthoritativeHealthPlusPricing(
          healthPlusPricingInputFromBooking(booking, profile),
      );
    } catch (error) {
      await db.collection("healthPlusUsageEvents").add({
        type: "checkout_pricing_failed",
        senderId: sender.uid,
        profileId,
        pickupId: bookingId,
        reason: error.code || "missing_pricing_inputs",
        source: "cloud-functions",
        createdAt: Date.now(),
      });
      throw new functions.https.HttpsError(
          "failed-precondition",
          "Health+ booking requires route distance and medication weight before checkout.",
      );
    }
    const amountPence = authoritative.amountPence;
    const recurring = authoritative.recurring;
    const submittedPence = submittedAmountPence(priceBreakdown || {});
    const discrepancyPence = submittedPence == null ? null : submittedPence - amountPence;

    const params = buildHealthPlusCheckoutParams({
      bookingId,
      profileId,
      email: email || sender.email || profile.email || booking.email,
      amountPence,
      recurring,
      successUrl: successUrl || "https://circum-app-2797c.web.app/?app=sender&health=success",
      cancelUrl: cancelUrl || "https://circum-app-2797c.web.app/?app=sender&health=cancelled",
    });

    const session = await stripe.checkout.sessions.create(params);
    await paymentRef.set({
      bookingId,
      profileId,
      senderId: sender.uid,
      userId: sender.uid,
      amountPence,
      amount: amountPence / 100,
      currency: "GBP",
      frequency: authoritative.frequency,
      recurring,
      subscriptionPlan: authoritative.subscriptionPlan,
      status: "checkout_created",
      checkoutSessionId: session.id,
      checkoutUrl: session.url,
      authoritativePricing: authoritative,
      submittedQuoteAmountPence: submittedPence,
      pricingDiscrepancyPence: discrepancyPence,
      updatedAt: Date.now(),
      createdAt: existingPayment.createdAt || Date.now(),
    }, {merge: true});
    await bookingRef.set({
      authoritativePricing: authoritative,
      paymentStatus: "checkout_created",
      updatedAt: Date.now(),
    }, {merge: true});
    if (discrepancyPence !== null && Math.abs(discrepancyPence) > 1) {
      await db.collection("healthPlusUsageEvents").add({
        type: "checkout_price_discrepancy",
        senderId: sender.uid,
        profileId,
        pickupId: bookingId,
        submittedQuoteAmountPence: submittedPence,
        authoritativeAmountPence: amountPence,
        discrepancyPence,
        source: "cloud-functions",
        createdAt: Date.now(),
      });
    }
    await db.collection("healthPlusUsageEvents").add({
      type: "checkout_created",
      senderId: sender.uid,
      userId: sender.uid,
      profileId,
      pickupId: bookingId,
      amountPence,
      amount: amountPence / 100,
      currency: "GBP",
      frequency: authoritative.frequency,
      recurring,
      source: "cloud-functions",
      createdAt: Date.now(),
    });

    return res.send({
      checkoutUrl: session.url,
      sessionId: session.id,
      amountPence,
      recurring,
    });
  } catch (error) {
    if (sendHttpsError(res, error)) return;
    console.error("Health+ checkout session error", error);
    return res.status(500).send({error: error.message});
  }
});

exports.updateHealthPlusPickupStatus = functions.https.onRequest(async (req, res) => {
  allowCors(res);
  if (req.method === "OPTIONS") return res.status(204).send("");
  if (req.method !== "POST") return res.status(405).send({error: "POST required"});

  try {
    const admin = await verifyAdminRequest(req);
    const {pickupId, status, driverId, adminId, note} = req.body;
    if (!pickupId || !status) {
      return res.status(400).send({error: "pickupId and status are required"});
    }

    const update = buildAdminStatusUpdate(status, driverId);
    update.lastAdminId = admin.uid;
    update.lastAdminRole = admin.role;
    if (note) update.adminNote = note;

    const db = getFirestore();
    await db.collection("prescriptionPickups").doc(pickupId).set(update, {merge: true});
    await db.collection("healthPlusUsageEvents").add({
      type: "pickup_status_updated",
      pickupId,
      status,
      driverId: driverId || null,
      adminId: admin.uid,
      adminEmail: admin.email,
      adminRole: admin.role,
      requestedAdminId: adminId || null,
      note: note || null,
      source: "cloud-functions",
      createdAt: Date.now(),
    });
    return res.send({success: true, pickupId, update});
  } catch (error) {
    if (sendHttpsError(res, error)) return;
    console.error("Health+ status update error", error);
    return res.status(500).send({error: error.message});
  }
});
