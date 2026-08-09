/* eslint-disable max-len, require-jsdoc */
"use strict";

const functions = require("firebase-functions/v1");
const {getFirestore, FieldPath, AggregateField} = require("firebase-admin/firestore");
const {businessAuthority} = require("./business-authority");

const PAGE_SIZE = 20;
const MAX_PAGE_SIZE = 50;
const COMPLETED = ["delivered", "completed"];
const FAILED = ["failed", "cancelled", "cancelled_admin"];

function text(value) {
  return `${value || ""}`.trim();
}

function millis(value) {
  return value && typeof value.toMillis === "function" ? value.toMillis() : null;
}

function money(value) {
  const parsed = Number(value || 0);
  return Number.isFinite(parsed) ? Math.round(parsed * 100) / 100 : 0;
}

function address(value) {
  if (value && typeof value === "object") {
    for (const key of ["formattedAddress", "addressLine1", "address", "description"]) {
      if (text(value[key])) return text(value[key]);
    }
    return "";
  }
  return text(value);
}

function sanitizeDelivery(doc, projection = {}) {
  const data = doc.data() || {};
  return {
    id: doc.id,
    pickup: address(data.pickupAddressCanonical || data.pickupAddress || data.pickup),
    dropoff: address(data.dropoffAddressCanonical || data.dropoffAddress || data.dropOffAddress || data.dropoff),
    status: text(data.deliveryStatus || data.status || "draft").toLowerCase(),
    bookedBy: text(data.bookedByName || data.senderName),
    vehicle: text(data.quotedVehicleClass || data.vehicleType || data.vehicle),
    category: text(data.category || data.itemCategory || data.serviceLevel || "Delivery"),
    serviceLevel: text(data.serviceLevel || data.selectedServiceLevel || data.selectedSpeed).toLowerCase(),
    amount: money(data.paidAmount || data.price || data.totalAmount || data.amountPaid),
    createdAtMillis: millis(data.createdAt),
    scheduledAtMillis: millis(data.scheduledAt || data.preferredDeliveryDate),
    durationMinutes: Number.isFinite(Number(data.durationMinutes)) ? Number(data.durationMinutes) : null,
    slaStatus: projection.openIncidentId ? "RED" : projection.active ? "AMBER" : "GREEN",
    incidentType: projection.openIncidentId ? text(projection.incidentType) : null,
  };
}

function sanitizeInvoice(doc) {
  const data = doc.data() || {};
  return {
    id: doc.id,
    invoiceNumber: text(data.invoiceNumber || doc.id),
    status: text(data.status || "draft").toLowerCase(),
    total: money(data.total || data.subtotal),
    balanceDue: money(data.balanceDue || data.total),
    rothApplied: money(data.rothApplied || data.rothAmount),
    deliveryCount: Number(data.deliveryCount || (Array.isArray(data.deliveryIds) ? data.deliveryIds.length : 0)),
    dueAtMillis: millis(data.dueAt || data.dueDate),
    createdAtMillis: millis(data.createdAt),
    paymentReference: text(data.paymentReference),
  };
}

async function authorizedAccount(db, businessId, context) {
  const uid = context.auth && context.auth.uid;
  if (!uid) throw new functions.https.HttpsError("unauthenticated", "Sign in to use Circum Business.");
  const ref = db.collection("businessAccounts").doc(businessId);
  const snapshot = await ref.get();
  if (!snapshot.exists) throw new functions.https.HttpsError("not-found", "Business workspace not found.");
  const account = snapshot.data() || {};
  const authority = businessAuthority(account, {uid, email: context.auth.token.email});
  if (!authority.member) throw new functions.https.HttpsError("permission-denied", "Business workspace access is required.");
  return {account, authority};
}

function pageQuery(db, businessId, data = {}) {
  const requested = Math.floor(Number(data.pageSize || PAGE_SIZE));
  const pageSize = Math.max(1, Math.min(MAX_PAGE_SIZE, requested));
  let query = db.collection("deliveryRequests")
      .where("businessId", "==", businessId)
      .orderBy("createdAt", "desc")
      .orderBy(FieldPath.documentId(), "desc");
  const cursor = data.cursor || {};
  if (Number.isFinite(Number(cursor.createdAtMillis)) && text(cursor.id)) {
    query = query.startAfter(new Date(Number(cursor.createdAtMillis)), text(cursor.id));
  }
  return {query: query.limit(pageSize + 1), pageSize};
}

async function reportSummary(db, businessId, now = new Date()) {
  const base = db.collection("deliveryRequests").where("businessId", "==", businessId);
  const monthStart = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1));
  const nextMonth = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() + 1, 1));
  const aggregate = async (query, fields = {count: AggregateField.count()}) =>
    (await query.aggregate(fields).get()).data();
  const [all, completed, failed, standard, express, economy, month] = await Promise.all([
    aggregate(base),
    aggregate(base.where("status", "in", COMPLETED)),
    aggregate(base.where("status", "in", FAILED)),
    aggregate(base.where("serviceLevel", "==", "standard")),
    aggregate(base.where("serviceLevel", "==", "express")),
    aggregate(base.where("serviceLevel", "==", "economy")),
    aggregate(base.where("createdAt", ">=", monthStart).where("createdAt", "<", nextMonth), {
      count: AggregateField.count(),
      spend: AggregateField.sum("paidAmount"),
      averageMinutes: AggregateField.average("durationMinutes"),
    }),
  ]);
  return {
    deliveryCount: all.count || 0,
    completedCount: completed.count || 0,
    failedOrCancelledCount: failed.count || 0,
    activeCount: Math.max(0, (all.count || 0) - (completed.count || 0) - (failed.count || 0)),
    monthlyDeliveries: month.count || 0,
    monthlySpend: money(month.spend),
    averageDeliveryMinutes: Number.isFinite(Number(month.averageMinutes)) ? Math.round(month.averageMinutes) : null,
    serviceMix: {standard: standard.count || 0, express: express.count || 0, economy: economy.count || 0},
    reportingVersion: "2026-08-business-operations-v1",
  };
}

exports.getBusinessOperationsWorkspace = functions.runWith({enforceAppCheck: true})
    .region("us-central1").https.onCall(async (data, context) => {
      const businessId = text(data && data.businessId);
      if (!businessId) throw new functions.https.HttpsError("invalid-argument", "Business workspace is required.");
      const db = getFirestore();
      const {authority} = await authorizedAccount(db, businessId, context);
      const response = {role: authority.role, permissions: {
        deliveries: authority.deliveryAuthorized,
        reports: authority.reportingAuthorized,
        finance: authority.financialAuthorized,
      }};
      if (authority.deliveryAuthorized) {
        const {query, pageSize} = pageQuery(db, businessId, data || {});
        const snapshot = await query.get();
        const visible = snapshot.docs.slice(0, pageSize);
        const projections = visible.length ?
          await db.getAll(...visible.map((doc) => db.collection("deliveryOperationalState").doc(doc.id))) : [];
        response.deliveries = visible.map((doc, index) => sanitizeDelivery(doc, projections[index].data() || {}));
        response.nextCursor = snapshot.size > pageSize && visible.length ? {
          createdAtMillis: response.deliveries[response.deliveries.length - 1].createdAtMillis,
          id: visible[visible.length - 1].id,
        } : null;
      } else {
        response.deliveries = [];
        response.nextCursor = null;
      }
      if (authority.deliveryAuthorized) {
        const [health, gifts] = await Promise.all([
          db.collection("prescriptionPickups").where("businessId", "==", businessId)
              .orderBy("createdAt", "desc").limit(20).get(),
          db.collection("giftRequests").where("businessId", "==", businessId)
              .orderBy("createdAt", "desc").limit(20).get(),
        ]);
        response.healthRequests = health.docs.map((doc) => ({
          id: doc.id,
          title: text(doc.data().patientName || "Health+ request"),
          status: text(doc.data().status || "requested").toLowerCase(),
          createdAtMillis: millis(doc.data().createdAt),
        }));
        response.giftRequests = gifts.docs.map((doc) => ({
          id: doc.id,
          title: text(doc.data().occasion || "Corporate gift"),
          status: text(doc.data().status || "requested").toLowerCase(),
          createdAtMillis: millis(doc.data().createdAt),
        }));
      }
      if (authority.reportingAuthorized) response.summary = await reportSummary(db, businessId);
      if (authority.financialAuthorized) {
        const [invoices, wallet] = await Promise.all([
          db.collection("businessInvoices").where("businessId", "==", businessId)
              .orderBy("createdAt", "desc").orderBy(FieldPath.documentId(), "desc").limit(50).get(),
          db.collection("business_wallets").doc(businessId).get(),
        ]);
        response.invoices = invoices.docs.map(sanitizeInvoice);
        const walletData = wallet.data() || {};
        response.wallet = {balance: money(walletData.balance), lifetimeSpent: money(walletData.lifetimeSpent), status: text(walletData.status || "active")};
      }
      return response;
    });

exports.getBusinessDeliveryTimeline = functions.runWith({enforceAppCheck: true})
    .region("us-central1").https.onCall(async (data, context) => {
      const businessId = text(data && data.businessId);
      const deliveryId = text(data && data.deliveryId);
      if (!businessId || !deliveryId) throw new functions.https.HttpsError("invalid-argument", "Business and delivery are required.");
      const db = getFirestore();
      const {authority} = await authorizedAccount(db, businessId, context);
      if (!authority.deliveryAuthorized && !authority.reportingAuthorized) throw new functions.https.HttpsError("permission-denied", "Delivery history access is required.");
      const delivery = await db.collection("deliveryRequests").doc(deliveryId).get();
      if (!delivery.exists || text(delivery.data().businessId) !== businessId) throw new functions.https.HttpsError("not-found", "Delivery not found.");
      const timeline = await delivery.ref.collection("timeline").orderBy("timestamp", "desc").limit(100).get();
      return {deliveryId, events: timeline.docs.map((doc) => {
        const event = doc.data() || {};
        return {eventId: doc.id, eventType: text(event.eventType), timestampMillis: millis(event.timestamp), actorType: text(event.actorType || "system"), source: text(event.source), previousState: text(event.previousState) || null, newState: text(event.newState) || null};
      })};
    });

exports._private = {sanitizeDelivery, sanitizeInvoice, pageQuery, reportSummary};
