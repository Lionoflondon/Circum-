/* eslint-disable max-len */
const functions = require("firebase-functions/v1");
const {getFirestore} = require("firebase-admin/firestore");
const stripeConfig = functions.config().stripe || {};
const stripe = require("stripe")(stripeConfig.livekey);
const {
  calculateHealthPlusAmountPence,
  normalizeSchedule,
  buildHealthPlusCheckoutParams,
  buildAdminStatusUpdate,
} = require("./health-plus-core");

function allowCors(res) {
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Headers", "Content-Type");
  res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
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
      successUrl,
      cancelUrl,
    } = req.body;

    if (!bookingId || !profileId) {
      return res.status(400).send({error: "bookingId and profileId are required"});
    }

    const amountPence = calculateHealthPlusAmountPence({
      baseFarePence: Math.round((priceBreakdown?.baseFare || 6) * 100),
      distanceFarePence: Math.round((priceBreakdown?.distanceFare || 3.8) * 100),
      weightSurchargePence: Math.round((priceBreakdown?.weightSurcharge || 0) * 100),
      serviceFeePence: Math.round((priceBreakdown?.serviceFee || 1.2) * 100),
    });
    const recurring = normalizeSchedule(frequency) !== "one_off";

    const params = buildHealthPlusCheckoutParams({
      bookingId,
      profileId,
      email,
      amountPence,
      recurring,
      successUrl: successUrl || "https://circum-app-2797c.web.app/?app=sender&health=success",
      cancelUrl: cancelUrl || "https://circum-app-2797c.web.app/?app=sender&health=cancelled",
    });

    const session = await stripe.checkout.sessions.create(params);
    await getFirestore().collection("healthPlusPayments").doc(bookingId).set({
      bookingId,
      profileId,
      amountPence,
      amount: amountPence / 100,
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
    const {pickupId, status, driverId, adminId, note} = req.body;
    if (!pickupId || !status) {
      return res.status(400).send({error: "pickupId and status are required"});
    }

    const update = buildAdminStatusUpdate(status, driverId);
    if (adminId) update.lastAdminId = adminId;
    if (note) update.adminNote = note;

    const db = getFirestore();
    await db.collection("prescriptionPickups").doc(pickupId).set(update, {merge: true});
    await db.collection("healthPlusUsageEvents").add({
      type: "pickup_status_updated",
      pickupId,
      status,
      driverId: driverId || null,
      adminId: adminId || null,
      note: note || null,
      source: "cloud-functions",
      createdAt: Date.now(),
    });
    return res.send({success: true, pickupId, update});
  } catch (error) {
    console.error("Health+ status update error", error);
    return res.status(500).send({error: error.message});
  }
});
