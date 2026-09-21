/* eslint-disable max-len, require-jsdoc */
"use strict";

const http = require("node:http");
const {initializeApp, getApps} = require("firebase-admin/app");
const {getAppCheck} = require("firebase-admin/app-check");
const {getAuth} = require("firebase-admin/auth");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const deviceTokenAuthority = require("./device-token-authority");
const rothLedger = require("./roth-ledger");

const MAX_BODY_BYTES = 32 * 1024;
const ROUTES = new Set(["ensureSenderAccount", "updateSenderPushToken", "updateRiderPushToken", "sendRiderUpdate"]);
const STATUS = {
  "invalid-argument": "INVALID_ARGUMENT",
  unauthenticated: "UNAUTHENTICATED",
  "permission-denied": "PERMISSION_DENIED",
  "failed-precondition": "FAILED_PRECONDITION",
  internal: "INTERNAL",
};

function callableError(code, message) {
  return Object.assign(new Error(message), {code});
}

function clean(value, max = 4096) {
  return String(value || "").trim().slice(0, max);
}

function createHandlers(options = {}) {
  const db = options.db || getFirestore();
  const registerProfileToken = options.registerProfileToken || deviceTokenAuthority.registerProfileToken;
  const serverTimestamp = options.serverTimestamp || (() => FieldValue.serverTimestamp());
  const grantSenderWelcomeRoth = options.grantSenderWelcomeRoth || rothLedger.grantSenderWelcomeRoth;
  return {
    async ensureSenderAccount(_data, context) {
      const uid = context.auth.uid;
      const userRef = db.collection("users").doc(uid);
      const riderRef = db.collection("riderProfiles").doc(uid);
      const adminRef = db.collection("adminUsers").doc(uid);
      const now = serverTimestamp();
      const result = await db.runTransaction(async (transaction) => {
        const [userSnap, riderSnap, adminSnap] = await Promise.all([
          transaction.get(userRef),
          transaction.get(riderRef),
          transaction.get(adminRef),
        ]);
        const existing = userSnap.exists ? userSnap.data() || {} : {};
        const roles = new Set([
          ...(Array.isArray(existing.roles) ? existing.roles : []),
          existing.role,
          existing.userType,
          existing.accountType,
        ].map((entry) => clean(entry, 80).toLowerCase()).filter(Boolean));
        if (roles.has("admin") || roles.has("rider") || riderSnap.exists || adminSnap.exists) {
          if (roles.has("sender") || roles.has("user") || roles.has("customer")) {
            return {
              allowed: true,
              roles: Array.from(roles),
              action: "existing_sender_role_allowed",
              starterRothEligible: clean(existing.starterRothGrantStatus, 80).toLowerCase() === "pending",
              profile: {
                phone: clean(existing.phone || existing.phoneNumber, 80),
                displayName: clean(existing.displayName || existing.name, 180),
              },
            };
          }
          return {allowed: false, roles: Array.from(roles), action: "blocked_conflicting_role"};
        }
        const starterRothEligible = !userSnap.exists || clean(existing.starterRothGrantStatus, 80).toLowerCase() === "pending";
        transaction.set(userRef, {
          uid,
          email: clean(context.auth.token.email, 180),
          role: "user",
          roles: FieldValue.arrayUnion("sender"),
          userType: "sender",
          accountType: "sender",
          status: "active",
          createdAt: userSnap.exists ? existing.createdAt || now : now,
          ...(starterRothEligible ? {
            starterRothGrantStatus: "pending",
            starterRothAmount: rothLedger.SENDER_WELCOME_ROTH_AMOUNT,
          } : {}),
          updatedAt: now,
        }, {merge: true});
        transaction.set(db.collection("senderProfileEvents").doc(), {
          uid,
          action: "sender_account_ensured",
          source: "ensureSenderAccount",
          createdAt: now,
        });
        return {
          allowed: true,
          roles: ["sender"],
          action: userSnap.exists ? "merged_sender_role" : "created_sender_profile",
          starterRothEligible,
          profile: {
            phone: clean(existing.phone || existing.phoneNumber, 80),
            displayName: clean(existing.displayName || existing.name, 180),
          },
        };
      });
      if (result.allowed && result.starterRothEligible) {
        const grant = await grantSenderWelcomeRoth({
          uid,
          email: context.auth.token.email,
          source: "ensureSenderAccount",
        });
        await userRef.set({
          starterRothGrantStatus: "granted",
          starterRothGrantedAt: serverTimestamp(),
          starterRothAmount: rothLedger.SENDER_WELCOME_ROTH_AMOUNT,
          starterRothTransactionId: grant.transactionId,
          updatedAt: serverTimestamp(),
        }, {merge: true});
        result.starterRothGranted = true;
        result.starterRothAmount = grant.amount;
        result.starterRothTransactionId = grant.transactionId;
      }
      delete result.starterRothEligible;
      return {ok: true, ...result};
    },
    async updateSenderPushToken(data, context) {
      const token = clean(data && data.fcmToken);
      if (!token) throw callableError("invalid-argument", "Push token is required.");
      await registerProfileToken({uid: context.auth.uid, role: "sender", token, db});
      await db.collection("senderProfileEvents").doc().set({
        uid: context.auth.uid,
        action: "sender_push_token_updated",
        source: "updateSenderPushToken",
        createdAt: serverTimestamp(),
      });
      return {ok: true};
    },
    async updateRiderPushToken(data, context) {
      const token = clean(data && data.fcmToken);
      if (!token) throw callableError("invalid-argument", "Push token is required.");
      await registerProfileToken({uid: context.auth.uid, role: "rider", token, db});
      await db.collection("riderOnboardingEvents").doc().set({
        type: "rider_push_token_updated",
        riderId: context.auth.uid,
        actorType: "rider",
        actorId: context.auth.uid,
        actorEmail: context.auth.token.email || null,
        source: "cloud-run-token-callables",
        createdAt: serverTimestamp(),
      });
      return {ok: true};
    },
    async sendRiderUpdate() {
      throw callableError(
          "failed-precondition",
          "Legacy direct-token Rider notifications are disabled. Use an authorised server-owned notification path.",
      );
    },
  };
}

function productionDependencies() {
  if (!getApps().length) initializeApp();
  return {
    verifyIdToken: (token) => getAuth().verifyIdToken(token, true),
    verifyAppCheck: (token) => getAppCheck().verifyToken(token),
    handlers: createHandlers(),
  };
}

function writeJson(response, status, body) {
  response.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "cache-control": "no-store",
    "access-control-allow-origin": "*",
    "access-control-allow-headers": "Authorization, Content-Type, X-Firebase-AppCheck",
    "access-control-allow-methods": "POST, OPTIONS",
  });
  response.end(JSON.stringify(body));
}

function bearer(request) {
  const match = /^Bearer ([^\s]+)$/.exec(String(request.headers.authorization || ""));
  return match && match[1];
}

function routeName(url) {
  const pathname = new URL(url || "/", "http://localhost").pathname;
  const match = /^(?:\/v1\/callable)?\/(ensureSenderAccount|updateSenderPushToken|updateRiderPushToken|sendRiderUpdate)$/.exec(pathname);
  return match && ROUTES.has(match[1]) ? match[1] : null;
}

function createServer(options = {}) {
  const dependenciesFactory = options.dependenciesFactory || productionDependencies;
  let dependencies;
  return http.createServer((request, response) => {
    if (request.method === "GET" && ["/health", "/healthz"].includes(request.url)) {
      return writeJson(response, 200, {status: "ok", runtime: "node22", source: process.env.CIRCUM_SOURCE_SHA || "unknown"});
    }
    if (request.method === "OPTIONS") return writeJson(response, 204, {});
    const name = routeName(request.url);
    if (!name) return writeJson(response, 404, {error: {status: "NOT_FOUND", message: "Not found."}});
    if (request.method !== "POST") return writeJson(response, 405, {error: {status: "INVALID_ARGUMENT", message: "POST required."}});
    if (!String(request.headers["content-type"] || "").toLowerCase().startsWith("application/json")) {
      return writeJson(response, 415, {error: {status: "INVALID_ARGUMENT", message: "JSON required."}});
    }
    let size = 0;
    const chunks = [];
    request.on("data", (chunk) => {
      size += chunk.length;
      if (size <= MAX_BODY_BYTES) chunks.push(chunk);
    });
    request.on("end", async () => {
      if (size > MAX_BODY_BYTES) return writeJson(response, 413, {error: {status: "INVALID_ARGUMENT", message: "Request too large."}});
      try {
        const idToken = bearer(request);
        if (!idToken) throw callableError("unauthenticated", "Sign in to continue.");
        if (!dependencies) dependencies = dependenciesFactory();
        const decoded = await dependencies.verifyIdToken(idToken);
        if (!decoded || !(decoded.uid || decoded.sub)) throw callableError("unauthenticated", "Invalid authentication token.");
        if (name === "updateRiderPushToken") {
          const appCheckToken = clean(request.headers["x-firebase-appcheck"]);
          if (!appCheckToken) throw callableError("failed-precondition", "Circum Rider security verification is required.");
          await dependencies.verifyAppCheck(appCheckToken);
        }
        const payload = JSON.parse(Buffer.concat(chunks).toString("utf8") || "{}");
        if (!Object.prototype.hasOwnProperty.call(payload, "data")) throw callableError("invalid-argument", "Callable request must contain data.");
        const context = {auth: {uid: decoded.uid || decoded.sub, token: decoded}};
        const result = await dependencies.handlers[name](payload.data, context);
        return writeJson(response, 200, {result});
      } catch (error) {
        const rawCode = String(error.code || "internal").replace(/^functions\//, "");
        const code = rawCode.startsWith("app-check/") || rawCode.startsWith("auth/") ? "unauthenticated" : rawCode;
        const status = code === "unauthenticated" ? 401 : code === "permission-denied" ? 403 : ["invalid-argument", "failed-precondition"].includes(code) ? 400 : 500;
        if (status === 500) console.error("token_callable_failed", {callable: name, reason: error.message || "internal_error"});
        return writeJson(response, status, {error: {status: STATUS[code] || "INTERNAL", message: status === 500 ? "Token request failed." : error.message}});
      }
    });
  });
}

if (require.main === module) createServer().listen(Number(process.env.PORT || 8080), "0.0.0.0");

module.exports = {createServer, createHandlers, productionDependencies, routeName, MAX_BODY_BYTES};
