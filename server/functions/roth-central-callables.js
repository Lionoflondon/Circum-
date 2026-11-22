"use strict";

const functions = require("firebase-functions/v1");
const {defineSecret, defineString} = require("firebase-functions/params");
const {getFirestore} = require("firebase-admin/firestore");
const {senderPaymentCallable} = require("./sender-app-check");
const {createRothCentralClient, STAGING_ORIGIN} = require("./roth-central-client");
const {isAuthorizedCircumIssuer, isValidStagingRewardAmount} = require("./roth-company-issuer");

const mode = defineString("ROTH_CENTRAL_MODE", {default: "disabled"});
const stageProject = defineString("ROTH_COMPANY_STAGING_PROJECT", {default: ""});
const apiOrigin = defineString("ROTH_CENTRAL_API_ORIGIN", {default: STAGING_ORIGIN});
const keyId = defineString("ROTH_CIRCUM_MERCHANT_KEY_ID", {default: ""});
const merchantSecret = defineSecret("ROTH_CIRCUM_MERCHANT_SECRET");
const scopedOptions = {secrets: [merchantSecret]};

function client() {
  const projectId = process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT || "";
  if (mode.value() !== "staging" || !projectId || projectId !== stageProject.value() ||
      !/(^|[-_])(stage|staging|stg|dev|test)([-_]|$)/i.test(projectId) || projectId === "circum-2797c") {
    throw new functions.https.HttpsError("failed-precondition", "Central ROTH is not enabled in this CIRCUM staging environment.");
  }
  try {
    return createRothCentralClient({baseUrl: apiOrigin.value(), keyId: keyId.value(), secret: merchantSecret.value()});
  } catch (_error) {
    throw new functions.https.HttpsError("failed-precondition", "ROTH staging credentials are not configured.");
  }
}

function requireCustomer(context) {
  if (!context.auth || !context.auth.uid) throw new functions.https.HttpsError("unauthenticated", "Sign in to your CIRCUM account first.");
  return context.auth.uid;
}

async function requireCompanyIssuer(context) {
  const uid = requireCustomer(context);
  const snapshot = await getFirestore().collection("adminUsers").doc(uid).get();
  const data = snapshot.exists ? snapshot.data() || {} : {};
  if (isAuthorizedCircumIssuer(data)) return uid;
  throw new functions.https.HttpsError("permission-denied", "An authorised CIRCUM issuer role is required.");
}

exports.beginRothAccountLink = senderPaymentCallable(async (_data, context) => {
  const uid = requireCustomer(context);
  return client().startLink(uid);
}, scopedOptions);

exports.getRothCentralCompanyBalance = senderPaymentCallable(async (_data, context) => {
  const uid = requireCustomer(context);
  return client().balance(uid);
}, scopedOptions);

exports.issueRothFromCircum = senderPaymentCallable(async (data, context) => {
  const actorUid = await requireCompanyIssuer(context);
  const uid = String(data && (data.customerUid || data.recipientUid) || "").trim();
  const rewardId = String(data && data.rewardId || "").trim();
  const reason = String(data && data.reason || "").trim();
  const amountPence = Number(data && data.amountPence);
  if (!/^[A-Za-z0-9_-]{1,128}$/.test(uid) || !/^[A-Za-z0-9_-]{1,160}$/.test(rewardId) ||
      !isValidStagingRewardAmount(amountPence) || reason.length < 8 || reason.length > 500) {
    throw new functions.https.HttpsError("invalid-argument", "Provide a valid customer, reward reference, pence amount and reason.");
  }
  const result = await client().issueReward({externalId: uid, rewardId, amountPence, reason});
  return { ...result, actorUid };
}, scopedOptions);

