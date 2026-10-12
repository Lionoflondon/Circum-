"use strict";

const {createHash, randomUUID} = require("node:crypto");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {getAuth} = require("firebase-admin/auth");
const {passwordReset} = require("./transactional-email-templates");

const EVENT = "auth_password_reset";
const REQUESTS = "authPasswordResetRequests";
const HOUR_MS = 3600000;
const ACK = Object.freeze({ok: true});
const fail = (code) => Object.assign(new Error("Password recovery unavailable."), {code});
const normalizeEmail = (value) => typeof value === "string" ? value.trim().toLowerCase() : "";

// No Auth lookup occurs in this public path. Known and unknown addresses take
// the same transaction and receive exactly the same acknowledgement.
function createPasswordRecoveryHandler({db, now = Date.now, randomId = randomUUID} = {}) {
  return async (data, context) => {
    if (!context.app || !context.app.appId) throw fail("failed-precondition");
    const email = normalizeEmail(data.email);
    const client = data.client;
    if (!/^[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+$/.test(email) || email.length > 254 ||
        !["sender", "rider"].includes(client) || Object.keys(data).some((key) => !["email", "client"].includes(key))) {
      throw fail("invalid-argument");
    }
    const store = db || getFirestore();
    const timestamp = now();
    const id = `password_reset_${randomId()}`;
    const emailKey = createHash("sha256").update(email).digest("hex");
    const limit = store.collection("authPasswordResetLimits");
    const emailRef = limit.doc(emailKey);
    const globalRef = limit.doc("global");
    await store.runTransaction(async (tx) => {
      const [perEmail, global] = await Promise.all([tx.get(emailRef), tx.get(globalRef)]);
      const current = (snapshot) => {
        const value = snapshot.data() || {};
        return timestamp - Number(value.startedAtMs || 0) < HOUR_MS ? value : {startedAtMs: timestamp, count: 0};
      };
      const e = current(perEmail);
      const g = current(global);
      if (Number(g.count || 0) >= 100) throw fail("resource-exhausted");
      if ((e.lastRequestedAtMs != null && timestamp - e.lastRequestedAtMs < 60000) || Number(e.count || 0) >= 3) return;
      tx.set(globalRef, {startedAtMs: g.startedAtMs, count: Number(g.count || 0) + 1});
      tx.set(emailRef, {startedAtMs: e.startedAtMs, count: Number(e.count || 0) + 1, lastRequestedAtMs: timestamp});
      tx.set(store.collection(REQUESTS).doc(id), {email, client, notificationId: id, status: "active", requestedAtMs: timestamp});
      tx.set(store.collection("emailQueue").doc(id), {
        notificationId: id, eventType: EVENT, templateId: "circum-password-reset", to: email,
        sourceCollection: REQUESTS, sourceDocumentId: id, sourceRecipientField: "email", sourceRequiredStatus: "active",
        senderCategory: "info", provider: "resend", status: "queued", attempts: 0, maxAttempts: 5,
        createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
      });
    });
    return ACK;
  };
}

function brandedRecoveryLink(link, client) {
  const url = new URL(link);
  const code = url.searchParams.get("oobCode") || "";
  if (url.origin !== "https://circum-2797c.firebaseapp.com" || url.pathname !== "/__/auth/action" ||
      url.username || url.password || url.hash || url.searchParams.get("mode") !== "resetPassword" ||
      url.searchParams.getAll("oobCode").length !== 1 || !/^[A-Za-z0-9_-]{20,2048}$/.test(code) ||
      !["sender", "rider"].includes(client)) throw fail("internal");
  // Fragments never reach Hosting access logs or Referer headers.
  return `https://circumuk.com/reset-password/#${new URLSearchParams({mode: "resetPassword", oobCode: code, app: client})}`;
}

async function preparePasswordRecovery({record, source, auth = getAuth(), nowMs = Date.now()}) {
  if (record.sourceCollection !== REQUESTS || record.sourceDocumentId !== record.notificationId ||
      !source || source.notificationId !== record.notificationId || source.status !== "active" ||
      normalizeEmail(source.email) !== normalizeEmail(record.to) || !["sender", "rider"].includes(source.client) ||
      !Number.isFinite(source.requestedAtMs) || nowMs < source.requestedAtMs || nowMs - source.requestedAtMs >= HOUR_MS) {
    return {status: "suppressed", reason: "recovery_request_invalid_or_expired"};
  }
  let user;
  try {
    user = await auth.getUserByEmail(source.email);
  } catch (error) {
    if (error.code === "auth/user-not-found") return {status: "suppressed", reason: "recovery_recipient_unavailable"};
    throw Object.assign(fail("unavailable"), {retryable: true});
  }
  if (user.disabled || normalizeEmail(user.email) !== normalizeEmail(source.email) ||
      (record.recoveryUid && record.recoveryUid !== user.uid)) {
    return {status: "suppressed", reason: "recovery_recipient_unavailable"};
  }
  if (record.recoveryMessage) return {status: "valid", message: record.recoveryMessage, uid: user.uid};
  try {
    const link = await auth.generatePasswordResetLink(user.email);
    return {status: "valid", message: passwordReset({link: brandedRecoveryLink(link, source.client)}), uid: user.uid};
  } catch (_error) {
    throw Object.assign(fail("unavailable"), {retryable: true});
  }
}

module.exports = {EVENT, REQUESTS, HOUR_MS, createPasswordRecoveryHandler, brandedRecoveryLink, preparePasswordRecovery};
