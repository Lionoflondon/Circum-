/* eslint-disable max-len, require-jsdoc */
"use strict";

const {getFirestore, FieldValue} = require("firebase-admin/firestore");

const ALLOWED_ACTIONS = new Set(["mark_read", "archive", "delete"]);
const ALLOWED_INPUT_KEYS = new Set(["action", "notificationId", "notificationIds"]);
const SENDER_ROLES = new Set(["sender", "shipper"]);

function authorityError(code, message) {
  return Object.assign(new Error(message), {code});
}

function cleanText(value, max = 160) {
  return String(value || "").trim().slice(0, max);
}

function normalizeNotificationIds(value) {
  const raw = Array.isArray(value) ? value : [value];
  return [...new Set(raw.map((entry) => cleanText(entry)).filter(Boolean))].slice(0, 100);
}

function validateInput(data) {
  const input = data && typeof data === "object" && !Array.isArray(data) ? data : {};
  const unexpected = Object.keys(input).filter((key) => !ALLOWED_INPUT_KEYS.has(key));
  if (unexpected.length) {
    throw authorityError("invalid-argument", "Notification state input is not supported.");
  }
  const action = cleanText(input.action, 40);
  const ids = normalizeNotificationIds(input.notificationIds || input.notificationId);
  if (!ids.length) throw authorityError("invalid-argument", "Notification id is required.");
  if (!ALLOWED_ACTIONS.has(action)) {
    throw authorityError("invalid-argument", "Unsupported notification action.");
  }
  return {action, ids};
}

function statePatch(action, current, now) {
  if (action === "mark_read") {
    return current.read === true ? null : {read: true, readAt: now};
  }
  if (action === "archive") {
    if (current.archived === true || current.archivedAt != null || current.deletedAt != null) return null;
    return {archived: true, archivedAt: now};
  }
  return current.deletedAt != null ? null : {deletedAt: now};
}

async function updateSenderNotificationState(data, context, options = {}) {
  const uid = context && context.auth && context.auth.uid;
  if (!uid) throw authorityError("unauthenticated", "Sign in to continue.");

  const {action, ids} = validateInput(data);
  const db = options.db || getFirestore();
  const serverTimestamp = options.serverTimestamp || (() => FieldValue.serverTimestamp());
  const now = serverTimestamp();
  let changed = false;

  await db.runTransaction(async (transaction) => {
    let changedInAttempt = false;
    const refs = ids.map((id) => db.collection("notifications").doc(id));
    const snaps = await Promise.all(refs.map((ref) => transaction.get(ref)));
    const patches = snaps.map((snap) => {
      if (!snap.exists) throw authorityError("not-found", "Notification not found.");
      const notification = snap.data() || {};
      const recipientRole = cleanText(notification.recipientRole || notification.role, 40).toLowerCase();
      if (notification.recipientId !== uid || (recipientRole && !SENDER_ROLES.has(recipientRole))) {
        throw authorityError("permission-denied", "Notification does not belong to this Sender account.");
      }
      return statePatch(action, notification, now);
    });
    patches.forEach((patch, index) => {
      if (!patch) return;
      changedInAttempt = true;
      transaction.set(refs[index], patch, {merge: true});
    });
    if (changedInAttempt) {
      transaction.set(db.collection("senderNotificationEvents").doc(), {
        uid,
        action,
        notificationIds: ids,
        source: "updateSenderNotificationState.cloud_run",
        createdAt: now,
      });
    }
    changed = changedInAttempt;
  });

  return {ok: true, notificationIds: ids, action, changed};
}

module.exports = {
  ALLOWED_ACTIONS,
  ALLOWED_INPUT_KEYS,
  normalizeNotificationIds,
  updateSenderNotificationState,
  validateInput,
};
