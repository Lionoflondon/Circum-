/* eslint-disable max-len */
/* eslint-disable require-jsdoc */
const functions = require("firebase-functions/v1");
const {getFirestore} = require("firebase-admin/firestore");
const {getAuth} = require("firebase-admin/auth");
const stripeConfig = functions.config().stripe || {};
const stripe = require("stripe")(stripeConfig.livekey);
const rothLedger = require("./roth-ledger");
const {calculateWalletCheckout} = require("./wallet-core");
const {
  calculateHealthPlusAmountPence,
  normalizeSchedule,
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

exports.createHealthPlusCheckoutSession = functions.https.onRequest(async (req, res) => {
  allowCors(res);
  if (req.method === "OPTIONS") return res.status(204).send("");
  if (req.method !== "POST") return res.status(405).send({error: "POST required"});

  try {
    const {
      bookingId,
      profileId,
      email,
      frequency,
      priceBreakdown,
      userId,
      paymentCurrency,
      successUrl,
      cancelUrl,
    } = req.body;
    const breakdown = priceBreakdown || {};

    if (!bookingId || !profileId) {
      return res.status(400).send({error: "bookingId and profileId are required"});
    }

    const amountPence = calculateHealthPlusAmountPence({
      baseFarePence: Math.round((breakdown.baseFare || 6) * 100),
      distanceFarePence:
        Math.round((breakdown.distanceFare || 3.8) * 100),
      weightSurchargePence:
        Math.round((breakdown.weightSurcharge || 0) * 100),
      serviceFeePence: Math.round((breakdown.serviceFee || 1.2) * 100),
    });
    const recurring = normalizeSchedule(frequency) !== "one_off";

    const walletUserId = userId || profileId;
    const walletUserEmail = `${email || ""}`.trim().toLowerCase();
    const walletLookupId = walletUserEmail || walletUserId;
    const walletSnap = walletUserId ?
      await getFirestore().collection("wallets").doc(walletLookupId).get() :
      null;
    const wallet = walletSnap && walletSnap.exists ? walletSnap.data() : {};
    const walletBalance = Number(wallet.balance == null ? wallet.rothCredit || 0 : wallet.balance || 0);
    const split = calculateWalletCheckout({
      orderTotalGbp: amountPence / 100,
      walletBalanceGbp: walletBalance,
      selectedCurrency: paymentCurrency || "gbp",
    });
    if (walletUserId && split.walletContributionGbp > 0) {
      await rothLedger.applyWalletDebit({
        userId: walletUserId,
        userEmail: walletUserEmail || null,
        amount: split.walletContributionGbp,
        type: "health_payment",
        referenceId: bookingId,
        notes: "Wallet applied to Health+ checkout.",
        transactionId: `wallet_health_${bookingId}`,
        metadata: {
          orderTotalGbp: split.orderTotalGbp,
          remainingGbp: split.remainingGbp,
          service: "health_plus",
        },
      });
    }
    if (!split.stripeRequired) {
      await getFirestore().collection("healthPlusPayments").doc(bookingId).set({
        bookingId,
        profileId,
        userId: walletUserId || null,
        amountPence,
        amount: amountPence / 100,
        walletContributionGbp: split.walletContributionGbp,
        remainingStripeAmountGbp: 0,
        currency: "GBP",
        paymentStatus: "paid",
        status: "paid",
        paidByWallet: true,
        frequency: normalizeSchedule(frequency),
        updatedAt: Date.now(),
        createdAt: Date.now(),
      }, {merge: true});
      return res.send({
        walletPaidInFull: true,
        amountPence,
        walletContributionGbp: split.walletContributionGbp,
        remainingStripeAmountGbp: 0,
        recurring,
      });
    }
    const params = buildHealthPlusCheckoutParams({
      bookingId,
      profileId,
      email,
      amountPence: split.stripeAmountMinor,
      recurring,
      currency: split.customerPaymentCurrency,
      successUrl: successUrl || "https://circum-app-2797c.web.app/?app=sender&health=success",
      cancelUrl: cancelUrl || "https://circum-app-2797c.web.app/?app=sender&health=cancelled",
    });

    const session = await stripe.checkout.sessions.create(params);
    await getFirestore().collection("healthPlusPayments").doc(bookingId).set({
      bookingId,
      profileId,
      amountPence,
      amount: amountPence / 100,
      walletContributionGbp: split.walletContributionGbp,
      remainingStripeAmountGbp: split.remainingGbp,
      customerPaymentCurrency: split.customerPaymentCurrency,
      customerPaymentAmount: split.customerPaymentAmount,
      currency: "GBP",
      frequency: normalizeSchedule(frequency),
      status: "checkout_created",
      checkoutSessionId: session.id,
      checkoutUrl: session.url,
      updatedAt: Date.now(),
      createdAt: Date.now(),
    }, {merge: true});
    await getFirestore().collection("healthPlusUsageEvents").add({
      type: "checkout_created",
      profileId,
      pickupId: bookingId,
      amountPence,
      amount: amountPence / 100,
      currency: "GBP",
      frequency: normalizeSchedule(frequency),
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
