/* eslint-disable max-len, require-jsdoc */
"use strict";

const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {requireAdmin} = require("./admin-auth");
const {pipelineHealthReport} = require("./delivery-cleanup");
const {approvalProjection} = require("./rider-canonical-account");

const criticalServices = new Set([
  "Dispatch Pipeline",
  "Google Maps",
  "Stripe",
  "Roth",
  "Firebase Functions",
  "Firestore",
  "Authentication",
]);

function text(value, max = 500) {
  return `${value || ""}`.trim().slice(0, max);
}

function statusForScore(score, warning = 85, fail = 60) {
  if (score < fail) return "FAIL";
  if (score < warning) return "WARNING";
  return "PASS";
}

function healthItem(service, status, rootCause, remediation, details = {}) {
  return {
    service,
    status,
    rootCause,
    affectedService: service,
    suggestedRemediation: remediation,
    details,
  };
}

function googlePlacesConfigured() {
  const config = functions.config() || {};
  return Boolean(`${process.env.GOOGLE_PLACES_API_KEY ||
    process.env.CIRCUM_GOOGLE_PLACES_API_KEY ||
    process.env.CIRCUM_WEB_GOOGLE_MAPS_API_KEY ||
    process.env.GOOGLE_MAPS_API_KEY ||
    config.google && config.google.places_api_key ||
    ""}`.trim());
}

function weightedScore(items) {
  if (!items.length) return 100;
  const total = items.reduce((sum, item) => {
    if (item.status === "FAIL") return sum;
    if (item.status === "WARNING") return sum + 60;
    return sum + 100;
  }, 0);
  return Math.round(total / items.length);
}

function deploymentCertification(items) {
  const criticalFailure = items.find((item) =>
    item.status === "FAIL" && criticalServices.has(item.service));
  return criticalFailure ? "NOT_CERTIFIED" : "CERTIFIED";
}

async function countCollection(db, collection, limit = 50) {
  const snapshot = await db.collection(collection).limit(limit).get().catch((error) => ({error}));
  if (snapshot.error) {
    return {ok: false, count: 0, error: snapshot.error.message};
  }
  return {ok: true, count: snapshot.size};
}

async function buildHealthScan(db, options = {}) {
  const now = new Date();
  const pipeline = await pipelineHealthReport(db, {
    now,
    limit: Math.min(Math.max(Number(options.limit) || 300, 1), 500),
  });
  const report = pipeline.report;
  const dispatchStatus = statusForScore(report.dispatchHealthScore);
  const [
    riders,
    users,
    irisRecords,
    notifications,
    wallets,
    rothMovements,
    payments,
    founderAccounts,
    internalTests,
  ] = await Promise.all([
    countCollection(db, "riders"),
    countCollection(db, "users"),
    countCollection(db, "irisPrivate"),
    countCollection(db, "notifications"),
    countCollection(db, "wallets"),
    countCollection(db, "rothLedger"),
    countCollection(db, "payments"),
    countCollection(db, "founderAuthorityAudit", 1),
    countCollection(db, "founderTestAccounts"),
  ]);
  const mapsConfigured = googlePlacesConfigured();
  const stripeConfigured = Boolean(process.env.STRIPE_SECRET_KEY ||
    process.env.STRIPE_WEBHOOK_SECRET ||
    functions.config().stripe);
  const items = [
    healthItem(
        "Dispatch Pipeline",
        dispatchStatus,
        dispatchStatus === "PASS" ? "No stale dispatch artefacts above threshold." : "Stale dispatch artefacts are present.",
        dispatchStatus === "PASS" ? "No action required." : "Run Pipeline Health Reset after confirming no active deliveries are affected.",
        report,
    ),
    healthItem(
        "Rider Matching",
        riders.ok ? "PASS" : "FAIL",
        riders.ok ? "Rider collection is readable." : riders.error,
        riders.ok ? "No action required." : "Verify Firestore availability and Admin service account permissions.",
        riders,
    ),
    healthItem(
        "IRIS",
        irisRecords.ok ? "PASS" : "WARNING",
        irisRecords.ok ? "IRIS operational records are readable." : irisRecords.error,
        irisRecords.ok ? "No action required." : "Verify IRIS temporary collection access and cleanup state.",
        irisRecords,
    ),
    healthItem(
        "Google Maps",
        mapsConfigured ? "PASS" : "FAIL",
        mapsConfigured ? "Maps configuration variable is present in backend runtime." : "No Maps or Places key is visible to the backend runtime.",
        mapsConfigured ? "No action required." : "Attach the configured Maps/Places secret to health callables before certification.",
    ),
    healthItem("Places API", mapsConfigured ? "PASS" : "FAIL", mapsConfigured ? "Places key path is configured." : "Places key path is missing.", mapsConfigured ? "No action required." : "Verify the configured Places secret name and deployment attachment."),
    healthItem("Geocoding", mapsConfigured ? "PASS" : "FAIL", mapsConfigured ? "Geocoding uses the same configured Google API key path." : "Geocoding key path is missing.", mapsConfigured ? "No action required." : "Enable Geocoding API for the configured Google key."),
    healthItem(
        "Notifications",
        notifications.ok ? "PASS" : "WARNING",
        notifications.ok ? "Notification records are readable." : notifications.error,
        notifications.ok ? "No action required." : "Verify notification queue collection access.",
        notifications,
    ),
    healthItem(
        "Wallet",
        wallets.ok ? "PASS" : "FAIL",
        wallets.ok ? "Wallet collection is readable; no financial mutation performed." : wallets.error,
        wallets.ok ? "No action required." : "Verify Firestore financial collection access.",
        wallets,
    ),
    healthItem(
        "Roth",
        rothMovements.ok ? "PASS" : "WARNING",
        rothMovements.ok ? "Roth ledger collection is readable; no ledger mutation performed." : rothMovements.error,
        rothMovements.ok ? "No action required." : "Verify Roth ledger collection naming and read permissions.",
        rothMovements,
    ),
    healthItem(
        "Stripe",
        stripeConfigured && payments.ok ? "PASS" : "FAIL",
        stripeConfigured && payments.ok ? "Stripe runtime configuration and payment records are readable." : "Stripe runtime configuration or payment records are unavailable.",
        stripeConfigured && payments.ok ? "No action required." : "Attach Stripe runtime secrets and verify payment collection access before deployment certification.",
        payments,
    ),
    healthItem("Firebase Functions", "PASS", "Operations Health Centre callable executed successfully.", "No action required."),
    healthItem("Firestore", users.ok ? "PASS" : "FAIL", users.ok ? "Firestore users collection is readable." : users.error, users.ok ? "No action required." : "Verify Firestore availability and Admin SDK permissions.", users),
    healthItem("Storage", "WARNING", "Storage live upload/download is not exercised by this read-only scan.", "Run storage rules certification or a controlled upload/download smoke test."),
    healthItem("App Check", "WARNING", "Callable reached backend; App Check enforcement state requires Firebase console/API verification.", "Verify App Check token exchange in live web surfaces."),
    healthItem("Authentication", "PASS", "Authenticated Admin callable context is present.", "No action required."),
    healthItem("Founder Authority", founderAccounts.ok ? "PASS" : "WARNING", founderAccounts.ok ? "Founder audit collection is readable." : founderAccounts.error, founderAccounts.ok ? "No action required." : "Verify Founder Authority deployment and audit collection access.", founderAccounts),
    healthItem("Internal Test Accounts", internalTests.ok ? "PASS" : "WARNING", internalTests.ok ? "Internal test account registry is readable." : internalTests.error, internalTests.ok ? "No action required." : "Verify founderTestAccounts access and designation workflow.", internalTests),
  ];
  const scores = {
    dispatchHealthScore: report.dispatchHealthScore,
    irisHealthScore: weightedScore(items.filter((item) => item.service === "IRIS")),
    mapsHealthScore: weightedScore(items.filter((item) => ["Google Maps", "Places API", "Geocoding"].includes(item.service))),
    paymentsHealthScore: weightedScore(items.filter((item) => ["Stripe", "Wallet", "Roth"].includes(item.service))),
    firebaseHealthScore: weightedScore(items.filter((item) => ["Firebase Functions", "Firestore", "Storage", "App Check", "Authentication"].includes(item.service))),
    notificationHealthScore: weightedScore(items.filter((item) => item.service === "Notifications")),
  };
  scores.overallProductionHealthScore = weightedScore(items);
  return {
    result: items.some((item) => item.status === "FAIL") ? "BLOCKED" : "READY",
    deploymentCertification: deploymentCertification(items),
    items,
    scores,
    pipeline: report,
    generatedAt: now.toISOString(),
  };
}

async function writeOperationsAudit(db, adminUid, action, payload) {
  const ref = db.collection("adminAuditLogs").doc();
  await ref.set({
    adminUserId: adminUid,
    action,
    actionType: action,
    recordType: "operationsHealthCentre",
    recordId: payload.correlationId || ref.id,
    correlationId: payload.correlationId || ref.id,
    durationMs: payload.durationMs || 0,
    results: payload.results || {},
    before: payload.before || {},
    after: payload.after || {},
    reason: payload.reason || action,
    createdAt: FieldValue.serverTimestamp(),
    immutable: true,
  });
  return ref.id;
}

function operationsHealthScan() {
  return functions.https.onCall(async (data, context) => {
    const adminUid = requireAdmin(context, "Operations Health Centre access is required.");
    const db = getFirestore();
    const started = Date.now();
    const correlationId = text(data && data.correlationId, 128) ||
      `operations-health-scan-${Date.now()}`;
    const scan = await buildHealthScan(db, data || {});
    const auditId = await writeOperationsAudit(db, adminUid, "operations_health_scan", {
      correlationId,
      durationMs: Date.now() - started,
      results: scan,
      reason: "Operations Health Scan",
    });
    return {...scan, correlationId, auditId};
  });
}

function canonicalRiderMismatch(rider = {}, profile = {}) {
  return ["approvalStatus", "verificationStatus", "onboardingStatus", "vehicleType", "vehicleRegistration", "dispatchEligible"].some((field) =>
    `${rider[field] || ""}` !== `${profile[field] || ""}`);
}

async function repairRiders(db, adminUid, limit) {
  const snapshot = await db.collection("riders").limit(limit).get();
  const repaired = [];
  const skipped = [];
  for (const doc of snapshot.docs) {
    const uid = doc.id;
    const [profileSnap, applicationsSnap, documentsSnap] = await Promise.all([
      db.collection("riderProfiles").doc(uid).get(),
      db.collection("riderApplications").where("uid", "==", uid).limit(20).get().catch(() => null),
      db.collection("riderDocuments").where("riderId", "==", uid).limit(100).get().catch(() => null),
    ]);
    const rider = doc.data() || {};
    const profile = profileSnap.exists ? profileSnap.data() || {} : {};
    const applications = applicationsSnap ? applicationsSnap.docs.map((item) => ({id: item.id, ...item.data()})) : [];
    const documents = documentsSnap ? documentsSnap.docs.map((item) => ({id: item.id, ...item.data()})) : [];
    const projection = approvalProjection({
      rider,
      profile,
      applications,
      documents,
      actor: {uid: adminUid},
      reason: "operations_health_repair",
      approve: false,
    });
    if (!projection.ok) {
      skipped.push({uid, reason: projection.reason});
      continue;
    }
    const needsRepair = canonicalRiderMismatch(rider, projection.riderPatch) ||
      canonicalRiderMismatch(profile, projection.profilePatch);
    if (!needsRepair) continue;
    await db.runTransaction(async (transaction) => {
      transaction.set(doc.ref, projection.riderPatch, {merge: true});
      transaction.set(db.collection("riderProfiles").doc(uid), projection.profilePatch, {merge: true});
      applicationsSnap && applicationsSnap.docs.forEach((application) => {
        transaction.set(application.ref, projection.applicationPatch, {merge: true});
      });
    });
    repaired.push({uid, before: projection.before, after: projection.after});
  }
  return {repaired, skipped};
}

function operationsHealthRepair() {
  return functions.https.onCall(async (data, context) => {
    const adminUid = requireAdmin(context, "Operations Health Repair access is required.");
    const reason = text(data && data.reason, 1000);
    if (reason.length < 12) {
      throw new functions.https.HttpsError("invalid-argument", "A detailed repair reason is required.");
    }
    const db = getFirestore();
    const started = Date.now();
    const limit = Math.min(Math.max(Number(data && data.limit) || 50, 1), 100);
    const correlationId = text(data && data.correlationId, 128) ||
      `operations-health-repair-${Date.now()}`;
    const before = await buildHealthScan(db, {limit});
    const riderRepair = await repairRiders(db, adminUid, limit);
    const after = await buildHealthScan(db, {limit});
    const results = {
      riderCanonicalSynchronisations: riderRepair.repaired.length,
      skippedRiders: riderRepair.skipped,
      senderCanonicalSynchronisations: 0,
      internalTestSynchronisations: 0,
      dispatchEligibilityRecalculations: riderRepair.repaired.length,
      quoteCacheInconsistencies: 0,
      irisSessionInconsistencies: before.pipeline.orphanedIrisSessions,
      temporaryUploadInconsistencies: 0,
      deliveryCacheInconsistencies: before.pipeline.staleQueueEntries,
      financialRecordsMutated: 0,
      usersApproved: 0,
    };
    const auditId = await writeOperationsAudit(db, adminUid, "operations_health_repair", {
      correlationId,
      durationMs: Date.now() - started,
      before: before.scores,
      after: after.scores,
      results,
      reason,
    });
    return {
      ok: true,
      correlationId,
      auditId,
      before,
      after,
      results,
    };
  });
}

function stage(status, name, rootCause, remediation, details = {}) {
  return {stage: name, status, rootCause, affectedService: name, suggestedRemediation: remediation, details};
}

function deliveryStageReport(delivery = {}) {
  const stages = [
    stage(delivery.paymentStatus ? "PASS" : "FAIL", "Booking", delivery.paymentStatus ? "Booking record contains payment state." : "Delivery has no payment status.", "Verify Sender payment finalisation and delivery creation."),
    stage(["available", "broadcast", "broadcasted", "offered", "accepted", "reserved", "assigned", "expired"].includes(`${delivery.matchingStatus || delivery.dispatchStatus || ""}`.toLowerCase()) ? "PASS" : "FAIL", "Dispatch", "Dispatch status is evaluated from canonical delivery fields.", "Check broadcast trigger and dispatchStatus/matchingStatus."),
    stage(delivery.offerCount || delivery.lastBroadcastAt || delivery.broadcastAt ? "PASS" : "WARNING", "Offer Broadcast", delivery.offerCount || delivery.lastBroadcastAt || delivery.broadcastAt ? "Broadcast metadata exists." : "No broadcast metadata found on delivery.", "Inspect riderOffers/deliveryOffers for this delivery ID."),
    stage(delivery.acceptedByRiderId || delivery.riderId || delivery.assignedRiderId ? "PASS" : "WARNING", "Offer Acceptance", delivery.acceptedByRiderId || delivery.riderId || delivery.assignedRiderId ? "Rider assignment field exists." : "No rider assignment field exists yet.", "Confirm rider acceptance transaction committed."),
    stage(delivery.riderId || delivery.assignedRiderId ? "PASS" : "WARNING", "Assignment", delivery.riderId || delivery.assignedRiderId ? "Assigned rider is present." : "Delivery is not assigned.", "Check atomic acceptance transaction."),
    stage(delivery.navigationStartedAt || delivery.riderLocation ? "PASS" : "WARNING", "Navigation", delivery.navigationStartedAt || delivery.riderLocation ? "Navigation or rider location signal exists." : "No navigation signal found.", "Verify Rider navigation start."),
    stage(delivery.pickupStartedAt || delivery.arrivedAtPickupAt || delivery.pickupPin ? "PASS" : "WARNING", "Pickup", "Pickup readiness inspected from delivery fields.", "Verify Rider pickup transition and PIN generation."),
    stage(delivery.pickupPin || delivery.collectionPin || delivery.pickupPinVerified ? "PASS" : "WARNING", "Pickup PIN", "Pickup PIN status inspected.", "Verify private PIN document if not stored on public delivery."),
    stage(delivery.inTransitAt || delivery.status === "in_transit" ? "PASS" : "WARNING", "Transit", "Transit status inspected.", "Verify pickup completion."),
    stage(delivery.recipientPin || delivery.deliveryPin || delivery.deliveryPinVerified ? "PASS" : "WARNING", "Recipient PIN", "Recipient PIN status inspected.", "Verify recipient handoff PIN."),
    stage(["delivered", "completed", "archived"].includes(`${delivery.status || ""}`.toLowerCase()) ? "PASS" : "WARNING", "Delivery", "Terminal delivery status inspected.", "Continue lifecycle until delivered/completed."),
    stage(delivery.walletSettlementId || delivery.walletUpdatedAt ? "PASS" : "WARNING", "Wallet", "Wallet settlement marker inspected without mutating finance.", "Verify settlement function after completion."),
    stage(delivery.rothSettlementId || delivery.rothUpdatedAt ? "PASS" : "WARNING", "Roth", "Roth reconciliation marker inspected without mutating finance.", "Verify Roth ledger after completion."),
    stage(delivery.stripePaymentIntentId || delivery.paymentIntentId ? "PASS" : "WARNING", "Stripe", "Stripe payment intent marker inspected.", "Verify payment session and webhook."),
    stage(delivery.archivedAt || delivery.archiveStatus === "archived" ? "PASS" : "WARNING", "Archive", "Archive marker inspected.", "Verify archive job after completion."),
  ];
  const stopped = stages.find((item) => item.status !== "PASS");
  return {
    result: stopped && stopped.status === "FAIL" ? "BLOCKED" : "READY",
    stoppedAt: stopped ? stopped.stage : "Complete",
    stages,
  };
}

function liveDeliveryDiagnostics() {
  return functions.https.onCall(async (data, context) => {
    const adminUid = requireAdmin(context, "Live Delivery Diagnostics access is required.");
    const deliveryId = text(data && data.deliveryId, 160);
    if (!deliveryId) {
      throw new functions.https.HttpsError("invalid-argument", "A delivery ID is required.");
    }
    const db = getFirestore();
    const started = Date.now();
    const correlationId = text(data && data.correlationId, 128) ||
      `delivery-diagnostics-${deliveryId}-${Date.now()}`;
    const refs = [
      db.collection("deliveryRequests").doc(deliveryId),
      db.collection("deliveries").doc(deliveryId),
      db.collection("senderBookings").doc(deliveryId),
    ];
    const snaps = await Promise.all(refs.map((ref) => ref.get()));
    const found = snaps.find((snap) => snap.exists);
    if (!found) {
      const result = {
        result: "BLOCKED",
        stoppedAt: "Booking",
        stages: [stage("FAIL", "Booking", "Delivery document was not found in canonical delivery collections.", "Verify the delivery ID and booking creation path.")],
      };
      const auditId = await writeOperationsAudit(db, adminUid, "live_delivery_diagnostics", {
        correlationId,
        durationMs: Date.now() - started,
        results: result,
        reason: "Live Delivery Diagnostics",
      });
      return {deliveryId, correlationId, auditId, ...result};
    }
    const delivery = found.data() || {};
    const result = deliveryStageReport(delivery);
    const auditId = await writeOperationsAudit(db, adminUid, "live_delivery_diagnostics", {
      correlationId,
      durationMs: Date.now() - started,
      results: result,
      before: {path: found.ref.path},
      reason: "Live Delivery Diagnostics",
    });
    return {deliveryId, path: found.ref.path, correlationId, auditId, ...result};
  });
}

module.exports = {
  buildHealthScan,
  criticalServices,
  deploymentCertification,
  deliveryStageReport,
  operationsHealthScan,
  operationsHealthRepair,
  liveDeliveryDiagnostics,
  statusForScore,
  weightedScore,
};
