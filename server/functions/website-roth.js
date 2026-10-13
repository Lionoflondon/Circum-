/* eslint-disable max-len, require-jsdoc */
"use strict";
const crypto = require("node:crypto");
const {walletIdForEmail} = require("./wallet-core");
const {verifiedStripePaidGbpSession, BALANCE_TYPES, TRANSACTION_TYPES} = require("./roth-ledger-core");
const fail = (message) => Object.assign(new Error(message), {statusCode: 400});
const digest = (value) => crypto.createHash("sha256").update(value).digest("hex");
const random = () => crypto.randomBytes(32).toString("hex");
const equal = (a, b) => typeof a === "string" && typeof b === "string" && a.length === b.length && crypto.timingSafeEqual(Buffer.from(a), Buffer.from(b));

function createWebsiteRoth({db, auth, stripe, sendCode, credit, secret, now = Date.now, live = false, returnBase = "https://circumuk.com/roth/"}) {
  if (!secret || secret.length < 32) throw new Error("A dedicated OTP secret of at least 32 characters is required.");
  if (returnBase !== "https://circumuk.com/roth/" && (live || returnBase !== "http://127.0.0.1:8779/roth/")) throw new Error("Unapproved return URL.");
  const mac = (value) => crypto.createHmac("sha256", secret).update(value).digest("hex");
  const challenges = db.collection("websiteRothChallenges");
  const orders = db.collection("websiteRothOrders");
  async function resolve(identifier) {
    try {
      const value = String(identifier || "").trim();
      if (!value || value.length > 180) return null;
      let user;
      if (value.includes("@") && !value.startsWith("@")) user = await auth.getUserByEmail(value.toLowerCase());
      else {
        const result = await db.collection("users").where("username", "==", value.replace(/^@/, "")).limit(2).get();
        if (result.size !== 1) return null;
        user = await auth.getUser(result.docs[0].id);
      }
      if (user.disabled || !user.email) return null;
      const email = user.email.trim().toLowerCase();
      return {uid: user.uid, email, walletId: walletIdForEmail(email)};
    } catch (error) {
      if (error.code === "auth/user-not-found" || error.code === "auth/invalid-email") return null;
      throw error;
    }
  }
  async function throttle(key, maximum, period) {
    const ref = db.collection("websiteRothLimits").doc(mac(key));
    return db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const old = snap.data() || {};
      const active = old.until > now();
      const count = active ? old.count : 0;
      if (count >= maximum) return false;
      tx.set(ref, {count: count + 1, until: active ? old.until : now() + period});
      return true;
    });
  }
  async function request({identifier}, clientKey) {
    const challengeId = random();
    if (!clientKey || !await throttle(`ip:${clientKey}`, 10, 3600000)) return {challengeId};
    const identity = await resolve(identifier);
    if (!identity || !await throttle(`account:${identity.uid}`, 3, 900000)) return {challengeId};
    const code = String(crypto.randomInt(100000, 1000000));
    await challenges.doc(challengeId).create({...identity, codeHash: mac(`${challengeId}:${code}`), expires: now() + 600000, attempts: 0, verified: false});
    await sendCode({...identity, code, challengeId});
    return {challengeId};
  }
  async function verify({challengeId, code}) {
    if (!/^[a-f0-9]{64}$/.test(challengeId || "") || !/^\d{6}$/.test(code || "")) throw fail("Code is invalid or expired.");
    const token = random();
    const ok = await db.runTransaction(async (tx) => {
      const ref = challenges.doc(challengeId);
      const item = (await tx.get(ref)).data();
      if (!item || item.expires <= now() || item.attempts >= 5 || item.verified) return false;
      const valid = equal(item.codeHash, mac(`${challengeId}:${code}`));
      tx.update(ref, {attempts: item.attempts + 1, ...(valid ? {verified: true, tokenHash: digest(token), tokenExpires: now() + 900000} : {})});
      return valid;
    });
    if (!ok) throw fail("Code is invalid or expired.");
    return {token, challengeId};
  }
  async function verified(challengeId, token) {
    if (!/^[a-f0-9]{64}$/.test(challengeId || "") || !/^[a-f0-9]{64}$/.test(token || "")) throw fail("Verification required.");
    const item = (await challenges.doc(challengeId).get()).data();
    if (!item?.verified || item.tokenExpires <= now() || !equal(item.tokenHash, digest(token))) throw fail("Verification required.");
    const user = await auth.getUser(item.uid);
    if (user.disabled || user.email?.trim().toLowerCase() !== item.email) throw fail("Account changed. Verify your email again.");
    return item;
  }
  async function checkout({challengeId, token, amountPence}) {
    if (!Number.isSafeInteger(amountPence) || amountPence < 100 || amountPence > 10000) throw fail("Choose between £1 and £100.");
    const identity = await verified(challengeId, token);
    // One verified challenge owns one immutable order and one Stripe idempotency key.
    const ref = orders.doc(challengeId);
    await db.runTransaction(async (tx) => {
      const item = (await tx.get(ref)).data();
      if (item && item.amountPence !== amountPence) throw fail("A checkout already exists for this amount. Verify again to change it.");
      if (!item) tx.create(ref, {uid: identity.uid, email: identity.email, walletId: identity.walletId, amountPence, created: now(), status: "pending"});
    });
    const session = await stripe.checkout.sessions.create({mode: "payment", payment_method_types: ["card"], client_reference_id: identity.walletId, customer_email: identity.email,
      line_items: [{quantity: 1, price_data: {currency: "gbp", unit_amount: amountPence, product_data: {name: "ROTH top-up"}}}],
      success_url: `${returnBase}?payment=returned`, cancel_url: `${returnBase}?payment=cancelled`,
      metadata: {type: "website_roth_top_up", orderId: challengeId}}, {idempotencyKey: `website_roth_${challengeId}`});
    if (session.livemode !== live) throw fail("Payment environment mismatch.");
    await ref.update({sessionId: session.id});
    return {checkoutUrl: session.url, sessionId: session.id};
  }
  const finalize = (session) => finalizeWebsiteRoth({db, auth, credit, live}, session);
  async function status({challengeId, token}) {
    await verified(challengeId, token);
    const order = (await orders.doc(challengeId).get()).data();
    if (!order?.sessionId) return {status: "pending"};
    // Retrieve from Stripe; query-string success is never proof of payment.
    const session = await stripe.checkout.sessions.retrieve(order.sessionId);
    if (session.payment_status !== "paid") return {status: "pending"};
    return finalize(session);
  }
  return {request, verify, checkout, status, finalize};
}
async function finalizeWebsiteRoth({db, auth, credit, live}, session) {
  const orders = db.collection("websiteRothOrders");
    if (session.metadata?.type !== "website_roth_top_up") return null;
    const id = session.metadata.orderId;
    if (!/^[a-f0-9]{64}$/.test(id || "")) throw fail("Unknown order.");
    const ref = orders.doc(id);
    const order = (await ref.get()).data();
    if (!order || order.sessionId !== session.id || session.livemode !== live || session.mode !== "payment" || session.status !== "complete" || !session.payment_intent || session.client_reference_id !== order.walletId) throw fail("Payment does not match the order.");
    const paid = verifiedStripePaidGbpSession(session, {ownerId: order.walletId, expectedAmountGBP: order.amountPence / 100});
    // Fail closed if an email was reassigned while checkout was open.
    const current = await auth.getUserByEmail(order.email);
    if (current.disabled || current.uid !== order.uid) throw fail("Wallet ownership changed. Payment needs review.");
    await credit({userId: order.walletId, userEmail: order.email, uid: order.uid, amount: paid.amountGBP, balanceType: BALANCE_TYPES.rothCredit, type: TRANSACTION_TYPES.userTopUp,
      reason: "ROTH website top-up", paymentProvider: "stripe", providerTransactionId: session.payment_intent,
      transactionId: `website_roth_${session.id}`, metadata: {source: "website_roth", amountGBP: paid.amountGBP, rothIssued: paid.amountGBP, stripeCheckoutSessionId: session.id}});
    // Durable deterministic outbox: credit retries cannot enqueue a second receipt.
    const notificationId = `website_roth_receipt_${session.id}`;
    const emailRef = db.collection("emailQueue").doc(notificationId);
    const receipt = require("./roth-verification-email").rothPurchaseEmail({quantity: paid.amountGBP, reference: `website_roth_${session.id}`});
    await db.runTransaction(async (tx) => {
      const email = await tx.get(emailRef);
      if (!email.exists) {
tx.create(emailRef, {...receipt, notificationId, to: order.email, recipientId: order.uid, recipientRole: "sender", eventType: "roth_purchase_completed", senderCategory: "info",
        sourceCollection: "websiteRothOrders", sourceDocumentId: id, sourceRecipientField: "email", sourceRequiredStatus: "credited", status: "queued", attempts: 0, maxAttempts: 5, provider: "resend",
        createdAt: require("firebase-admin/firestore").FieldValue.serverTimestamp(), updatedAt: require("firebase-admin/firestore").FieldValue.serverTimestamp()});
}
      tx.update(ref, {status: "credited", emailNotificationId: notificationId});
    });
    return {status: "credited", roth: paid.amountGBP};
  }

module.exports = {createWebsiteRoth, finalizeWebsiteRoth};
