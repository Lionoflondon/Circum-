/* eslint-disable max-len, require-jsdoc */
"use strict";

const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");

const REQUIRED_FIELDS = ["addressLine1", "city", "postcode", "country"];
const ADDRESS_FIELDS = [
  "formattedAddress", "addressLine1", "addressLine2", "city", "county",
  "postcode", "country", "latitude", "longitude", "placeId",
];

function clean(value) {
  const text = `${value == null ? "" : value}`.trim();
  return ["null", "undefined", "[]", "||"].includes(text.toLowerCase()) ? "" : text;
}

function requireSender(context) {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Sign in to manage saved addresses.");
  }
  return context.auth.uid;
}

function canonicalAddress(data) {
  const input = data && data.address || {};
  const address = {};
  for (const field of ADDRESS_FIELDS) {
    if (["latitude", "longitude"].includes(field)) {
      const value = Number(input[field]);
      if (Number.isFinite(value)) address[field] = value;
    } else {
      const value = clean(input[field]);
      if (value) address[field] = value;
    }
  }
  if (!address.formattedAddress) {
    address.formattedAddress = [
      address.addressLine1, address.addressLine2, address.city,
      address.county, address.postcode, address.country,
    ].filter(Boolean).join(", ");
  }
  const missing = REQUIRED_FIELDS.filter((field) => !clean(address[field]));
  if (missing.length) {
    throw new functions.https.HttpsError("invalid-argument", `Address is missing: ${missing.join(", ")}.`);
  }
  return address;
}

exports.saveSenderSavedAddress = functions.https.onCall(async (data, context) => {
  const userId = requireSender(context);
  const db = getFirestore();
  const collection = db.collection("users").doc(userId).collection("savedAddresses");
  const requestedId = clean(data && data.addressId);
  const reference = requestedId ? collection.doc(requestedId) : collection.doc();
  const label = clean(data && data.label).toLowerCase();
  if (!["home", "work", "other"].includes(label)) {
    throw new functions.https.HttpsError("invalid-argument", "Choose Home, Work or Other.");
  }
  const customLabel = clean(data && data.customLabel);
  if (label === "other" && !customLabel) {
    throw new functions.https.HttpsError("invalid-argument", "Add a custom label.");
  }
  const address = canonicalAddress(data);
  const defaultPickup = data && data.isDefaultPickup === true;
  const defaultDropoff = data && data.isDefaultDropoff === true;
  let saved;
  await db.runTransaction(async (transaction) => {
    const all = await transaction.get(collection);
    const existing = all.docs.find((doc) => doc.id === reference.id);
    const now = FieldValue.serverTimestamp();
    if (defaultPickup || defaultDropoff) {
      for (const document of all.docs) {
        if (document.id === reference.id) continue;
        const current = document.data();
        const update = {};
        if (defaultPickup && current.isDefaultPickup === true) update.isDefaultPickup = false;
        if (defaultDropoff && current.isDefaultDropoff === true) update.isDefaultDropoff = false;
        if (Object.keys(update).length) {
          update.updatedAt = now;
          update.version = Number(current.version || 1) + 1;
          transaction.set(document.ref, update, {merge: true});
        }
      }
    }
    saved = {
      id: reference.id,
      userId,
      label,
      customLabel: label === "other" ? customLabel : "",
      ...address,
      deliveryInstructions: clean(data && data.deliveryInstructions),
      isDefaultPickup: defaultPickup,
      isDefaultDropoff: defaultDropoff,
      createdAt: existing ? existing.data().createdAt || now : now,
      updatedAt: now,
      version: Number(existing && existing.data().version || 0) + 1,
    };
    transaction.set(reference, saved, {merge: false});
  });
  return {addressId: reference.id, version: saved.version};
});

exports.deleteSenderSavedAddress = functions.https.onCall(async (data, context) => {
  const userId = requireSender(context);
  const addressId = clean(data && data.addressId);
  if (!addressId) throw new functions.https.HttpsError("invalid-argument", "Address id is required.");
  const reference = getFirestore().collection("users").doc(userId).collection("savedAddresses").doc(addressId);
  const snapshot = await reference.get();
  if (!snapshot.exists) throw new functions.https.HttpsError("not-found", "Saved address not found.");
  await reference.delete();
  return {deleted: true, wasDefaultPickup: snapshot.data().isDefaultPickup === true, wasDefaultDropoff: snapshot.data().isDefaultDropoff === true};
});

exports.canonicalAddress = canonicalAddress;
