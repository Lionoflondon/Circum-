/* eslint-disable max-len, require-jsdoc */
"use strict";

const crypto = require("crypto");
const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue, Timestamp} = require("firebase-admin/firestore");
const {getAuth} = require("firebase-admin/auth");
const {BALANCE_TYPES, TRANSACTION_TYPES, roundMoney} = require("./roth-ledger-core");
const {recordRothMovement, requireTrustedRothAdmin} = require("./roth-ledger");

const MAX_ROTH_PER_USER = 1000;
const MAX_CAMPAIGN_ROTH = 1000000;
const MAX_RECIPIENTS = 100000;
const CLAIM_TTL_MS = 10 * 60 * 1000;

function clean(value) {
  return `${value || ""}`.trim();
}

function stable(value) {
  if (Array.isArray(value)) return `[${value.map(stable).join(",")}]`;
  if (value && typeof value === "object") {
    return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${stable(value[key])}`).join(",")}}`;
  }
  return JSON.stringify(value == null ? null : value);
}

function definitionHash(definition) {
  return crypto.createHash("sha256").update(stable(definition)).digest("hex");
}

function campaignDefinition(data) {
  const amount = roundMoney(Number(data.rothPerUser));
  if (!Number.isFinite(amount) || amount <= 0 || amount > MAX_ROTH_PER_USER) {
    throw new functions.https.HttpsError("invalid-argument", "Roth amount exceeds the campaign limit.");
  }
  const scope = data.recipientScope || "active_customers";
  if (scope !== "active_customers") {
    throw new functions.https.HttpsError("invalid-argument", "Only the active customer scope is enabled for the first release.");
  }
  return {
    name: clean(data.name),
    description: clean(data.description),
    rothPerUser: amount,
    recipientScope: scope,
    eligibilityRules: data.eligibilityRules || {},
    uidAllowlist: Array.isArray(data.uidAllowlist) ? [...new Set(data.uidAllowlist.map(clean).filter(Boolean))].sort() : [],
    uidExclusionList: Array.isArray(data.uidExclusionList) ? [...new Set(data.uidExclusionList.map(clean).filter(Boolean))].sort() : [],
  };
}

function isEligibleUser(uid, user = {}, definition) {
  const role = clean(user.role || user.accountType || user.userType).toLowerCase();
  const excludedRoles = new Set(["rider", "admin", "super_admin", "finance_admin", "operations_admin", "service", "internal", "test"]);
  if (user.deleted === true || user.deletedAt || user.closed === true || user.closedAt) return {eligible: false, reason: "closed_or_deleted"};
  if (user.suspended === true || ["suspended", "frozen", "fraud_blocked"].includes(clean(user.accountStatus || user.status).toLowerCase())) return {eligible: false, reason: "suspended_or_blocked"};
  if (excludedRoles.has(role) || user.isInternal === true || user.isTestAccount === true || user.serviceAccount === true) return {eligible: false, reason: "internal_or_excluded_account"};
  if (definition.uidAllowlist.length && !definition.uidAllowlist.includes(uid)) return {eligible: false, reason: "not_in_allowlist"};
  if (definition.uidExclusionList.includes(uid)) return {eligible: false, reason: "explicitly_excluded"};
  if (definition.eligibilityRules.verifiedEmail === true && user.emailVerified !== true) return {eligible: false, reason: "email_not_verified"};
  return {eligible: true, reason: null};
}

function requireCampaignId(data) {
  const id = clean(data.campaignId);
  if (!id || !/^[a-zA-Z0-9_-]{1,100}$/.test(id)) throw new functions.https.HttpsError("invalid-argument", "A valid campaign ID is required.");
  return id;
}

async function audit(db, actor, campaignId, action, metadata = {}) {
  await db.collection("adminAuditLogs").add({
    adminUserId: actor.uid,
    adminEmail: actor.email || null,
    actionType: action,
    recordType: "rothGrantCampaigns",
    recordId: campaignId,
    newValue: metadata,
    createdAt: FieldValue.serverTimestamp(),
  });
}

async function loadDefinition(campaign) {
  return campaign.definition || {
    name: campaign.name,
    description: campaign.description,
    rothPerUser: campaign.rothPerUser,
    recipientScope: campaign.recipientScope,
    eligibilityRules: campaign.eligibilityRules || {},
    uidAllowlist: campaign.uidAllowlist || [],
    uidExclusionList: campaign.uidExclusionList || [],
  };
}

exports.createRothGrantCampaign = functions.runWith({enforceAppCheck: true}).https.onCall(async (data, context) => {
  const actor = await requireTrustedRothAdmin(context);
  const definition = campaignDefinition(data || {});
  if (!definition.name) throw new functions.https.HttpsError("invalid-argument", "Campaign name is required.");
  const db = getFirestore();
  const campaignId = clean(data.campaignId) || db.collection("rothGrantCampaigns").doc().id;
  const ref = db.collection("rothGrantCampaigns").doc(campaignId);
  const hash = definitionHash(definition);
  await ref.create({campaignId, ...definition, definition, definitionHash: hash, status: "draft", createdBy: actor.uid, createdAt: FieldValue.serverTimestamp(), estimatedRecipients: 0, estimatedRothLiability: 0, actualRecipients: 0, actualRothGranted: 0, failureCount: 0});
  await audit(db, actor, campaignId, "roth_grant_campaign_created", {definitionHash: hash});
  return {campaignId, status: "draft", definitionHash: hash};
});

exports.dryRunRothGrantCampaign = functions.runWith({enforceAppCheck: true}).https.onCall(async (data, context) => {
  const actor = await requireTrustedRothAdmin(context);
  const campaignId = requireCampaignId(data || {});
  const db = getFirestore();
  const ref = db.collection("rothGrantCampaigns").doc(campaignId);
  const snap = await ref.get();
  if (!snap.exists || snap.data().status !== "draft") throw new functions.https.HttpsError("failed-precondition", "Campaign must be in draft status.");
  const campaign = snap.data();
  const definition = await loadDefinition(campaign);
  const users = await db.collection("users").get();
  const counts = {};
  const eligible = [];
  for (const doc of users.docs) {
    const result = isEligibleUser(doc.id, doc.data(), definition);
    if (result.eligible) eligible.push(doc); else counts[result.reason] = (counts[result.reason] || 0) + 1;
  }
  if (eligible.length > MAX_RECIPIENTS || eligible.length * definition.rothPerUser > MAX_CAMPAIGN_ROTH) {
    throw new functions.https.HttpsError("failed-precondition", "Campaign exceeds the configured safety limits.");
  }
  for (let offset = 0; offset < eligible.length; offset += 400) {
    const batch = db.batch();
    for (const doc of eligible.slice(offset, offset + 400)) {
      batch.set(ref.collection("recipients").doc(doc.id), {uid: doc.id, eligibilityStatus: "eligible", grantStatus: "pending", amountRoth: definition.rothPerUser, campaignId, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
    }
    await batch.commit();
  }
  await ref.update({status: "dry_run_complete", definitionHash: definitionHash(definition), dryRunBy: actor.uid, dryRunAt: FieldValue.serverTimestamp(), estimatedRecipients: eligible.length, estimatedRothLiability: roundMoney(eligible.length * definition.rothPerUser), excludedAccountCount: users.size - eligible.length, exclusionReasons: counts});
  await audit(db, actor, campaignId, "roth_grant_campaign_dry_run", {eligibleRecipients: eligible.length, estimatedRothLiability: roundMoney(eligible.length * definition.rothPerUser)});
  return {campaignId, rothPerUser: definition.rothPerUser, eligibleRecipients: eligible.length, excludedRecipients: users.size - eligible.length, estimatedRothLiability: roundMoney(eligible.length * definition.rothPerUser), exclusionReasons: counts, sampleEligibleUids: eligible.slice(0, 20).map((doc) => doc.id), definitionHash: definitionHash(definition)};
});

exports.approveRothGrantCampaign = functions.runWith({enforceAppCheck: true}).https.onCall(async (data, context) => {
  const actor = await requireTrustedRothAdmin(context);
  const campaignId = requireCampaignId(data || {});
  const db = getFirestore();
  const ref = db.collection("rothGrantCampaigns").doc(campaignId);
  await db.runTransaction(async (transaction) => {
    const snap = await transaction.get(ref);
    if (!snap.exists || snap.data().status !== "dry_run_complete") throw new functions.https.HttpsError("failed-precondition", "A completed dry run is required.");
    const campaign = snap.data();
    if (campaign.definitionHash !== definitionHash(await loadDefinition(campaign))) throw new functions.https.HttpsError("failed-precondition", "Campaign definition changed; rerun the dry run.");
    transaction.update(ref, {status: "approved", approvedBy: actor.uid, approvedAt: FieldValue.serverTimestamp(), approvedDefinitionHash: campaign.definitionHash});
  });
  await audit(db, actor, campaignId, "roth_grant_campaign_approved");
  return {campaignId, status: "approved"};
});

exports.executeRothGrantCampaign = functions.runWith({enforceAppCheck: true, timeoutSeconds: 540}).https.onCall(async (data, context) => {
  const actor = await requireTrustedRothAdmin(context);
  const campaignId = requireCampaignId(data || {});
  const db = getFirestore();
  const ref = db.collection("rothGrantCampaigns").doc(campaignId);
  const first = await ref.get();
  if (!first.exists || !["approved", "executing", "partially_failed"].includes(first.data().status)) throw new functions.https.HttpsError("failed-precondition", "Campaign is not approved for execution.");
  const campaign = first.data();
  const definition = await loadDefinition(campaign);
  await ref.update({status: "executing", executedBy: actor.uid, executedAt: campaign.executedAt || FieldValue.serverTimestamp()});
  const statuses = data.retryFailed === true ? ["pending", "processing", "failed"] : ["pending", "processing"];
  const pending = await ref.collection("recipients").where("grantStatus", "in", statuses).limit(100).get();
  let granted = 0; let failures = 0;
  for (const recipient of pending.docs) {
    const claim = `${actor.uid}_${Date.now()}_${Math.random()}`;
    let claimed = false;
    await db.runTransaction(async (transaction) => {
      const current = await transaction.get(recipient.ref);
      const value = current.data() || {};
      const stale = value.grantStatus === "processing" && value.processingAt && Date.now() - value.processingAt.toMillis() > CLAIM_TTL_MS;
      if (value.grantStatus === "pending" || stale) {
        transaction.update(recipient.ref, {grantStatus: "processing", processingClaim: claim, processingAt: Timestamp.now(), updatedAt: FieldValue.serverTimestamp()});
        claimed = true;
      }
    });
    if (!claimed) continue;
    try {
      const user = await getAuth().getUser(recipient.id);
      const result = await recordRothMovement({userId: user.uid, uid: user.uid, userEmail: user.email, amount: definition.rothPerUser, balanceType: BALANCE_TYPES.rothCredit, type: TRANSACTION_TYPES.adminCredit, reason: definition.name, issuedByAdminId: actor.uid, issuedByAdminEmail: actor.email, transactionId: `roth_campaign_${campaignId}_${recipient.id}`, idempotencyKey: `roth_campaign:${campaignId}:${recipient.id}`, relatedEntityId: campaignId, metadata: {source: "roth_grant_campaign", sourceType: "roth_grant_campaign", campaignId, campaignName: definition.name, idempotencyKey: `roth_campaign:${campaignId}:${recipient.id}`}});
      await recipient.ref.update({grantStatus: "granted", ledgerEntryId: result.transactionId, processedAt: FieldValue.serverTimestamp(), processingClaim: null, updatedAt: FieldValue.serverTimestamp()});
      granted++;
    } catch (error) {
      failures++;
      await recipient.ref.update({grantStatus: "failed", failureCode: error.code || "grant_failed", failureMessage: "Grant could not be completed.", updatedAt: FieldValue.serverTimestamp()});
    }
  }
  const remaining = await ref.collection("recipients").where("grantStatus", "in", ["pending", "processing"]).limit(1).get();
  const status = remaining.empty ? (failures ? "partially_failed" : "completed") : "executing";
  await ref.update({status, completedAt: remaining.empty ? FieldValue.serverTimestamp() : null, actualRecipients: FieldValue.increment(granted), actualRothGranted: FieldValue.increment(roundMoney(granted * definition.rothPerUser)), failureCount: FieldValue.increment(failures)});
  await audit(db, actor, campaignId, "roth_grant_campaign_execution_batch", {granted, failures, status});
  return {campaignId, status, granted, failures, remaining: !remaining.empty};
});

exports.reconcileRothGrantCampaign = functions.runWith({enforceAppCheck: true}).https.onCall(async (data, context) => {
  const actor = await requireTrustedRothAdmin(context);
  const campaignId = requireCampaignId(data || {});
  const db = getFirestore();
  const campaignRef = db.collection("rothGrantCampaigns").doc(campaignId);
  const recipients = await campaignRef.collection("recipients").where("grantStatus", "==", "granted").get();
  const ledger = await db.collection("rothLedger").where("metadata.campaignId", "==", campaignId).get();
  const expected = recipients.docs.reduce((sum, doc) => sum + Number(doc.data().amountRoth || 0), 0);
  const actual = ledger.docs.reduce((sum, doc) => sum + Number(doc.data().amount || 0), 0);
  const result = {campaignId, recipientCount: recipients.size, ledgerCount: ledger.size, expectedRoth: roundMoney(expected), actualRoth: roundMoney(actual), ok: recipients.size === ledger.size && roundMoney(expected) === roundMoney(actual)};
  await audit(db, actor, campaignId, "roth_grant_campaign_reconciled", result);
  return result;
});

module.exports.MAX_ROTH_PER_USER = MAX_ROTH_PER_USER;
module.exports.MAX_CAMPAIGN_ROTH = MAX_CAMPAIGN_ROTH;
module.exports.definitionHash = definitionHash;
module.exports.isEligibleUser = isEligibleUser;
