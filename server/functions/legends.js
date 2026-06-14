/* eslint-disable max-len */
const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {LEGEND_LIMIT, isEligibleLegendDelivery, legendAwardDecision} = require("./legends-core");

exports.awardLegendOnCompletion = functions.firestore.document("deliveryRequests/{deliveryId}").onUpdate(async (change, context) => {
  if (isEligibleLegendDelivery(change.before.data()) || !isEligibleLegendDelivery(change.after.data())) return null;
  const db = getFirestore();
  const deliveryRef = change.after.ref;
  const counterRef = db.collection("platformStats").doc("legends");

  return db.runTransaction(async (transaction) => {
    const deliverySnapshot = await transaction.get(deliveryRef);
    if (!deliverySnapshot.exists || !isEligibleLegendDelivery(deliverySnapshot.data())) return;
    const delivery = deliverySnapshot.data();
    const userId = `${delivery.senderId || delivery.userId || delivery.customerId || ""}`.trim();
    if (!userId) return;
    const userRef = db.collection("users").doc(userId);
    const [userSnapshot, counterSnapshot] = await Promise.all([
      transaction.get(userRef),
      transaction.get(counterRef),
    ]);
    if (!userSnapshot.exists || userSnapshot.data().isLegend === true) return;
    const counter = counterSnapshot.exists ? counterSnapshot.data() : {};
    const limit = Number(counter.limit || LEGEND_LIMIT);
    const legendNumber = legendAwardDecision({
      delivery,
      user: userSnapshot.data(),
      counter: {...counter, limit},
    });
    if (legendNumber === null) return;

    transaction.set(userRef, {
      isLegend: true,
      legendNumber,
      legendAwardedAt: FieldValue.serverTimestamp(),
      legendSource: "first_completed_delivery",
      legendDeliveryId: context.params.deliveryId,
      legendCelebrationSeenAt: null,
    }, {merge: true});
    transaction.set(counterRef, {
      totalAwarded: legendNumber,
      limit,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    transaction.set(deliveryRef, {
      legendAwarded: true,
      legendNumber,
      legendAwardedTo: userId,
    }, {merge: true});
  });
});
