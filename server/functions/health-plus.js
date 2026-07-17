/* eslint-disable max-len */
/* eslint-disable require-jsdoc */
const functions = require("firebase-functions/v1");
const {getFirestore} = require("firebase-admin/firestore");
const {getAuth} = require("firebase-admin/auth");
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
