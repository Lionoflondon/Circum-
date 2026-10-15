/* eslint-disable max-len, require-jsdoc */
"use strict";
// Standalone disposable certification runtime. Never imported by index.js.
const fs = require("node:fs");
const http = require("node:http");
const crypto = require("node:crypto");
const {spawn} = require("node:child_process");
const {validate} = require("./isolated-payment-certification-guard");
validate(process.env);
const incarnation = crypto.randomUUID();
const events = [];
let signingSecret = "";
async function start() {
  const emulator = spawn("java", ["-jar", "/opt/firestore.jar", "--host=127.0.0.1", "--port=8081", "--project_id=demo-pay-cert-20261016"], {stdio: "ignore"});
  emulator.on("exit", () => process.exit(1));
  let ready = false;
  for (let n = 0; n < 120; n++) {
    try {
 const r = await fetch("http://127.0.0.1:8081/"); if (r.status < 500) {
 ready = true; break;
}
} catch (_) {/* emulator boot */}
    await new Promise((r) => setTimeout(r, 500));
  }
  if (!ready) throw new Error("Emulator startup failed");
  const {initializeApp} = require("firebase-admin/app");
  const {getFirestore} = require("firebase-admin/firestore");
  initializeApp({projectId: process.env.GCLOUD_PROJECT});
  const db = getFirestore();
  const stripe = new (require("stripe"))(process.env.STRIPE_SECRET_KEY, {maxNetworkRetries: 0, timeout: 20000});
  if ((await stripe.accounts.retrieve()).id !== process.env.CIRCUM_CERT_ACCOUNT) throw new Error("Sandbox account mismatch");
  const quiet = {info() {}, log() {}, warn() {}, error() {}};
  const processor = require("./stripe-webhook-core").createStripeWebhookProcessor({
    stripe, db, resolveRuntimeConfig: () => ({mode: "test", webhookSecret: signingSecret}),
    assertEventMode: require("./stripe-config").assertStripeEventMode,
    messaging: {send: async () => {
 throw new Error("External messaging forbidden");
}},
    giftsPayment: require("./gifts-payment"), ratingsTipping: require("./ratings-tipping"),
    stripeRefunds: require("./stripe-refunds"), senderBooking: require("./sender-booking"),
    businessPayments: require("./business-payments"), deliveryAdjustmentPayments: require("./delivery-adjustment-checkout"),
    healthPlus: require("./health-plus"), healthMembershipLifecycle: require("./health-membership-lifecycle"),
    rothLedger: require("./roth-ledger"), routeCheckoutSessionCompleted: require("./checkout-session-router").routeCheckoutSessionCompleted, logger: quiet,
  });
  async function rpc(data) {
    if (data.action === "configure") {
      if (!/^whsec_[A-Za-z0-9]+$/.test(data.secret || "")) throw new Error("Signing secret required");
      signingSecret = data.secret; return {configured: true};
    }
    if (data.action === "state") {
      const names = ["businessInvoices", "business_wallets", "deliveryRequests", "deliveryAdjustments", "healthPlusMemberships", "giftRecurringSeries", "giftRecurringRenewals", "giftRequests", "emailQueue", "paymentArtifactReconciliations"];
      const result = {};
      for (const name of names) result[name] = (await db.collection(name).get()).docs.map((d) => ({id: d.id, ...d.data()}));
      return {incarnation, events, records: result};
    }
    if (!/^cert_[a-f0-9]{12}$/.test(data.id || "")) throw new Error("Invalid synthetic fixture ID");
    const id = data.id;
    if (data.action === "business_checkout") {
      await db.doc(`businessAccounts/${id}`).create({ownerUid: id, outstandingInvoiceAmount: 8});
      await db.doc(`business_wallets/${id}`).create({balance: 7, availableBalance: 7, status: "active"});
      await db.doc(`businessInvoices/${id}`).create({businessId: id, total: 8, balanceDue: 8, amountPaid: 0, status: "unpaid", checkoutProtocolVersion: 1});
      const result = await require("./business-checkout-reservations").checkout({db, stripe, invoiceId: id, businessId: id, uid: id, data: {useRoth: true, paymentAmount: 8, returnUrl: process.env.CIRCUM_CERT_ORIGIN + "/return"}});
      return result;
    }
    if (data.action === "adjustment_checkout") {
      await db.doc(`deliveryAdjustments/${id}`).create({senderId: id, bookingId: id, riderId: "cert_rider", status: "awaiting_sender_payment", adminDecision: "approve", additionalAmount: 1, revisedQuote: 9});
      await db.doc(`deliveryRequests/${id}`).create({status: "awaiting_sender_adjustment", preAdjustmentStatus: "accepted"});
      const fixtureStripe = {paymentIntents: stripe.paymentIntents, checkout: {sessions: {retrieve: (...a) => stripe.checkout.sessions.retrieve(...a), create: (params, options) => stripe.checkout.sessions.create({...params, success_url: process.env.CIRCUM_CERT_ORIGIN + "/return", cancel_url: process.env.CIRCUM_CERT_ORIGIN + "/cancel"}, options)}}};
      return require("./delivery-adjustment-checkout").createPayment({db, stripe: fixtureStripe, adjustmentId: id, senderId: id, hosted: true});
    }
    throw new Error("Unknown fixture action");
  }
  const server = http.createServer(async (req, res) => {
    const path = new URL(req.url, "http://localhost").pathname;
    const send = (status, body) => {
res.writeHead(status, {"Content-Type": "application/json", "Cache-Control": "no-store"}); res.end(JSON.stringify(body));
};
    if (path === "/health") return send(200, {certificationOnly: true, mode: "test", emulatorOnly: true, incarnation, configured: !!signingSecret, source: process.env.CIRCUM_SOURCE_SHA});
    if (["/return", "/cancel"].includes(path)) {
      res.writeHead(200, {"Content-Type": "text/html", "Cache-Control": "no-store"});
      return res.end("<title>CIRCUM isolated payment certification</title><h1>Isolated Stripe sandbox return</h1><p>This is a disposable certification fixture. Returning here never marks a payment paid.</p>");
    }
    if (req.method !== "POST" || !["/rpc", "/stripe/webhook"].includes(path)) return send(404, {error: "not_found"});
    if (path === "/rpc") {
      const given = Buffer.from(req.headers.authorization || ""); const expected = Buffer.from("Bearer " + process.env.CIRCUM_CERT_TOKEN);
      if (given.length !== expected.length || !crypto.timingSafeEqual(given, expected)) return send(401, {error: "unauthenticated"});
    }
    let raw = Buffer.alloc(0);
    for await (const part of req) {
raw = Buffer.concat([raw, part]); if (raw.length > 1048576) return send(413, {error: "too_large"});
}
    try {
      if (path === "/rpc") return send(200, {incarnation, result: await rpc(JSON.parse(raw.toString()))});
      if (!signingSecret) return send(503, {error: "not_configured"});
      const result = await processor({rawBody: raw, signature: req.headers["stripe-signature"]});
      let event;
      try {
event = stripe.webhooks.constructEvent(raw, req.headers["stripe-signature"], signingSecret);
} catch (_) {/* canonical handler rejects */}
      events.push({id: event?.id || null, type: event?.type || null, livemode: event?.livemode ?? null, signatureVerified: !!event, status: result.status, result: result.body});
      return send(result.status, result.body);
    } catch (error) {
 return send(400, {error: String(error.message).slice(0, 220)});
}
  });
  server.listen(Number(process.env.PORT || 8080), "0.0.0.0");
  fs.writeFileSync("/tmp/certification-ready", incarnation);
}
start().catch(() => {
console.error("Isolated certification startup rejected"); process.exit(1);
});
