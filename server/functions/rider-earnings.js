/* eslint-disable max-len, require-jsdoc */
"use strict";

const {FieldValue} = require("firebase-admin/firestore");

function earningsCreditId(deliveryId) {
  return `delivery_${deliveryId}`;
}

async function creditRiderEarnings({db, riderId, deliveryId, amount, now = FieldValue.serverTimestamp()}) {
  const value = Number(amount);
  if (!riderId || !deliveryId || !Number.isFinite(value) || value <= 0) {
    throw new Error("A rider, delivery and positive earnings amount are required.");
  }
  const paymentRef = db.collection("payments").doc(riderId);
  const creditRef = db.collection("riderEarningsCredits").doc(earningsCreditId(deliveryId));
  return db.runTransaction(async (transaction) => {
    const existing = await transaction.get(creditRef);
    if (existing.exists) return {credited: false, duplicate: true, creditId: creditRef.id};
    transaction.create(creditRef, {
      riderId,
      deliveryId,
      amount: value,
      currency: "GBP",
      type: "delivery_earnings",
      createdAt: now,
    });
    transaction.set(paymentRef, {
      accountBalance: FieldValue.increment(value),
      updatedAt: now,
    }, {merge: true});
    return {credited: true, duplicate: false, creditId: creditRef.id};
  });
}

module.exports = {creditRiderEarnings, earningsCreditId};
