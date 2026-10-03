/* eslint-disable max-len, require-jsdoc */
"use strict";
const http = require("node:http");
const OPERATIONS = Object.freeze({
  createSenderBookingQuote: {owner: "circum-sender-booking-quotes", appCheck: true, sdkEnforced: true},
  goOnline: {owner: "circum-rider-delivery-authority", appCheck: true, sdkAuthFailure: true},
  ensureReferralCode: {owner: "circum-referral-callables", appCheck: false, path: "v1/callable/ensureReferralCode"},
  createSenderSetupIntent: {owner: "circum-account-bootstrap", appCheck: true, sdkEnforced: true},
  detachSenderPaymentMethod: {owner: "circum-account-bootstrap", appCheck: true, sdkEnforced: true},
  setDefaultSenderPaymentMethod: {owner: "circum-account-bootstrap", appCheck: true, sdkEnforced: true},
  saveSenderCheckoutPreference: {owner: "circum-account-bootstrap", appCheck: true, sdkEnforced: true},
  requestSenderWalletDebit: {owner: "circum-account-bootstrap", appCheck: true, sdkEnforced: true},
  redeemGiftCard: {owner: "circum-account-bootstrap", appCheck: true, sdkEnforced: true},
  createGiftPayment: {owner: "circum-gift-payments", appCheck: true, sdkEnforced: true},
  finalizeGiftPayment: {owner: "circum-gift-payments", appCheck: true, sdkEnforced: true},
  giftStoryLanding: {owner: "circum-gift-payments", appCheck: false, allowGuest: true, http: true},
  recordGiftStoryGuestEvent: {owner: "circum-gift-payments", appCheck: false, allowGuest: true, http: true},
  getGiftStoryActionState: {owner: "circum-gift-payments", appCheck: false, allowGuest: true},
  acknowledgeGiftStory: {owner: "circum-gift-payments", appCheck: false},
  saveGiftStoryToVault: {owner: "circum-gift-payments", appCheck: false},
  getSenderGiftStory: {owner: "circum-gift-payments", appCheck: false},
  resolveGiftStoryAccess: {owner: "circum-gift-payments", appCheck: false, allowGuest: true},
  createGiftStoryVideoUpload: {owner: "circum-gift-payments", appCheck: false, allowGuest: true},
  getSenderPaymentMode: {owner: "circum-sender-delivery-payments", appCheck: true, sdkEnforced: true},
  getSenderRothBalance: {owner: "circum-sender-delivery-payments", appCheck: true, sdkEnforced: true},
  getRiderEarningsSummary: {owner: "circum-rider-payouts", appCheck: true, sdkEnforced: true},
  finalizeGiftStoryVideoUpload: {owner: "circum-gift-payments", appCheck: false, allowGuest: true},
  getGiftStoryVideoDownload: {owner: "circum-gift-payments", appCheck: false, allowGuest: true},
  getSenderWalletTransactions: {owner: "circum-account-bootstrap", appCheck: true, sdkEnforced: true},
  completeSenderWalletOnboarding: {owner: "circum-account-bootstrap", appCheck: true, sdkEnforced: true},
  createBusinessAccount: {owner: "circum-business-invoice-payments", appCheck: false},
  getSenderAccountActivity: {owner: "circum-account-bootstrap", appCheck: false},
  exportSenderData: {owner: "circum-account-bootstrap", appCheck: false},
  updateSenderPreferences: {owner: "circum-account-bootstrap", appCheck: false},
  revokeSenderSessions: {owner: "circum-account-bootstrap", appCheck: false},
  verifyRiderAccountAccess: {owner: "circum-account-bootstrap", appCheck: true},
  createBusinessGiftOrder: {owner: "circum-business-invoice-payments", appCheck: true},
});
function createServer({operation = process.env.CIRCUM_CALLABLE_OPERATION, fetchImpl = fetch} = {}) {
  const policy = OPERATIONS[operation];
  if (!policy) throw new Error("Unsupported callable operation.");
  const endpoint = `https://${policy.owner}-j2b7cicfwq-uc.a.run.app/${policy.path || operation}`;
  const maxBody = ["createBusinessGiftOrder", "createGiftPayment", "finalizeGiftPayment"].includes(operation) ? 1024 * 1024 : operation === "createSenderBookingQuote" ? 64 * 1024 : operation === "goOnline" ? 32 * 1024 : 16 * 1024;
  const cors = {"content-type": "application/json; charset=utf-8", "cache-control": "no-store", "access-control-allow-origin": "*", "access-control-allow-headers": "Authorization, Content-Type, X-Firebase-AppCheck", "access-control-allow-methods": operation === "giftStoryLanding" ? "GET, HEAD, POST, OPTIONS" : "POST, OPTIONS"};
  function send(res, status, payload) {
    res.writeHead(status, cors);
    res.end(Buffer.isBuffer(payload) ? payload : JSON.stringify(payload));
  }
  function error(res, status, code, message) {
    send(res, status, {error: {status: code, message}});
  }
  return http.createServer((req, res) => {
    const path = new URL(req.url, "http://localhost").pathname;
    if (req.method === "GET" && path === "/health") return send(res, 200, {status: "ok", operation, owner: policy.owner, source: process.env.CIRCUM_SOURCE_SHA || "unknown"});
    if (!policy.http && !["/", `/${operation}`, `/v1/callable/${operation}`].includes(path)) return error(res, 404, "NOT_FOUND", "Not found.");
    if (policy.http && operation === "recordGiftStoryGuestEvent" && !["/", `/${operation}`].includes(path)) return error(res, 404, "NOT_FOUND", "Not found.");
    const landingSuffix = path.replace(new RegExp(`^/${operation}(?=/|$)`), "");
    if (policy.http && operation === "giftStoryLanding" && !/^\/(?:[A-Za-z0-9_.-]{1,512})?$/.test(landingSuffix || "/")) return error(res, 400, "INVALID_ARGUMENT", "Invalid story path.");
    if (req.method === "OPTIONS") return send(res, 204, "");
    if (req.method !== "POST" && !(operation === "giftStoryLanding" && ["GET", "HEAD"].includes(req.method))) return error(res, 405, "INVALID_ARGUMENT", "POST required.");
    const authorization = req.headers.authorization;
    if ((!policy.allowGuest || authorization) && !/^Bearer\s+\S+$/.test(authorization || "")) return error(res, 401, "UNAUTHENTICATED", "Sign in to continue.");
    const appCheck = req.headers["x-firebase-appcheck"];
    if (policy.appCheck && !policy.sdkEnforced && !String(appCheck || "").trim()) return error(res, policy.sdkAuthFailure ? 401 : 400, policy.sdkAuthFailure ? "UNAUTHENTICATED" : "FAILED_PRECONDITION", "Security verification is required.");
    if (req.method === "POST" && !String(req.headers["content-type"] || "").toLowerCase().startsWith("application/json")) return error(res, 415, "INVALID_ARGUMENT", "JSON required.");
    let size = 0;
    const chunks = [];
    req.on("data", (chunk) => {
      size += chunk.length;
      if (size <= maxBody) chunks.push(chunk);
    });
    req.on("end", async () => {
      if (size > maxBody) return error(res, 413, "INVALID_ARGUMENT", "Request too large.");
      try {
        // The existing owner verifies Firebase Auth/App Check and remains the only business authority.
        const suffix = policy.http ? landingSuffix + new URL(req.url, "http://localhost").search : "";
        const upstream = await fetchImpl(policy.http ? endpoint + (suffix === "/" ? "" : suffix) : endpoint, {
          method: req.method, redirect: "error",
          headers: {...(authorization ? {authorization} : {}), "content-type": req.headers["content-type"], ...(appCheck ? {"x-firebase-appcheck": appCheck} : {})},
          body: ["GET", "HEAD"].includes(req.method) ? undefined : Buffer.concat(chunks), signal: AbortSignal.timeout(55000),
        });
        const body = Buffer.from(await upstream.arrayBuffer());
        console.info("native_callable_proxy_response", {operation, status: upstream.status});
        if (policy.http) {
          res.writeHead(upstream.status, {...cors, "content-type": upstream.headers?.get("content-type") || "application/json; charset=utf-8", "x-robots-tag": "noindex, nofollow, noarchive"}); res.end(body); return;
        }
        return send(res, upstream.status, body);
      } catch {
        // An order or session action may have completed upstream. Never automatically retry it.
        console.error("native_callable_proxy_unavailable", {operation});
        return error(res, 503, "UNAVAILABLE", "The service is temporarily unavailable.");
      }
    });
  });
}
if (require.main === module) createServer().listen(Number(process.env.PORT || 8080), "0.0.0.0");
module.exports = {createServer, OPERATIONS};
