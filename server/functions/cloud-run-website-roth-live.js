/* eslint-disable max-len, require-jsdoc */
"use strict";
const http = require("node:http");
const {createWebsiteRoth} = require("./website-roth");
function createWebsiteRothLiveServer({service, stripe, webhookSecret, verifyAppCheck, afterFinalize = async () => {}, beforeFinalize = async () => {}, isolationVerified = false, publicPurchasesEnabled = false, clientKey = (req) => req.socket.remoteAddress}) {
  return http.createServer(async (req, res) => {
    res.setHeader("Cache-Control", "no-store");
    res.setHeader("Content-Type", "application/json");
    let signedEventId = null;
    const send = (code, value) => {
      if (req.url.endsWith("/webhook")) console.info("website_roth_live_delivery", {eventId: signedEventId, httpStatus: code});
res.statusCode = code; res.end(JSON.stringify(value));
};
    if (req.method === "GET" && req.url === "/health") return send(200, {ok: true, environment: "live", isolationVerified, publicPurchasesEnabled, sourceSHA: process.env.CIRCUM_SOURCE_SHA || "unknown"});
    if (req.method !== "POST") return send(405, {error: "Method not allowed."});
    const path = req.url.replace(/^\/api\/roth-live/, "");
    try {
      const chunks = []; let size = 0;
      for await (const chunk of req) {
size += chunk.length; if (size > 16384) throw new Error("Request too large."); chunks.push(chunk);
}
      const raw = Buffer.concat(chunks);
      if (path === "/webhook") {
        let event;
        try {
 event = stripe.webhooks.constructEvent(raw, req.headers["stripe-signature"], webhookSecret);
          signedEventId = event.id;
} catch (_error) {
 return send(400, {error: "Invalid signature."});
}
        if (!event.livemode || event.data.object.metadata?.type !== "website_roth_top_up") return send(200, {ignored: true});
        if (event.data.object.metadata.websiteRealm !== "live" || event.data.object.metadata.testDatabase) return send(400, {error: "LIVE realm binding required."});
        if (["checkout.session.completed", "checkout.session.async_payment_succeeded"].includes(event.type)) {
          await beforeFinalize(event.data.object);
          await service.finalize(event.data.object);
          await afterFinalize(event.data.object, event.id);
        }
        if (event.type === "checkout.session.async_payment_failed") await service.failed(event.data.object);
        return send(200, {received: true});
      }
      if (!["/request", "/verify", "/checkout", "/status", "/wallet", "/logout", "/cancel"].includes(path)) return send(404, {error: "Not found."});
      await verifyAppCheck(req.headers["x-firebase-appcheck"] || "");
      const input = JSON.parse(raw.toString());
      return send(200, await service[path.slice(1)](input, clientKey(req)));
    } catch (error) {
      // Stripe will retry a failed finalization. Never acknowledge a failed credit.
      return send(path === "/webhook" ? 500 : error.statusCode || 503, {error: error.statusCode ? error.message : "Unable to complete this request. Please try again."});
    }
  });
}

function trustedClientKey(req) {
  // Google ingress appends client and load-balancer addresses; ignore supplied prefixes.
  const chain = String(req.headers["x-forwarded-for"] || "").split(",").map((v) => v.trim()).filter(Boolean);
  const client = chain.length > 1 ? chain[chain.length - 2] : chain[0];
  return require("node:net").isIP(client || "") ? client : req.socket.remoteAddress;
}
function liveRuntimeConfig(env) {
  if (env.FIRESTORE_EMULATOR_HOST || env.FIREBASE_AUTH_EMULATOR_HOST) throw new Error("LIVE runtime cannot use emulators.");
  if (env.WEBSITE_ROTH_LIVE_ENABLED !== "true" || env.STRIPE_MODE !== "live" || env.FIRESTORE_DATABASE_ID !== "(default)") throw new Error("Explicit LIVE default-database binding required.");
  if (!/^sk_live_/.test(env.STRIPE_SECRET_KEY || "") || !/^whsec_/.test(env.WEBSITE_ROTH_WEBHOOK_SECRET || "") || (env.WEBSITE_ROTH_OTP_SECRET || "").length < 32) throw new Error("Separate LIVE credentials required.");
  if (!/^acct_/.test(env.WEBSITE_ROTH_STRIPE_ACCOUNT || "")) throw new Error("Approved merchant binding required.");
  const publicEnabled = env.WEBSITE_ROTH_LIVE_PUBLIC === "true";
  if (publicEnabled && (!/^[a-f0-9]{40}$/.test(env.CIRCUM_SOURCE_SHA || "") || env.WEBSITE_ROTH_PRODUCTION_CERTIFIED_SHA !== env.CIRCUM_SOURCE_SHA)) throw new Error("Exact-source production certification required.");
  const allowedUids = new Set((env.WEBSITE_ROTH_LIVE_UIDS || "").split(",").map((v) => v.trim()).filter(Boolean));
  if (!publicEnabled && !allowedUids.size) throw new Error("Private LIVE certification account allowlist required.");
  const returnBase = publicEnabled ? "https://circumuk.com/roth/" : "https://circumuk.com/roth/live-cert/";
  return {publicEnabled, allowedUids: publicEnabled ? null : allowedUids, returnBase};
}
async function verifyLiveDatabaseIsolation(db, testDb) {
  await db.collection("rothPermissionProbe").doc("nonexistent").get();
  try {
await testDb.collection("rothPermissionProbe").doc("nonexistent").get();
} catch (error) {
    if (error.code === 7) return true;
    throw error;
  }
  throw new Error("LIVE identity must not access TEST financial records.");
}
function assertWalletOwner(snapshot, uid, {requireAvailable = false} = {}) {
  if (!snapshot.exists) return;
  const item = snapshot.data();
  if (item.uid !== uid || (requireAvailable && (item.isFrozen === true || item.frozen === true))) throw Object.assign(new Error("Wallet ownership or availability needs review."), {statusCode: 400});
}
function assertWalletAccounting(wallet, projection) {
  const legacy = wallet?.exists ? wallet.data() : {};
  const sender = projection?.exists ? projection.data() : {};
  const cents = (value) => {
    const number = Number(value ?? 0);
    if (!Number.isFinite(number) || number < 0 || !Number.isSafeInteger(Math.round(number * 100))) throw Object.assign(new Error("Wallet accounting needs review."), {statusCode: 400});
    return Math.round(number * 100);
  };
  const balance = cents(legacy.balance ?? legacy.rothCredit);
  if (legacy.balance != null && legacy.rothCredit != null && balance !== cents(legacy.rothCredit)) throw Object.assign(new Error("Wallet accounting needs review."), {statusCode: 400});
  if (projection?.exists && balance !== cents(sender.balance)) throw Object.assign(new Error("Wallet accounting needs review."), {statusCode: 400});
}
function guardedWalletDatabase(db, uid) {
  return new Proxy(db, {get(target, key) {
    if (key === "runTransaction") {
return (update) => target.runTransaction((tx) => update(new Proxy(tx, {get(transaction, name) {
      if (name === "getAll") {
return async (...refs) => {
        const snapshots = await transaction.getAll(...refs);
        const completed = snapshots.some((s, i) => refs[i].parent.id === "walletTransactions" && s.exists && s.data().uid === uid && s.data().status === "completed");
        snapshots.forEach((s, i) => {
if (["wallets", "senderWallets"].includes(refs[i].parent.id)) assertWalletOwner(s, uid, {requireAvailable: !completed});
});
        const walletIndex = refs.findIndex((r) => r.parent.id === "wallets");
        const projectionIndex = refs.findIndex((r) => r.parent.id === "senderWallets");
        assertWalletAccounting(snapshots[walletIndex], snapshots[projectionIndex]);
        return snapshots;
      };
}
      const value = transaction[name];
      return typeof value === "function" ? value.bind(transaction) : value;
    }})));
}
    const value = target[key];
    return typeof value === "function" ? value.bind(target) : value;
  }});
}
function liveCheckoutProvider(stripe, returnBase) {
  const sessions = stripe.checkout.sessions;
  return new Proxy(stripe, {get(target, key) {
    if (key === "checkout") {
return {sessions: {
      create: (params, options) => sessions.create({...params,
        success_url: returnBase + "?payment=returned", cancel_url: returnBase + "?payment=cancelled",
        metadata: {...params.metadata, websiteRealm: "live"},
        payment_intent_data: {...params.payment_intent_data, metadata: {...params.payment_intent_data.metadata, websiteRealm: "live"}},
      }, options), retrieve: sessions.retrieve.bind(sessions), expire: sessions.expire.bind(sessions),
    }};
}
    return target[key];
  }});
}
async function production() {
  const config = liveRuntimeConfig(process.env);
  const {initializeApp} = require("firebase-admin/app");
  const {getFirestore, FieldValue} = require("firebase-admin/firestore");
  const {getAuth} = require("firebase-admin/auth");
  const {getAppCheck} = require("firebase-admin/app-check");
  const app = initializeApp(); const db = getFirestore(app);
  await verifyLiveDatabaseIsolation(db, getFirestore(app, "roth-website-test"));
  const stripe = require("stripe")(process.env.STRIPE_SECRET_KEY);
  const merchant = await stripe.accounts.retrieve();
  if (merchant.id !== process.env.WEBSITE_ROTH_STRIPE_ACCOUNT || !merchant.charges_enabled) throw new Error("LIVE merchant is not approved or charge-ready.");
  const auth = getAuth(app);
  const checkUser = async (user) => {
    if (config.allowedUids && !config.allowedUids.has(user.uid)) throw Object.assign(new Error("Account not eligible."), {code: "auth/user-not-found"});
    const id = require("./wallet-core").walletIdForEmail(user.email);
    const [wallet, projection] = await Promise.all([db.collection("wallets").doc(id).get(), db.collection("senderWallets").doc(user.uid).get()]);
    assertWalletOwner(wallet, user.uid);
    assertWalletOwner(projection, user.uid);
    assertWalletAccounting(wallet, projection);
    return user;
  };
  const guardedAuth = {getUser: async (uid) => checkUser(await auth.getUser(uid)), getUserByEmail: async (email) => checkUser(await auth.getUserByEmail(email))};
  const emails = require("./cloud-run-transactional-email");
  const service = createWebsiteRoth({db, auth: guardedAuth, stripe: liveCheckoutProvider(stripe, config.returnBase), secret: process.env.WEBSITE_ROTH_OTP_SECRET, live: true, allowedUids: config.allowedUids,
    credit: (args) => require("./roth-ledger").recordRothMovement({...args, db: guardedWalletDatabase(db, args.uid)}),
    sendCode: async ({uid, email, code, challengeId}) => {
      const id = `roth_verify_${challengeId}`;
      await db.collection("authVerificationRequests").doc(id).set({uid, email, status: "active", expiresAtMs: Date.now() + 600000});
      await db.collection("emailQueue").doc(id).create({...require("./roth-verification-email").rothVerificationEmail(code), notificationId: id, to: email,
        eventType: "auth_email_verification", templateId: "circum-verify-email", senderCategory: "info", recipientId: uid, recipientRole: "account", sourceCollection: "authVerificationRequests", sourceDocumentId: id, sourceRecipientField: "email", sourceRequiredStatus: "active", status: "queued", attempts: 0, maxAttempts: 1, provider: "resend", createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()});
      const result = await emails.processEmailQueueRecord({db, emailId: id, eventId: id, apiKey: process.env.RESEND_API_KEY});
      if (result.status !== "sent") throw new Error("Verification email unavailable.");
    }});
  const checkout = service.checkout;
  service.checkout = async (input) => {
    await service.wallet(input); // Verify capability before reading its bound identity.
    const identity = (await db.collection("websiteRothChallenges").doc(input.challengeId).get()).data();
    assertWalletOwner(await db.collection("wallets").doc(identity.walletId).get(), identity.uid, {requireAvailable: true});
    return checkout(input);
  };
  return createWebsiteRothLiveServer({service, stripe, webhookSecret: process.env.WEBSITE_ROTH_WEBHOOK_SECRET, isolationVerified: true, publicPurchasesEnabled: config.publicEnabled, clientKey: trustedClientKey,
    afterFinalize: async (session, eventId) => {
      const result = await emails.processEmailQueueRecord({db, emailId: `website_roth_receipt_${session.id}`, eventId, apiKey: process.env.RESEND_API_KEY});
      if (!["sent", "duplicate"].includes(result.status)) throw new Error("Receipt delivery incomplete.");
    }, verifyAppCheck: async (token) => {
      if (!token) throw Object.assign(new Error("App Check required."), {statusCode: 401});
      try {
await getAppCheck(app).verifyToken(token);
} catch (_error) {
throw Object.assign(new Error("Invalid App Check."), {statusCode: 401});
}
    }});
}
if (require.main === module) {
production().then((server) => server.listen(Number(process.env.PORT || 8080), "0.0.0.0")).catch((error) => {
console.error("ROTH LIVE startup rejected", {errorType: error.code || error.name}); process.exit(1);
});
}
module.exports = {createWebsiteRothLiveServer, liveRuntimeConfig, verifyLiveDatabaseIsolation, assertWalletOwner, guardedWalletDatabase, liveCheckoutProvider, trustedClientKey, assertWalletAccounting};
