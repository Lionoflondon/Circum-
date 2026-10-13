/* eslint-disable max-len, require-jsdoc */
"use strict";
const http = require("node:http");
const {createWebsiteRoth} = require("./website-roth");
function createWebsiteRothServer({service, stripe, webhookSecret, verifyAppCheck, afterFinalize = async () => {}, clientKey = (req) => req.socket.remoteAddress}) {
  return http.createServer(async (req, res) => {
    res.setHeader("Cache-Control", "no-store");
    res.setHeader("Content-Type", "application/json");
    const send = (code, value) => {
res.statusCode = code; res.end(JSON.stringify(value));
};
    if (req.method === "GET" && req.url === "/health") return send(200, {ok: true, environment: "test", sourceSHA: process.env.CIRCUM_SOURCE_SHA || "unknown"});
    if (req.method !== "POST") return send(405, {error: "Method not allowed."});
    const path = req.url.replace(/^\/api\/roth/, "");
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
} catch (_error) {
 return send(400, {error: "Invalid signature."});
}
        if (event.livemode || event.data.object.metadata?.type !== "website_roth_top_up") return send(200, {ignored: true});
        if (["checkout.session.completed", "checkout.session.async_payment_succeeded"].includes(event.type)) {
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
function testRuntimeConfig(env) {
  if (env.WEBSITE_ROTH_ENABLED !== "true" || env.WEBSITE_ROTH_LIVE === "true" || env.STRIPE_MODE !== "test") throw new Error("Only explicitly enabled Stripe TEST is supported.");
  if (env.FIRESTORE_DATABASE_ID !== "roth-website-test") throw new Error("Dedicated TEST database required.");
  if (!/^sk_test_/.test(env.STRIPE_SECRET_KEY || "") || !/^whsec_/.test(env.WEBSITE_ROTH_WEBHOOK_SECRET || "")) throw new Error("TEST credentials required.");
  if ((env.WEBSITE_ROTH_OTP_SECRET || "").length < 32) throw new Error("Dedicated OTP secret required.");
  const allowedUids = new Set((env.WEBSITE_ROTH_TEST_UIDS || "").split(",").map((x) => x.trim()).filter(Boolean));
  if (!allowedUids.size) throw new Error("TEST account allowlist required.");
  return {allowedUids, databaseId: "roth-website-test"};
}
function production() {
  const config = testRuntimeConfig(process.env);
  const {initializeApp} = require("firebase-admin/app");
  const {getFirestore, FieldValue} = require("firebase-admin/firestore");
  const {getAuth} = require("firebase-admin/auth");
  const {getAppCheck} = require("firebase-admin/app-check");
  const app = initializeApp();
  const db = getFirestore(app, config.databaseId);
  const auth = getAuth(app);
  const stripe = require("stripe")(process.env.STRIPE_SECRET_KEY);
  const emails = require("./cloud-run-transactional-email");
  const processReceipt = async (session, eventId) => {
    const result = await emails.processEmailQueueRecord({db, emailId: `website_roth_receipt_${session.id}`, eventId, apiKey: process.env.RESEND_API_KEY});
    if (!["sent", "duplicate"].includes(result.status)) throw new Error("Receipt delivery incomplete.");
  };
  const service = createWebsiteRoth({db, auth, stripe, secret: process.env.WEBSITE_ROTH_OTP_SECRET, live: false, allowedUids: config.allowedUids,
    credit: (args) => require("./roth-ledger").recordRothMovement({...args, db}),
    sendCode: async ({uid, email, code, challengeId}) => {
      const id = `roth_verify_${challengeId}`;
      await db.collection("authVerificationRequests").doc(id).set({uid, email, status: "active", expiresAtMs: Date.now() + 600000});
      await db.collection("emailQueue").doc(id).create({...require("./roth-verification-email").rothVerificationEmail(code), notificationId: id, to: email,
        eventType: "auth_email_verification", templateId: "circum-verify-email", senderCategory: "info", recipientId: uid, recipientRole: "account", sourceCollection: "authVerificationRequests", sourceDocumentId: id, sourceRecipientField: "email", sourceRequiredStatus: "active", status: "queued", attempts: 0, maxAttempts: 1, provider: "resend", createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()});
      const result = await emails.processEmailQueueRecord({db, emailId: id, eventId: id, apiKey: process.env.RESEND_API_KEY});
      if (result.status !== "sent") throw new Error("Verification email unavailable.");
    }});
  return createWebsiteRothServer({service, stripe, webhookSecret: process.env.WEBSITE_ROTH_WEBHOOK_SECRET, afterFinalize: processReceipt,
    verifyAppCheck: async (token) => {
      if (!token) throw Object.assign(new Error("App Check required."), {statusCode: 401});
      try {
        await getAppCheck(app).verifyToken(token);
      } catch (_error) {
        throw Object.assign(new Error("Invalid App Check."), {statusCode: 401});
      }
    }});
}
if (require.main === module) production().listen(Number(process.env.PORT || 8080), "0.0.0.0");
module.exports = {createWebsiteRothServer, testRuntimeConfig};
