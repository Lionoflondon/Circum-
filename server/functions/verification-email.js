/* eslint-disable max-len, require-jsdoc */
"use strict";
const crypto = require("node:crypto");
const {getAuth} = require("firebase-admin/auth");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const template = require("./templates/verify-email.json");
function fail(code, message) {
  return Object.assign(new Error(message), {code});
}
function buildVerificationEmail(link) {
  const url = new URL(link);
  if (url.protocol !== "https:" || !["circum-2797c.firebaseapp.com", "circumuk.com"].includes(url.hostname) || url.pathname !== "/__/auth/action" || url.searchParams.get("mode") !== "verifyEmail") throw fail("internal", "Invalid verification link.");
  const safeLink = link.replaceAll("&", "&amp;").replaceAll("\"", "&quot;").replaceAll("'", "&#39;").replaceAll("<", "&lt;");
  return {subject: template.subject, html: template.body.replaceAll("%DISPLAY_NAME%", "there").replaceAll("%LINK%", safeLink), text: "Verify your email to continue with Circum. Open the Verify email button in the HTML version of this message. If you did not create a Circum account, ignore this email. The Circum team"};
}
function createVerificationEmailHandler({auth = () => getAuth(), db = () => getFirestore(), now = Date.now, randomId = () => crypto.randomUUID()} = {}) {
  return async (_data, context) => {
    if (!context.auth?.uid) throw fail("unauthenticated", "Sign in to continue.");
    const user = await auth().getUser(context.auth.uid);
    if (user.disabled || !user.email) throw fail("failed-precondition", "A current email address is required.");
    if (user.emailVerified) return {ok: true, alreadyVerified: true};
    const database = db();
    const source = database.collection("authVerificationRequests").doc(user.uid);
    const time = now();
    const id = `verify_email_${user.uid}_${randomId()}`;
    // Reserve before generating a link; retries and concurrent requests cannot flood the provider.
    await database.runTransaction(async (tx) => {
      const old = await tx.get(source);
      if (old.exists && time - Number(old.data().lastRequestedAtMs) < 60000) throw fail("resource-exhausted", "Wait a minute before requesting another verification email.");
      tx.set(source, {uid: user.uid, email: user.email, status: "active", lastRequestedAtMs: time, notificationId: id, updatedAt: FieldValue.serverTimestamp()});
    });
    const link = await auth().generateEmailVerificationLink(user.email);
    const email = buildVerificationEmail(link);
    await database.collection("emailQueue").doc(id).create({...email, notificationId: id, to: user.email, eventType: "auth_email_verification", templateId: "circum-verify-email", senderCategory: "info", recipientId: user.uid, recipientRole: "account", sourceCollection: "authVerificationRequests", sourceDocumentId: user.uid, sourceRecipientField: "email", sourceRequiredStatus: "active", status: "queued", attempts: 0, maxAttempts: 5, provider: "resend", createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()});
    return {ok: true, queued: true};
  };
}
module.exports = {buildVerificationEmail, createVerificationEmailHandler};
