/* eslint-disable max-len, require-jsdoc */
const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {requireAdmin} = require("./admin-auth");

const ACTIONS = new Set([
  "reset_address_rate_limit",
  "expire_sender_draft",
  "delete_sender_draft",
  "restore_sender_draft",
  "recover_sender_booking",
  "recover_sender_payment_state",
  "recover_sender_wallet_state",
  "recover_sender_notifications",
  "recover_sender_account_state",
  "recover_sender_onboarding",
  "force_rider_offline",
  "force_rider_online",
  "reset_rider_presence",
  "reset_rider_dispatch_state",
  "recover_rider_verification",
  "restore_suspended_rider",
  "correct_rider_onboarding",
  "recover_stripe_onboarding",
  "recover_payout_state",
  "recover_stuck_rider_job",
  "repair_tracking_state",
  "recover_delivery_lifecycle",
  "recover_cancelled_delivery",
  "resolve_duplicate_delivery",
  "recover_orphan_delivery",
  "reassign_rider",
  "reopen_delivery",
  "force_complete_delivery",
  "repair_custody_chain",
  "escalate_health_plus",
  "recover_health_booking",
  "recover_health_custody",
  "recover_health_checkout",
  "recover_health_schedule",
  "recover_business_membership",
  "recover_business_invoice",
  "recover_business_team",
  "recover_business_permissions",
  "recover_business_invitation",
  "recover_business_subscription",
  "recover_gift_campaign",
  "recover_gift_matching",
  "recover_gift_procurement",
  "recover_gift_supplier",
  "recover_gift_story",
  "recover_gift_delivery",
  "override_iris_review",
  "reclassify_iris",
  "resolve_iris_weight_dispute",
  "promote_iris_canonical",
  "recover_iris_learning_job",
  "recover_chat_conversation",
  "restore_chat_messages",
  "moderate_chat_abuse",
  "export_chat_conversation",
  "place_chat_legal_hold",
  "replay_notification",
  "rebuild_notification_queue",
  "clear_stuck_notification",
  "retry_checkout",
  "recover_checkout",
  "retry_payment_webhook",
  "reconcile_ledger",
  "manual_financial_adjustment",
  "investigate_stripe_state",
  "recover_payment_session",
  "force_logout",
  "invalidate_refresh_tokens",
  "lock_account",
  "unlock_account",
  "reset_mfa",
  "recover_account_access",
]);

const DELIVERY_ACTIONS = new Set([
  "repair_tracking_state",
  "recover_delivery_lifecycle",
  "recover_cancelled_delivery",
  "resolve_duplicate_delivery",
  "recover_orphan_delivery",
  "reassign_rider",
  "reopen_delivery",
  "force_complete_delivery",
  "repair_custody_chain",
  "recover_sender_booking",
  "recover_stuck_rider_job",
  "recover_gift_delivery",
]);

const RIDER_ACTIONS = new Set([
  "force_rider_offline",
  "force_rider_online",
  "reset_rider_presence",
  "reset_rider_dispatch_state",
]);

const BUSINESS_ACTIONS = new Set([
  "recover_business_membership",
  "recover_business_team",
  "recover_business_permissions",
  "recover_business_invitation",
  "recover_business_subscription",
]);

const HEALTH_ACTIONS = new Set([
  "escalate_health_plus",
  "recover_health_booking",
  "recover_health_custody",
  "recover_health_checkout",
]);

const GIFT_ORDER_ACTIONS = new Set([
  "recover_gift_campaign",
  "recover_gift_procurement",
  "recover_gift_supplier",
  "recover_gift_story",
]);

const NOTIFICATION_ACTIONS = new Set([
  "replay_notification",
  "rebuild_notification_queue",
  "clear_stuck_notification",
]);

const PAYMENT_ACTIONS = new Set([
  "retry_checkout",
  "recover_checkout",
  "retry_payment_webhook",
  "investigate_stripe_state",
  "recover_payment_session",
  "manual_financial_adjustment",
  "recover_sender_payment_state",
]);

const TIER_ONE_ACTIONS = new Set([
  "replay_notification",
  "restore_sender_draft",
  "reset_rider_presence",
  "retry_payment_webhook",
  "recover_checkout",
]);

const TIER_TWO_ACTIONS = new Set([
  "force_complete_delivery",
  "reopen_delivery",
  "reconcile_ledger",
  "manual_financial_adjustment",
  "override_iris_review",
  "place_chat_legal_hold",
  "lock_account",
  "unlock_account",
  "reassign_rider",
]);

function text(value) {
  return `${value || ""}`.trim();
}

function lower(value) {
  return text(value).toLowerCase();
}

function roleValues(token = {}) {
  const roles = Array.isArray(token.roles) ? token.roles.map(lower) : [];
  return new Set([
    lower(token.role),
    lower(token.adminRole),
    ...roles,
  ].filter(Boolean));
}

function assertSuperAdmin(context) {
  const uid = requireAdmin(context, "Super Admin recovery access is required.");
  const roles = roleValues(context.auth.token || {});
  if (
    context.auth.token.superAdmin === true ||
    context.auth.token.super_admin === true ||
    roles.has("super_admin")
  ) {
    return {
      uid,
      email: text(context.auth.token.email),
      roles: [...roles],
    };
  }
  throw new functions.https.HttpsError(
      "permission-denied",
      "Super Admin recovery access is required.",
  );
}

function requireReason(data) {
  const reason = text(data && data.reason);
  if (!reason) {
    throw new functions.https.HttpsError(
        "invalid-argument",
        "A recovery reason is required.",
    );
  }
  return reason;
}

function approvalTier(action) {
  if (TIER_TWO_ACTIONS.has(action)) return "tier_2";
  if (TIER_ONE_ACTIONS.has(action)) return "tier_1";
  return "tier_1";
}

function hasElevatedRecoveryRole(actor) {
  const roles = new Set((actor.roles || []).map(lower));
  return roles.has("recovery_approver") ||
    roles.has("platform_owner") ||
    roles.has("owner");
}

function approvalFor(action, actor, data = {}) {
  const tier = approvalTier(action);
  const elevated = hasElevatedRecoveryRole(actor);
  const secondaryApprover = {
    id: text(data.secondaryApproverId),
    email: text(data.secondaryApproverEmail),
    role: text(data.secondaryApproverRole),
  };
  if (tier === "tier_2" && !elevated && !secondaryApprover.id) {
    throw new functions.https.HttpsError(
        "failed-precondition",
        "Tier 2 recovery requires a secondary approver or elevated recovery role.",
    );
  }
  return {
    tier,
    primaryApprover: actor.uid,
    secondaryApprover: secondaryApprover.id ? secondaryApprover : null,
    elevatedRoleApproved: tier === "tier_2" && elevated,
  };
}

function targetRef(db, action, data) {
  const id = text(data && (data.targetId || data.id));
  const userId = text(data && data.userId);
  const riderId = text(data && data.riderId);
  const deliveryId = text(data && data.deliveryId);
  const businessId = text(data && data.businessId);
  const healthId = text(data && data.healthPlusId);
  const invoiceId = text(data && data.invoiceId);
  const giftId = text(data && data.giftId);
  const matchId = text(data && data.matchId);
  const irisId = text(data && data.irisId);
  const chatId = text(data && data.chatId);
  const notificationId = text(data && data.notificationId);
  const paymentId = text(data && data.paymentId);
  const walletId = text(data && data.walletId);
  const scheduleId = text(data && data.scheduleId);
  switch (action) {
    case "reset_address_rate_limit":
      return db.collection("rateLimits").doc(id || `address_search_${userId}`);
    case "expire_sender_draft":
    case "delete_sender_draft":
    case "restore_sender_draft":
      return db.collection("senderBookingDrafts").doc(id || userId);
    case "recover_rider_verification":
    case "restore_suspended_rider":
    case "correct_rider_onboarding":
    case "recover_stripe_onboarding":
    case "recover_payout_state":
      return db.collection("riders").doc(id || riderId);
    case "recover_sender_wallet_state":
    case "reconcile_ledger":
      return db.collection("wallets").doc(id || walletId || userId);
    case "recover_business_invoice":
      return db.collection("businessInvoices").doc(id || invoiceId);
    case "recover_health_schedule":
      return db.collection("recurringPickupSchedules").doc(id || scheduleId);
    case "recover_gift_matching":
      return db.collection("giftCampaignMatches").doc(id || matchId);
    case "override_iris_review":
    case "reclassify_iris":
    case "resolve_iris_weight_dispute":
      return db.collection("irisEvidence").doc(id || irisId || deliveryId);
    case "promote_iris_canonical":
      return db.collection("irisCanonicalObjects").doc(id || irisId);
    case "recover_iris_learning_job":
      return db.collection("irisLearningCases").doc(id || irisId);
    case "recover_chat_conversation":
    case "restore_chat_messages":
    case "moderate_chat_abuse":
    case "export_chat_conversation":
    case "place_chat_legal_hold":
      return db.collection("chats").doc(id || chatId);
    case "recover_sender_account_state":
    case "recover_sender_onboarding":
    case "recover_sender_notifications":
    case "force_logout":
    case "invalidate_refresh_tokens":
    case "lock_account":
    case "unlock_account":
    case "reset_mfa":
    case "recover_account_access":
      return db.collection("users").doc(id || userId);
    default:
      break;
  }
  if (RIDER_ACTIONS.has(action)) {
    return db.collection("riderPresence").doc(id || riderId);
  }
  if (DELIVERY_ACTIONS.has(action)) {
    return db.collection("deliveryRequests").doc(id || deliveryId);
  }
  if (HEALTH_ACTIONS.has(action)) {
    return db.collection("prescriptionPickups").doc(id || healthId);
  }
  if (BUSINESS_ACTIONS.has(action)) {
    return db.collection("businessAccounts").doc(id || businessId);
  }
  if (GIFT_ORDER_ACTIONS.has(action)) {
    return db.collection("giftOrders").doc(id || giftId);
  }
  if (NOTIFICATION_ACTIONS.has(action)) {
    return db.collection("notifications").doc(id || notificationId);
  }
  if (PAYMENT_ACTIONS.has(action)) {
    return db.collection("payments").doc(id || paymentId);
  }
  throw new functions.https.HttpsError("invalid-argument", "Unsupported governance action.");
}

function patchFor(action, actor, reason) {
  const timestamp = FieldValue.serverTimestamp();
  const common = {
    adminRecoveryUpdatedAt: timestamp,
    adminRecoveryUpdatedBy: actor.uid,
    adminRecoveryReason: reason,
    updatedAt: timestamp,
  };
  const recoveryRequest = (status) => ({
    ...common,
    adminOperationStatus: "recovery_requested",
    recoveryStatus: status,
    recoveryOutcome: "queued",
  });
  switch (action) {
    case "reset_address_rate_limit":
      return {deleteDocument: true};
    case "expire_sender_draft":
      return {
        ...common,
        status: "expired",
        adminRecoveryStatus: "expired",
        expiresAt: timestamp,
      };
    case "delete_sender_draft":
      return {deleteDocument: true};
    case "restore_sender_draft":
      return {
        ...common,
        status: "draft",
        adminRecoveryStatus: "restored",
        restoreBlocked: false,
        corrupted: false,
      };
    case "force_rider_online":
      return {
        ...common,
        isOnline: true,
        online: true,
        busy: false,
        status: "online",
        availabilityStatus: "online",
        dispatchEligible: true,
        source: "admin_governance",
        recoveryOutcome: "force_online_requested",
      };
    case "force_rider_offline":
      return {
        ...common,
        isOnline: false,
        online: false,
        busy: false,
        status: "offline",
        availabilityStatus: "offline",
        dispatchEligible: false,
        gpsStatus: "reset",
        activeDeliveryId: FieldValue.delete(),
        currentDeliveryId: FieldValue.delete(),
        source: "admin_governance",
      };
    case "reset_rider_presence":
    case "reset_rider_dispatch_state":
      return {
        ...common,
        isOnline: false,
        online: false,
        busy: false,
        status: "offline",
        availabilityStatus: "offline",
        dispatchEligible: false,
        dispatchRecoveryStatus: "reset_requested",
        gpsStatus: "reset",
        activeDeliveryId: FieldValue.delete(),
        currentDeliveryId: FieldValue.delete(),
        source: "admin_governance",
      };
    case "repair_tracking_state":
      return {
        ...common,
        trackingRecoveryStatus: "repair_requested",
        trackingSessionStatus: "reset_requested",
        realtimeTrackingStatus: "restart_requested",
      };
    case "recover_delivery_lifecycle":
      return {
        ...common,
        adminOperationStatus: "recovery_requested",
        lifecycleRecoveryStatus: "requested",
        lifecycleRecoveryReason: reason,
      };
    case "recover_cancelled_delivery":
      return {
        ...common,
        adminOperationStatus: "reopen_review_requested",
        lifecycleRecoveryStatus: "cancelled_recovery_review",
        reopenPolicyReviewRequired: true,
      };
    case "resolve_duplicate_delivery":
      return {
        ...common,
        adminOperationStatus: "duplicate_review_requested",
        duplicateResolutionStatus: "review_requested",
      };
    case "recover_orphan_delivery":
      return {
        ...common,
        adminOperationStatus: "orphan_recovery_requested",
        orphanRecoveryStatus: "review_requested",
      };
    case "reassign_rider":
      return {
        ...common,
        adminOperationStatus: "reassignment_requested",
        riderReassignmentStatus: "requested",
        assignedRiderId: FieldValue.delete(),
        riderId: FieldValue.delete(),
      };
    case "reopen_delivery":
      return {
        ...common,
        adminOperationStatus: "reopen_requested",
        reopenPolicyReviewRequired: true,
        lifecycleRecoveryStatus: "reopen_requested",
      };
    case "force_complete_delivery":
      return {
        ...common,
        adminOperationStatus: "force_completion_review_requested",
        lifecycleRecoveryStatus: "force_completion_requested",
        forceCompletionReviewRequired: true,
      };
    case "repair_custody_chain":
      return {
        ...common,
        custodyRecoveryStatus: "repair_requested",
        custodyReviewStatus: "review_requested",
      };
    case "escalate_health_plus":
      return {
        ...common,
        adminEscalationStatus: "escalated",
        custodyReviewStatus: "review_requested",
        medicationWorkflowEscalated: true,
      };
    case "recover_health_booking":
      return recoveryRequest("health_booking_recovery_requested");
    case "recover_health_custody":
      return {
        ...recoveryRequest("health_custody_recovery_requested"),
        custodyReviewStatus: "review_requested",
      };
    case "recover_health_checkout":
      return recoveryRequest("health_checkout_recovery_requested");
    case "recover_health_schedule":
      return recoveryRequest("health_schedule_recovery_requested");
    case "recover_business_membership":
      return {
        ...common,
        membershipRecoveryStatus: "review_requested",
        onboardingRecoveryStatus: "review_requested",
      };
    case "recover_business_invoice":
      return recoveryRequest("business_invoice_recovery_requested");
    case "recover_business_team":
      return recoveryRequest("business_team_recovery_requested");
    case "recover_business_permissions":
      return recoveryRequest("business_permissions_recovery_requested");
    case "recover_business_invitation":
      return recoveryRequest("business_invitation_recovery_requested");
    case "recover_business_subscription":
      return recoveryRequest("business_subscription_recovery_requested");
    case "recover_rider_verification":
      return recoveryRequest("rider_verification_recovery_requested");
    case "restore_suspended_rider":
      return {
        ...recoveryRequest("rider_restore_review_requested"),
        suspensionRecoveryStatus: "review_requested",
      };
    case "correct_rider_onboarding":
      return recoveryRequest("rider_onboarding_recovery_requested");
    case "recover_stripe_onboarding":
      return recoveryRequest("rider_stripe_onboarding_recovery_requested");
    case "recover_payout_state":
      return recoveryRequest("rider_payout_recovery_requested");
    case "recover_stuck_rider_job":
      return recoveryRequest("rider_job_recovery_requested");
    case "recover_sender_booking":
      return recoveryRequest("sender_booking_recovery_requested");
    case "recover_sender_payment_state":
      return recoveryRequest("sender_payment_recovery_requested");
    case "recover_sender_wallet_state":
      return recoveryRequest("sender_wallet_recovery_requested");
    case "recover_sender_notifications":
      return recoveryRequest("sender_notification_recovery_requested");
    case "recover_sender_account_state":
      return recoveryRequest("sender_account_recovery_requested");
    case "recover_sender_onboarding":
      return recoveryRequest("sender_onboarding_recovery_requested");
    case "recover_gift_campaign":
      return recoveryRequest("gift_campaign_recovery_requested");
    case "recover_gift_matching":
      return recoveryRequest("gift_matching_recovery_requested");
    case "recover_gift_procurement":
      return recoveryRequest("gift_procurement_recovery_requested");
    case "recover_gift_supplier":
      return recoveryRequest("gift_supplier_recovery_requested");
    case "recover_gift_story":
      return recoveryRequest("gift_story_recovery_requested");
    case "recover_gift_delivery":
      return recoveryRequest("gift_delivery_recovery_requested");
    case "override_iris_review":
      return {
        ...recoveryRequest("iris_override_review_requested"),
        overrideReviewRequired: true,
      };
    case "reclassify_iris":
      return recoveryRequest("iris_reclassification_requested");
    case "resolve_iris_weight_dispute":
      return recoveryRequest("iris_weight_dispute_review_requested");
    case "promote_iris_canonical":
      return recoveryRequest("iris_canonical_promotion_requested");
    case "recover_iris_learning_job":
      return recoveryRequest("iris_learning_recovery_requested");
    case "recover_chat_conversation":
      return recoveryRequest("chat_conversation_recovery_requested");
    case "restore_chat_messages":
      return recoveryRequest("chat_message_restore_review_requested");
    case "moderate_chat_abuse":
      return recoveryRequest("chat_moderation_requested");
    case "export_chat_conversation":
      return recoveryRequest("chat_export_requested");
    case "place_chat_legal_hold":
      return {
        ...recoveryRequest("chat_legal_hold_requested"),
        legalHoldStatus: "requested",
      };
    case "replay_notification":
      return recoveryRequest("notification_replay_requested");
    case "rebuild_notification_queue":
      return recoveryRequest("notification_queue_rebuild_requested");
    case "clear_stuck_notification":
      return recoveryRequest("notification_clear_requested");
    case "retry_checkout":
      return recoveryRequest("checkout_retry_requested");
    case "recover_checkout":
      return recoveryRequest("checkout_recovery_requested");
    case "retry_payment_webhook":
      return recoveryRequest("payment_webhook_retry_requested");
    case "reconcile_ledger":
      return recoveryRequest("ledger_reconciliation_requested");
    case "manual_financial_adjustment":
      return {
        ...recoveryRequest("manual_financial_adjustment_review_requested"),
        financialAdjustmentReviewRequired: true,
      };
    case "investigate_stripe_state":
      return recoveryRequest("stripe_state_investigation_requested");
    case "recover_payment_session":
      return recoveryRequest("payment_session_recovery_requested");
    case "force_logout":
    case "invalidate_refresh_tokens":
      return {
        ...recoveryRequest("session_invalidation_requested"),
        sessionInvalidationRequestedAt: timestamp,
      };
    case "lock_account":
      return {
        ...recoveryRequest("account_lock_requested"),
        accountLockStatus: "locked",
      };
    case "unlock_account":
      return {
        ...recoveryRequest("account_unlock_requested"),
        accountLockStatus: "unlock_review_requested",
      };
    case "reset_mfa":
      return recoveryRequest("mfa_reset_review_requested");
    case "recover_account_access":
      return recoveryRequest("account_access_recovery_requested");
    default:
      throw new functions.https.HttpsError("invalid-argument", "Unsupported governance action.");
  }
}

function publicBefore(data = {}) {
  const result = {};
  for (const key of [
    "status",
    "adminRecoveryStatus",
    "availabilityStatus",
    "isOnline",
    "busy",
    "dispatchEligible",
    "trackingRecoveryStatus",
    "lifecycleRecoveryStatus",
    "recoveryStatus",
    "recoveryOutcome",
    "duplicateResolutionStatus",
    "orphanRecoveryStatus",
    "riderReassignmentStatus",
    "reopenPolicyReviewRequired",
    "forceCompletionReviewRequired",
    "custodyReviewStatus",
    "custodyRecoveryStatus",
    "membershipRecoveryStatus",
    "onboardingRecoveryStatus",
    "dispatchRecoveryStatus",
    "legalHoldStatus",
    "accountLockStatus",
    "financialAdjustmentReviewRequired",
    "count",
    "windowStart",
    "expiresAt",
  ]) {
    if (Object.prototype.hasOwnProperty.call(data, key)) result[key] = data[key];
  }
  return result;
}

function requestMeta(context, data = {}) {
  const headers = context.rawRequest && context.rawRequest.headers ?
    context.rawRequest.headers : {};
  return {
    sourceIp: text(headers["x-forwarded-for"]).split(",")[0] ||
      text(context.rawRequest && context.rawRequest.ip) ||
      null,
    sessionId: text(data.sessionId || data.adminSessionId) || null,
  };
}

exports.adminGovernanceAction = functions.runWith({enforceAppCheck: true}).https.onCall(async (data, context) => {
  const actor = assertSuperAdmin(context);
  const action = lower(data && data.action);
  const reason = requireReason(data);
  const approval = approvalFor(action, actor, data || {});
  const meta = requestMeta(context, data || {});
  if (!ACTIONS.has(action)) {
    throw new functions.https.HttpsError("invalid-argument", "Unsupported governance action.");
  }
  const db = getFirestore();
  const ref = targetRef(db, action, data || {});
  if (!ref.id) {
    throw new functions.https.HttpsError("invalid-argument", "A target is required.");
  }
  const auditRef = db.collection("adminAuditLogs").doc();
  const timelineRef = ref.collection("recoveryTimeline").doc(auditRef.id);
  const result = await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    const before = snapshot.exists ? publicBefore(snapshot.data() || {}) : {};
    if (!snapshot.exists && action !== "reset_address_rate_limit") {
      throw new functions.https.HttpsError(
          "not-found",
          "Recovery target was not found.",
      );
    }
    const patch = patchFor(action, actor, reason);
    if (patch.deleteDocument) {
      transaction.delete(ref);
    } else {
      transaction.set(ref, patch, {merge: true});
    }
    const audit = {
      actionType: `governance_${action}`,
      action,
      approvalTier: approval.tier,
      primaryApprover: approval.primaryApprover,
      secondaryApprover: approval.secondaryApprover,
      elevatedRoleApproved: approval.elevatedRoleApproved,
      actorId: actor.uid,
      actorEmail: actor.email || null,
      actorRoles: actor.roles,
      targetCollection: ref.parent.id,
      targetId: ref.id,
      reason,
      before,
      after: patch.deleteDocument ? {deleted: true} : publicBefore(patch),
      result: "queued",
      recoveryOutcome: "queued",
      source: "circum_admin_governance",
      sourceIp: meta.sourceIp,
      sessionId: meta.sessionId,
      createdAt: FieldValue.serverTimestamp(),
    };
    const timeline = {
      auditId: auditRef.id,
      eventType: "Recovered",
      action,
      actorId: actor.uid,
      actorRole: actor.roles.join(","),
      reason,
      before,
      after: audit.after,
      result: "queued",
      recoveryOutcome: "queued",
      approvalTier: approval.tier,
      primaryApprover: approval.primaryApprover,
      secondaryApprover: approval.secondaryApprover,
      source: "circum_admin_governance",
      sourceIp: meta.sourceIp,
      sessionId: meta.sessionId,
      createdAt: FieldValue.serverTimestamp(),
    };
    transaction.set(auditRef, audit);
    transaction.set(timelineRef, timeline);
    return {auditId: auditRef.id, targetCollection: ref.parent.id, targetId: ref.id};
  });
  return {ok: true, action, ...result};
});
