/* eslint-disable max-len, require-jsdoc */
"use strict";

const functions = require("firebase-functions/v1");
const {getAuth} = require("firebase-admin/auth");
const {getFirestore} = require("firebase-admin/firestore");

const FINANCIAL_ADMIN_ROLES = new Set([
  "admin",
  "super_admin",
  "operations_admin",
  "support_agent",
  "finance_admin",
]);
const INACTIVE_ADMIN_STATUSES = new Set([
  "disabled",
  "inactive",
  "revoked",
  "suspended",
]);

function clean(value) {
  return `${value || ""}`.trim();
}

function lower(value) {
  return clean(value).toLowerCase();
}

function rolesFrom(record = {}) {
  return [
    record.role,
    record.adminRole,
    ...(Array.isArray(record.roles) ? record.roles : []),
    record.admin === true ? "admin" : "",
    record.superAdmin === true || record.super_admin === true ? "super_admin" : "",
  ].map(lower).filter(Boolean);
}

function hasFinancialRole(record = {}) {
  return rolesFrom(record).some((role) => FINANCIAL_ADMIN_ROLES.has(role));
}

function bearerToken(req) {
  const header = clean(req && req.headers && (req.headers.authorization || req.headers.Authorization));
  const match = /^Bearer\s+(.+)$/i.exec(header);
  return match ? clean(match[1]) : "";
}

async function activeFinancialAdmin(db, decoded) {
  if (!hasFinancialRole(decoded)) return false;
  const uid = clean(decoded.uid || decoded.sub);
  const email = lower(decoded.email);
  const snapshots = await Promise.all([
    uid ? db.collection("adminUsers").doc(uid).get() : null,
    email ? db.collection("adminUsers").doc(email).get() : null,
  ]);
  return snapshots.filter(Boolean).some((snapshot) => {
    if (!snapshot.exists) return false;
    const record = snapshot.data() || {};
    if (INACTIVE_ADMIN_STATUSES.has(lower(record.status))) return false;
    return hasFinancialRole(record);
  });
}

async function authenticateRequest(req, {auth, db}) {
  const token = bearerToken(req);
  if (!token) return null;
  try {
    const decoded = await auth.verifyIdToken(token, true);
    const uid = clean(decoded.uid || decoded.sub);
    if (!uid) return null;
    return {
      uid,
      email: lower(decoded.email),
      isFinancialAdmin: await activeFinancialAdmin(db, decoded),
    };
  } catch (_) {
    return null;
  }
}

function requestData(req) {
  const body = req && req.body && typeof req.body === "object" ? req.body : {};
  return body.data && typeof body.data === "object" ? body.data : body;
}

function prepareResponse(req, res) {
  res.set("Cache-Control", "no-store");
  res.set("X-Content-Type-Options", "nosniff");
  if (req.method === "OPTIONS") {
    res.status(204).send("");
    return true;
  }
  if (req.method !== "POST") {
    res.status(405).json({error: "method_not_allowed"});
    return true;
  }
  return false;
}

function paymentMethodView(method) {
  const card = method.card || {};
  return {
    id: method.id,
    type: method.type,
    brand: card.brand || "",
    last4: card.last4 || "",
    expMonth: card.exp_month || null,
    expYear: card.exp_year || null,
  };
}

async function ownedStripeCustomerIds(db, uid) {
  const [user, sender] = await Promise.all([
    db.collection("users").doc(uid).get(),
    db.collection("senders").doc(uid).get(),
  ]);
  return new Set([user, sender]
      .filter((snapshot) => snapshot.exists)
      .flatMap((snapshot) => {
        const data = snapshot.data() || {};
        return [data.stripeCustomerId, data.customerId].map(clean).filter(Boolean);
      }));
}

function createRetrieveCardDetailsHandler({stripe, auth = getAuth(), db = getFirestore()}) {
  return async (req, res) => {
    if (prepareResponse(req, res)) return;
    const actor = await authenticateRequest(req, {auth, db});
    if (!actor) return res.status(401).json({error: "authentication_required"});
    const requestedCustomerId = clean(requestData(req).customerId);
    const ownedCustomerIds = actor.isFinancialAdmin ? new Set() : await ownedStripeCustomerIds(db, actor.uid);
    const customerId = requestedCustomerId || [...ownedCustomerIds][0] || "";
    if (!customerId) return res.status(404).json({error: "payment_profile_not_found"});
    if (!actor.isFinancialAdmin && !ownedCustomerIds.has(customerId)) {
      return res.status(403).json({error: "payment_profile_access_denied"});
    }
    try {
      const methods = await stripe.paymentMethods.list({customer: customerId, type: "card"});
      return res.status(200).json({
        customerId,
        paymentMethods: (methods.data || []).map(paymentMethodView),
      });
    } catch (error) {
      console.error("RetrieveCardDetails failed", {name: error && error.name});
      return res.status(500).json({error: "payment_methods_unavailable"});
    }
  };
}

function earningsForSnapshot(snapshot) {
  let total = 0;
  snapshot.forEach((doc) => {
    total += Number((doc.data() || {}).price || 0);
  });
  return total;
}

function createCalculateEarningsHandler({auth = getAuth(), db = getFirestore()}) {
  return async (req, res) => {
    if (prepareResponse(req, res)) return;
    const actor = await authenticateRequest(req, {auth, db});
    if (!actor) return res.status(401).json({error: "authentication_required"});
    const riderId = clean(requestData(req).riderId) || actor.uid;
    if (!actor.isFinancialAdmin && riderId !== actor.uid) {
      return res.status(403).json({error: "rider_earnings_access_denied"});
    }
    const rider = await db.collection("riders").doc(riderId).get();
    if (!rider.exists) return res.status(404).json({error: "rider_not_found"});

    try {
      const [payment, history] = await Promise.all([
        db.collection("payments").doc(riderId).get(),
        db.collection("history").where("riderId", "==", riderId).get(),
      ]);
      const now = new Date();
      const weekStart = new Date(now);
      weekStart.setDate(weekStart.getDate() - 7);
      const weekly = await db.collection("history")
          .where("riderId", "==", riderId)
          .where("createdAt", ">=", weekStart)
          .where("createdAt", "<=", now)
          .get();
      const weeklyEarnings = {Sun: 0, Mon: 0, Tue: 0, Wed: 0, Thu: 0, Fri: 0, Sat: 0};
      weekly.forEach((doc) => {
        const data = doc.data() || {};
        if (!data.createdAt || typeof data.createdAt.toDate !== "function") return;
        const day = data.createdAt.toDate().toLocaleDateString("en-US", {weekday: "short"});
        weeklyEarnings[day] += Number(data.price || 0);
      });
      return res.status(200).json({
        accountBalance: Number(payment.exists ? (payment.data() || {}).accountBalance || 0 : 0),
        totalAmountEarned: earningsForSnapshot(history),
        totalTrips: history.size,
        weeklyEarnings,
      });
    } catch (error) {
      console.error("calculateEarnings failed", {name: error && error.name});
      return res.status(500).json({error: "earnings_unavailable"});
    }
  };
}

exports.retrieveCardDetails = (stripe) => functions.https.onRequest(
    createRetrieveCardDetailsHandler({stripe}),
);
exports.calculateEarnings = () => functions.https.onRequest(
    createCalculateEarningsHandler({}),
);
exports._test = {
  activeFinancialAdmin,
  authenticateRequest,
  createCalculateEarningsHandler,
  createRetrieveCardDetailsHandler,
  hasFinancialRole,
  ownedStripeCustomerIds,
};
