/* eslint-disable max-len, require-jsdoc */
const payoutAllocation = require("./rider-payout-allocation");
const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {payoutReadiness} = require("./rider-certification-policy");
const {riderCallable} = require("./rider-app-check");

const appBaseUrl = process.env.APP_BASE_URL || "https://circumuk.com";
const adminBaseUrl = process.env.ADMIN_BASE_URL || "https://admin.circumuk.com";
const riderStripeReturnUrl = `${appBaseUrl}/rider/stripe/return`;
const riderStripeRefreshUrl = `${appBaseUrl}/rider/stripe/refresh`;

const rawBankFields = ["bankName", "sortCode", "accountNumber", "bankAccountNumber"];
const stripeSecretRuntime = functions.runWith({secrets: ["STRIPE_SECRET_KEY"]});
const stripeWebhookRuntime = functions.runWith({secrets: ["STRIPE_SECRET_KEY", "STRIPE_WEBHOOK_SECRET"]});
const riderStripeCallable = (handler) => functions.runWith({
  secrets: ["STRIPE_SECRET_KEY"],
  enforceAppCheck: true,
}).https.onCall(handler);

function text(value) {
  return `${value || ""}`.trim();
}

function urlWithParams(url, params = {}) {
  const parsed = new URL(url);
  Object.entries(params).forEach(([key, value]) => {
    const normalized = text(value);
    if (normalized) parsed.searchParams.set(key, normalized);
  });
  return parsed.toString();
}

function stripeFrom(stripeOrFactory) {
  return typeof stripeOrFactory === "function" ? stripeOrFactory() : stripeOrFactory;
}

function stripeClientMode(stripe) {
  return stripe && stripe._circumStripeMode ? stripe._circumStripeMode : "unknown";
}

function numberValue(value, fallback = 0) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function roundMoney(value) {
  return Math.round(numberValue(value) * 100) / 100;
}

function payoutFeePolicy() {
  const percentBps = numberValue(
      process.env.RIDER_PAYOUT_STRIPE_FEE_PERCENT_BPS ||
      150,
  );
  const fixedPence = numberValue(
      process.env.RIDER_PAYOUT_STRIPE_FEE_FIXED_PENCE ||
      20,
  );
  const minimumPence = numberValue(
      process.env.RIDER_PAYOUT_STRIPE_FEE_MINIMUM_PENCE ||
      0,
  );
  return {
    source: "backend_config",
    percentBps,
    fixedPence,
    minimumPence,
  };
}

function estimateStripeFee(amountGbp, policy = payoutFeePolicy()) {
  const grossPence = Math.max(0, Math.round(numberValue(amountGbp) * 100));
  if (grossPence <= 0) return 0;
  const percentagePence = Math.ceil((grossPence * Math.max(0, policy.percentBps)) / 10000);
  const feePence = Math.max(
      Math.round(Math.max(0, policy.minimumPence)),
      percentagePence + Math.round(Math.max(0, policy.fixedPence)),
  );
  return roundMoney(feePence / 100);
}

function resolveRiderPayoutBreakdown(input = {}) {
  const riderGrossShare = roundMoney(input.riderGrossShare || input.amount || 0);
  const totalCustomerPaid = roundMoney(input.totalCustomerPaid || input.customerPaid || input.total || 0);
  const suppliedCommission = input.circumPlatformCommission != null ?
    input.circumPlatformCommission :
    input.platformCommission;
  const circumPlatformCommission = roundMoney(
      suppliedCommission == null && totalCustomerPaid > 0 ?
        Math.max(0, totalCustomerPaid - riderGrossShare) :
        numberValue(suppliedCommission, 0),
  );
  const policy = payoutFeePolicy();
  const estimatedStripeFees = roundMoney(
      input.estimatedStripeFees == null ?
        estimateStripeFee(riderGrossShare, policy) :
        numberValue(input.estimatedStripeFees, 0),
  );
  const riderNetPayout = roundMoney(riderGrossShare - estimatedStripeFees);
  return {
    totalCustomerPaid,
    circumPlatformCommission,
    estimatedStripeFees,
    riderGrossShare,
    stripeFeeDeductedFromRider: estimatedStripeFees,
    riderNetPayout,
    payoutFeePayer: "rider",
    payoutFeePolicy: policy,
    adminReviewRequired: riderNetPayout <= 0,
  };
}

function stripeTransferIdempotencyKey(requestId) {
  return `rider_payout_transfer_${text(requestId)}`;
}

function stripeConnectAccountIdempotencyKey(riderId, replacedAccountId = "") {
  const generation = text(replacedAccountId) || "initial";
  return `rider_connect_account_${text(riderId)}_${generation}`;
}

function hasRawBankFields(data) {
  return rawBankFields.some((field) => {
    const value = text(data && data[field]);
    return value.length > 0 && value !== "REMOVED";
  });
}

async function riderIdForStripeAccount(db, account = {}) {
  const metadataRiderId = text(account.metadata && account.metadata.riderId);
  if (metadataRiderId) return metadataRiderId;
  const accountId = text(account.id);
  if (!accountId) return "";
  const direct = await db.collection("riderProfiles")
      .where("stripeAccountId", "==", accountId)
      .limit(1)
      .get();
  if (!direct.empty) return direct.docs[0].id;
  const connect = await db.collection("riderProfiles")
      .where("stripeConnectAccountId", "==", accountId)
      .limit(1)
      .get();
  return connect.empty ? "" : connect.docs[0].id;
}

function riderWithdrawalFailure({
  amount,
  available,
  minimum = 1,
  existingStatus = "",
  approvedRider = false,
  stripeReady = false,
  payoutPaused = false,
} = {}) {
  if (!approvedRider) return "approval_required";
  if (!stripeReady || payoutPaused) return "stripe_not_ready";
  if (["requested", "pending", "approved", "processing"]
      .includes(text(existingStatus).toLowerCase())) {
    return "duplicate_pending";
  }
  if (roundMoney(amount) <= 0) return "invalid_amount";
  if (roundMoney(amount) < roundMoney(minimum)) return "below_minimum";
  if (roundMoney(amount) > roundMoney(available)) return "exceeds_available";
  return null;
}

async function isAdmin(uid) {
  if (!uid) return false;
  const db = getFirestore();
  const adminDoc = await db.collection("adminUsers").doc(uid).get();
  if (adminDoc.exists) {
    const data = adminDoc.data() || {};
    if (data.active !== false) return true;
  }
  return false;
}

async function assertActor(context, riderId, {adminOnly = false} = {}) {
  const uid = context.auth && context.auth.uid;
  if (!uid) {
    throw new functions.https.HttpsError("unauthenticated", "Sign in first.");
  }
  const admin = await isAdmin(uid);
  if (adminOnly && !admin) {
    throw new functions.https.HttpsError("permission-denied", "Admin access required.");
  }
  if (!admin && uid !== riderId) {
    throw new functions.https.HttpsError("permission-denied", "You can only manage your own payout setup.");
  }
  return {uid, admin};
}

async function loadRider(riderId) {
  const db = getFirestore();
  const profileRef = db.collection("riderProfiles").doc(riderId);
  const profileDoc = await profileRef.get();
  const profile = profileDoc.exists ? profileDoc.data() || {} : {};
  if (!profileDoc.exists) {
    throw new functions.https.HttpsError("not-found", "Rider profile not found.");
  }
  return {profileRef, profile};
}

async function loadRiderDocuments(riderId) {
  const snapshot = await getFirestore().collection("riderDocuments")
      .where("riderId", "==", riderId)
      .limit(100)
      .get();
  return snapshot.docs.map((doc) => ({id: doc.id, ...doc.data()}));
}

async function computeRiderPayoutReadiness(riderId) {
  const {profile} = await loadRider(riderId);
  const documents = await loadRiderDocuments(riderId);
  return payoutReadiness(profile, documents);
}

function stripeStatusFromAccount(account) {
  if (!account || !account.id) return "not_started";
  const requirements = account.requirements || {};
  const currentlyDue = requirements.currently_due || [];
  const pastDue = requirements.past_due || [];
  if (text(requirements.disabled_reason)) return "disabled";
  if (currentlyDue.length > 0 || pastDue.length > 0) return "action_required";
  if (account.details_submitted !== true) return "onboarding";
  if (account.payouts_enabled === true) return "payouts_enabled";
  if (account.charges_enabled === false && account.details_submitted === true) {
    return "restricted";
  }
  return "connected";
}

function connectPatch(account, extra = {}) {
  const requirements = account.requirements || {};
  const currentlyDue = requirements.currently_due || [];
  const pastDue = requirements.past_due || [];
  const payoutsEnabled = account.payouts_enabled === true;
  const chargesEnabled = account.charges_enabled === true;
  const detailsSubmitted = account.details_submitted === true;
  const onboardingComplete = detailsSubmitted && payoutsEnabled;
  const stripeStatus = stripeStatusFromAccount(account);
  return {
    stripeConnectAccountId: account.id,
    stripeAccountId: account.id,
    stripeMode: extra.stripeMode || "unknown",
    stripeConnectType: "express",
    stripeStatus,
    stripeConnectStatus: stripeStatus,
    stripeOnboardingStarted: true,
    stripeDetailsSubmitted: detailsSubmitted,
    stripeChargesEnabled: chargesEnabled,
    stripePayoutsEnabled: payoutsEnabled,
    stripeOnboardingStatus: stripeStatus === "payouts_enabled" ? "complete" : "incomplete",
    payoutsEnabled,
    chargesEnabled,
    onboardingComplete,
    payoutPaused: false,
    payoutFeePayer: "rider",
    stripeRequirementsDue: currentlyDue,
    stripeRequirementsPastDue: pastDue,
    stripeDisabledReason: requirements.disabled_reason || null,
    stripeLastSyncedAt: FieldValue.serverTimestamp(),
    stripeLastCheckedAt: FieldValue.serverTimestamp(),
    lastStripeSyncAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
    ...extra,
  };
}

async function updateRiderConnectFields(riderId, patch) {
  const db = getFirestore();
  const batch = db.batch();
  batch.set(db.collection("riderProfiles").doc(riderId), patch, {merge: true});
  batch.set(db.collection("riders").doc(riderId), patch, {merge: true});
  await batch.commit();
}

function resetStripeFieldsPatch({staleAccountId = "", staleMode = "test"} = {}) {
  return {
    staleStripeAccountId: staleAccountId || FieldValue.delete(),
    staleStripeMode: staleAccountId ? staleMode : FieldValue.delete(),
    staleStripeResetAt: staleAccountId ? FieldValue.serverTimestamp() : FieldValue.delete(),
    stripeConnectAccountId: FieldValue.delete(),
    stripeAccountId: FieldValue.delete(),
    stripeMode: FieldValue.delete(),
    stripeStatus: "not_started",
    stripeConnectStatus: "not_started",
    stripeConnectType: FieldValue.delete(),
    stripeOnboardingStarted: false,
    stripeDetailsSubmitted: false,
    stripeChargesEnabled: false,
    stripePayoutsEnabled: false,
    stripeRequirementsDue: [],
    stripeRequirementsPastDue: [],
    stripeDisabledReason: null,
    stripeOnboardingStatus: "incomplete",
    payoutsEnabled: false,
    chargesEnabled: false,
    onboardingComplete: false,
    stripeLastSyncedAt: FieldValue.serverTimestamp(),
    stripeLastCheckedAt: FieldValue.serverTimestamp(),
    lastStripeSyncAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };
}

async function resetRiderStripeFields(riderId, options = {}) {
  await updateRiderConnectFields(riderId, resetStripeFieldsPatch(options));
}

async function retrieveUsableAccount(stripe, riderId, accountId) {
  if (!accountId) return null;
  try {
    return await stripe.accounts.retrieve(accountId);
  } catch (error) {
    if (error && (error.code === "resource_missing" || error.statusCode === 404)) {
      await resetRiderStripeFields(riderId, {
        staleAccountId: accountId,
        staleMode: stripeClientMode(stripe) === "live" ? "test_or_missing" : "missing",
      });
      return null;
    }
    throw error;
  }
}

function createStripeConnectAccountForRider(stripeOrFactory) {
  return riderStripeCallable(async (_data, context) => {
    const stripe = stripeFrom(stripeOrFactory);
    const mode = stripeClientMode(stripe);
    const riderId = text(context.auth && context.auth.uid);
    await assertActor(context, riderId);
    const {profile} = await loadRider(riderId);
    const existingAccountId = text(profile.stripeConnectAccountId || profile.stripeAccountId);
    if (existingAccountId) {
      const existingAccount = await retrieveUsableAccount(stripe, riderId, existingAccountId);
      if (existingAccount) {
        await updateRiderConnectFields(riderId, connectPatch(existingAccount, {stripeMode: mode}));
        return {
          stripeConnectAccountId: existingAccount.id,
          stripeAccountId: existingAccount.id,
          stripeConnectType: "express",
          stripeMode: mode,
          payoutFeePayer: "rider",
          alreadyExists: true,
        };
      }
    }
    const account = await stripe.accounts.create({
      type: "express",
      country: "GB",
      email: text(profile.email || (context.auth && context.auth.token && context.auth.token.email)) || undefined,
      business_type: "individual",
      capabilities: {
        transfers: {requested: true},
      },
      metadata: {
        riderId,
        payoutFeePayer: "rider",
        platform: "circum",
      },
    }, {
      idempotencyKey: stripeConnectAccountIdempotencyKey(
          riderId,
          existingAccountId,
      ),
    });
    await updateRiderConnectFields(riderId, connectPatch(account, {
      stripeMode: mode,
      stripeStatus: "onboarding",
      stripeConnectStatus: "onboarding",
      stripeOnboardingCreatedAt: FieldValue.serverTimestamp(),
    }));
    await getFirestore().collection("riderPayoutAudit").add({
      riderId,
      action: "stripe_connect_account_created",
      stripeConnectType: "express",
      stripeAccountId: account.id,
      actorId: context.auth.uid,
      actorType: context.auth.uid === riderId ? "rider" : "admin",
      payoutFeePayer: "rider",
      createdAt: FieldValue.serverTimestamp(),
    });
    return {
      stripeConnectAccountId: account.id,
      stripeAccountId: account.id,
      stripeConnectType: "express",
      stripeMode: mode,
      payoutFeePayer: "rider",
    };
  });
}

function createStripeOnboardingLink(stripeOrFactory) {
  return riderStripeCallable(async (_data, context) => {
    const stripe = stripeFrom(stripeOrFactory);
    const mode = stripeClientMode(stripe);
    const riderId = text(context.auth && context.auth.uid);
    await assertActor(context, riderId);
    const {profile} = await loadRider(riderId);
    let accountId = text(profile.stripeConnectAccountId || profile.stripeAccountId);
    if (accountId) {
      const existingAccount = await retrieveUsableAccount(stripe, riderId, accountId);
      if (existingAccount) {
        await updateRiderConnectFields(riderId, connectPatch(existingAccount, {stripeMode: mode}));
      } else {
        accountId = "";
      }
    }
    if (!accountId) {
      const created = await stripe.accounts.create({
        type: "express",
        country: "GB",
        email: text(profile.email || (context.auth && context.auth.token && context.auth.token.email)) || undefined,
        business_type: "individual",
        capabilities: {transfers: {requested: true}},
        metadata: {riderId, payoutFeePayer: "rider", platform: "circum"},
      }, {
        idempotencyKey: stripeConnectAccountIdempotencyKey(
            riderId,
            text(profile.stripeConnectAccountId || profile.stripeAccountId),
        ),
      });
      accountId = created.id;
      await updateRiderConnectFields(riderId, connectPatch(created, {
        stripeMode: mode,
        stripeStatus: "onboarding",
        stripeConnectStatus: "onboarding",
      }));
    }
    const returnUrl = urlWithParams(riderStripeReturnUrl, {riderId});
    const refreshUrl = urlWithParams(riderStripeRefreshUrl, {riderId});
    const link = await stripe.accountLinks.create({
      account: accountId,
      refresh_url: refreshUrl,
      return_url: returnUrl,
      type: "account_onboarding",
    });
    await updateRiderConnectFields(riderId, {
      stripeStatus: "onboarding",
      stripeConnectStatus: "onboarding",
      stripeMode: mode,
      stripeOnboardingStarted: true,
      payoutFeePayer: "rider",
      stripeLastSyncedAt: FieldValue.serverTimestamp(),
      lastStripeSyncAt: FieldValue.serverTimestamp(),
    });
    return {
      url: link.url,
      stripeConnectAccountId: accountId,
      stripeAccountId: accountId,
      stripeConnectType: "express",
      stripeMode: mode,
      returnUrl,
      refreshUrl,
    };
  });
}

function refreshStripeOnboardingLink(stripe) {
  return createStripeOnboardingLink(stripe);
}

function syncStripeConnectStatus(stripeOrFactory) {
  return riderStripeCallable(async (_data, context) => {
    const stripe = stripeFrom(stripeOrFactory);
    const mode = stripeClientMode(stripe);
    const riderId = text(context.auth && context.auth.uid);
    await assertActor(context, riderId);
    const {profile} = await loadRider(riderId);
    const accountId = text(profile.stripeConnectAccountId || profile.stripeAccountId);
    if (!accountId) {
      const patch = {
        stripeStatus: "not_started",
        stripeConnectStatus: "not_started",
        stripeOnboardingStarted: false,
        stripeDetailsSubmitted: false,
        stripeChargesEnabled: false,
        stripePayoutsEnabled: false,
        payoutsEnabled: false,
        chargesEnabled: false,
        onboardingComplete: false,
        payoutFeePayer: "rider",
        stripeRequirementsDue: [],
        stripeRequirementsPastDue: [],
        stripeDisabledReason: null,
        stripeMode: FieldValue.delete(),
        stripeLastSyncedAt: FieldValue.serverTimestamp(),
        stripeLastCheckedAt: FieldValue.serverTimestamp(),
        lastStripeSyncAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      };
      await updateRiderConnectFields(riderId, patch);
      return {
        stripeStatus: "not_started",
        stripeConnectType: "express",
        stripeMode: null,
        stripeDetailsSubmitted: false,
        stripeChargesEnabled: false,
        stripePayoutsEnabled: false,
        payoutsEnabled: false,
        chargesEnabled: false,
        onboardingComplete: false,
        payoutPaused: profile.payoutPaused === true,
        payoutFeePayer: "rider",
        requirementsDue: [],
        disabledReason: null,
      };
    }
    const account = await retrieveUsableAccount(stripe, riderId, accountId);
    if (!account) {
      return {
        stripeStatus: "not_started",
        stripeConnectType: "express",
        stripeMode: mode,
        staleStripeAccountId: accountId,
        stripeDetailsSubmitted: false,
        stripeChargesEnabled: false,
        stripePayoutsEnabled: false,
        payoutsEnabled: false,
        chargesEnabled: false,
        onboardingComplete: false,
        payoutPaused: profile.payoutPaused === true,
        payoutFeePayer: "rider",
        requirementsDue: [],
        disabledReason: null,
      };
    }
    const patch = connectPatch(account, {stripeMode: mode});
    await updateRiderConnectFields(riderId, patch);
    return {
      stripeConnectAccountId: account.id,
      stripeAccountId: account.id,
      stripeConnectType: "express",
      stripeMode: mode,
      stripeStatus: patch.stripeStatus,
      stripeDetailsSubmitted: patch.stripeDetailsSubmitted,
      stripeChargesEnabled: patch.stripeChargesEnabled,
      stripePayoutsEnabled: patch.stripePayoutsEnabled,
      stripeOnboardingStatus: patch.stripeOnboardingStatus,
      payoutsEnabled: patch.payoutsEnabled,
      chargesEnabled: patch.chargesEnabled,
      onboardingComplete: patch.onboardingComplete,
      payoutPaused: patch.payoutPaused,
      payoutFeePayer: "rider",
      requirementsDue: patch.stripeRequirementsDue,
      disabledReason: patch.stripeDisabledReason,
    };
  });
}

function createStripeAccountManagementLink(stripeOrFactory) {
  return riderStripeCallable(async (data, context) => {
    const stripe = stripeFrom(stripeOrFactory);
    const riderId = text(context.auth && context.auth.uid);
    await assertActor(context, riderId);
    const {profile} = await loadRider(riderId);
    const accountId = text(profile.stripeConnectAccountId || profile.stripeAccountId);
    const account = await retrieveUsableAccount(stripe, riderId, accountId);
    if (!account || account.details_submitted !== true) {
      throw new functions.https.HttpsError(
          "failed-precondition",
          "Complete payout account setup first.",
      );
    }
    const link = await stripe.accounts.createLoginLink(account.id);
    const url = text(link && link.url);
    if (!url) {
      throw new functions.https.HttpsError(
          "internal",
          "Payout account management is temporarily unavailable.",
      );
    }
    return {url};
  });
}

function riderPayoutReadiness() {
  return riderCallable(async (_data, context) => {
    const riderId = text(context.auth && context.auth.uid);
    await assertActor(context, riderId);
    const readiness = await computeRiderPayoutReadiness(riderId);
    await updateRiderConnectFields(riderId, {
      payoutReadinessStatus: readiness.status,
      payoutReady: readiness.ready,
      payoutReadinessChecks: readiness.checks,
      payoutReadinessMissingDocuments: readiness.missingDocuments,
      payoutReadinessUpdatedAt: FieldValue.serverTimestamp(),
    });
    return {
      riderId,
      ...readiness,
      labels: {
        not_started: "Not started",
        in_progress: "In progress",
        additional_information_required: "Additional information required",
        charges_enabled: "Charges enabled",
        payouts_enabled: "Payouts enabled",
        fully_payout_ready: "Fully payout ready",
      },
    };
  });
}

function resetRiderTestStripeAccount() {
  return riderCallable(async (data, context) => {
    const riderId = text(data && data.riderId);
    await assertActor(context, riderId, {adminOnly: true});
    if (!riderId) {
      throw new functions.https.HttpsError("invalid-argument", "Rider is required.");
    }
    const {profile} = await loadRider(riderId);
    const staleAccountId = text(profile.stripeAccountId || profile.stripeConnectAccountId);
    const staleMode = text(profile.stripeMode || profile.staleStripeMode || "test_or_missing");
    await resetRiderStripeFields(riderId, {
      staleAccountId,
      staleMode,
    });
    await getFirestore().collection("riderPayoutAudit").add({
      riderId,
      action: "stripe_test_account_reset",
      staleStripeAccountId: staleAccountId || null,
      staleStripeMode: staleMode || null,
      actorId: context.auth.uid,
      actorType: "admin",
      createdAt: FieldValue.serverTimestamp(),
    });
    return {
      stripeStatus: "not_started",
      staleStripeAccountId: staleAccountId || null,
      staleStripeMode: staleMode || null,
    };
  });
}

function createRiderTransferOrPayout(stripeOrFactory) {
  return riderStripeCallable(async (data, context) => {
    const stripe = stripeFrom(stripeOrFactory);
    const mode = stripeClientMode(stripe);
    const riderId = text(data && data.riderId);
    const amount = Number((data && data.amount) || 0);
    const requestId = text(data && data.requestId);
    const deliveryId = text(data && (data.deliveryId || data.bookingId || data.orderId));
    await assertActor(context, riderId, {adminOnly: true});
    if (!riderId || !requestId || !Number.isFinite(amount) || amount <= 0) {
      throw new functions.https.HttpsError("invalid-argument", "Rider, amount and a stable payout request are required.");
    }
    payoutAllocation.minor(amount);
    if (hasRawBankFields(data)) {
      throw new functions.https.HttpsError("invalid-argument", "Raw bank details are not accepted.");
    }
    const db = getFirestore();
    const {profile} = await loadRider(riderId);
    const readiness = await computeRiderPayoutReadiness(riderId);
    if (!readiness.ready) {
      throw new functions.https.HttpsError("failed-precondition", `Rider payout setup is not ready: ${readiness.status}.`);
    }
    const stripeAccountId = text(profile.stripeConnectAccountId || profile.stripeAccountId);
    const walletRef = db.collection("riderEarnings").doc(riderId);
    const requestRef = requestId ? db.collection("payoutRequests").doc(requestId) : db.collection("payoutRequests").doc();
    const reservation = await db.runTransaction(async (transaction) => {
      const wallet = await transaction.get(walletRef);
      const existingRequest = await transaction.get(requestRef);
      const walletData = wallet.data() || {};
      const requestData = existingRequest.exists ? existingRequest.data() || {} : {};
      if (existingRequest.exists && (text(requestData.riderId) !== riderId || payoutAllocation.minor(requestData.amount) !== payoutAllocation.minor(amount))) {
        throw new functions.https.HttpsError("failed-precondition", "Payout request identity or amount changed.");
      }
      const payoutInput = {
        ...requestData,
        ...data,
        amount,
        riderGrossShare: requestData.riderGrossShare || data.riderGrossShare || amount,
      };
      let breakdown = resolveRiderPayoutBreakdown(payoutInput);
      const existingStatus = text(requestData.status || requestData.payoutStatus).toLowerCase();
      const existingTransferId = text(requestData.stripeTransferId);
      if (existingRequest.exists &&
        existingTransferId &&
        ["processing", "scheduled", "paid"].includes(existingStatus)) {
        return {
          id: existingTransferId,
          idempotent: true,
          metadata: {
            stripeFeeDeductedFromRider: String(requestData.stripeFeeDeductedFromRider || breakdown.stripeFeeDeductedFromRider),
            riderNetPayout: String(requestData.riderNetPayout || breakdown.riderNetPayout),
          },
        };
      }
      if (existingRequest.exists && existingTransferId && existingStatus === "failed") {
        throw new functions.https.HttpsError("failed-precondition", "This payout transfer failed and must be retried with a new request.");
      }
      const available = Number(walletData.availableBalance || 0);
      const pendingDelta = requestData.fundsReserved === true ? 0 : breakdown.riderGrossShare;
      if (pendingDelta > 0 && available < breakdown.riderGrossShare) {
        throw new functions.https.HttpsError("failed-precondition", "Withdrawal exceeds available balance.");
      }
      const deliveryDocId = deliveryId || text(requestData.deliveryId || requestData.bookingId || requestData.orderId);
      const deliveryRefs = deliveryDocId ? [
        db.collection("deliveryRequests").doc(deliveryDocId),
        db.collection("bookings").doc(deliveryDocId),
        db.collection("deliveries").doc(deliveryDocId),
        db.collection("deliveryRecords").doc(deliveryDocId),
      ] : [];
      const deliveryDocs = [];
      for (const ref of deliveryRefs) {
        deliveryDocs.push(await transaction.get(ref));
      }
      const plan = await payoutAllocation.readAllocationPlan(transaction, db, riderId, requestRef.id, payoutAllocation.minor(breakdown.riderGrossShare));
      const allocations = plan.allocations;
      const tipPence = allocations.filter((row) => row.type === "tip").reduce((sum, row) => sum + row.amountPence, 0);
      const feePence = Math.min(payoutAllocation.minor(breakdown.estimatedStripeFees), payoutAllocation.minor(breakdown.riderGrossShare) - tipPence);
      breakdown = {...breakdown, stripeFeeDeductedFromRider: feePence / 100,
        riderNetPayout: (payoutAllocation.minor(breakdown.riderGrossShare) - feePence) / 100, tipAmountPence: tipPence};
      let remainingFee = feePence;
      for (const allocation of allocations) {
        allocation.processorFeePence = allocation.type === "tip" ? 0 : Math.min(remainingFee, allocation.amountPence);
        allocation.netAmountPence = allocation.amountPence - allocation.processorFeePence;
        remainingFee -= allocation.processorFeePence;
      }
      if (breakdown.riderNetPayout <= 0) {
        transaction.set(requestRef, {
          ...breakdown,
          requestId: requestRef.id,
          riderId,
          riderEmail: profile.email || null,
          deliveryId: deliveryId || requestData.deliveryId || requestData.bookingId || null,
          amount: breakdown.riderGrossShare,
          status: "admin_review_required",
          payoutStatus: "blocked_admin_review",
          payoutBlockReason: "estimated_stripe_fees_exceed_rider_share",
          stripeAccountId,
          feePayer: "rider",
          payoutFeePayer: "rider",
          paymentProvider: "stripe_connect_express",
          updatedAt: FieldValue.serverTimestamp(),
          processedBy: context.auth.uid,
        }, {merge: true});
        return {
          blocked: true,
          status: "admin_review_required",
          reason: "estimated_stripe_fees_exceed_rider_share",
          ...breakdown,
        };
      }
      for (const recovery of plan.recoveries) {
        payoutAllocation.reserveAllocations(transaction, db, riderId, `recovery_${recovery.id}`, recovery.allocations, "paid", "tip_recovery");
        transaction.set(recovery.ref, {unallocatedPence: 0, earningAllocations: recovery.allocations, allocatedAt: FieldValue.serverTimestamp()}, {merge: true});
      }
      payoutAllocation.reserveAllocations(transaction, db, riderId, requestRef.id, allocations);
      const reservationVersion = Number(requestData.reservationVersion || 0) + (pendingDelta > 0 ? 1 : 0);
      if (pendingDelta > 0) {
payoutAllocation.writePayoutLedger(transaction, db, {requestId: requestRef.id, version: reservationVersion, riderId,
        amountPence: payoutAllocation.minor(pendingDelta), phase: "reserved", balanceBeforePence: payoutAllocation.minor(available), balanceAfterPence: payoutAllocation.minor(available - pendingDelta)});
}
      const payoutPatch = {
        reservationVersion,
        allocationVersion: 1, earningAllocations: allocations,
        totalCustomerPaid: breakdown.totalCustomerPaid,
        circumPlatformCommission: breakdown.circumPlatformCommission,
        riderGrossShare: breakdown.riderGrossShare,
        stripeFeeDeductedFromRider: breakdown.stripeFeeDeductedFromRider,
        estimatedStripeFees: breakdown.estimatedStripeFees,
        riderNetPayout: breakdown.riderNetPayout,
        stripeAccountId,
        stripeMode: mode,
        payoutStatus: "reserved",
        payoutReservedAt: FieldValue.serverTimestamp(),
        payoutFeePolicy: breakdown.payoutFeePolicy,
        payoutFeePayer: "rider",
        feePayer: "rider",
        paymentProvider: "stripe_connect_express",
        updatedAt: FieldValue.serverTimestamp(),
      };
      transaction.set(requestRef, {
        requestId: requestRef.id,
        riderId,
        riderEmail: profile.email || null,
        deliveryId: deliveryDocId || requestData.deliveryId || requestData.bookingId || null,
        amount: breakdown.riderGrossShare,
        status: "reserved",
        fundsReserved: true,
        ...payoutPatch,
        createdAt: existingRequest.exists ? requestData.createdAt || FieldValue.serverTimestamp() : FieldValue.serverTimestamp(),
        reservedAt: FieldValue.serverTimestamp(),
        processedBy: context.auth.uid,
      }, {merge: true});
      deliveryDocs.forEach((doc) => {
        if (!doc.exists) return;
        transaction.set(doc.ref, {
          ...payoutPatch,
          payoutRequestId: requestRef.id,
        }, {merge: true});
      });
      transaction.set(walletRef, {
        availableBalance: FieldValue.increment(-pendingDelta),
        pendingWithdrawal: FieldValue.increment(pendingDelta),
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
      return {
        requestId: requestRef.id,
        riderId,
        deliveryId: deliveryDocId || null,
        stripeAccountId,
        breakdown,
        reservationVersion,
        deliveryRefs: deliveryDocs.filter((doc) => doc.exists).map((doc) => doc.ref.path),
      };
    });
    if (reservation.blocked) {
      await db.collection("riderPayoutAudit").add({
        riderId,
        payoutRequestId: requestRef.id,
        action: "stripe_transfer_blocked",
        reason: reservation.reason,
        amount,
        riderGrossShare: reservation.riderGrossShare,
        stripeFeeDeductedFromRider: reservation.stripeFeeDeductedFromRider,
        riderNetPayout: reservation.riderNetPayout,
        feePayer: "rider",
        actorId: context.auth.uid,
        createdAt: FieldValue.serverTimestamp(),
      });
      throw new functions.https.HttpsError(
          "failed-precondition",
          "Stripe fees exceed the rider share. Admin review is required.",
      );
    }
    if (reservation.idempotent) {
      return {
        requestId: requestRef.id,
        stripeTransferId: reservation.id,
        status: "processing",
        idempotent: true,
        feePayer: "rider",
        stripeFeeDeductedFromRider: reservation.metadata && reservation.metadata.stripeFeeDeductedFromRider,
        riderNetPayout: reservation.metadata && reservation.metadata.riderNetPayout,
        feeChecklist: "Stripe Dashboard -> Connect settings -> set payout/fee payer to connected account/rider where available.",
      };
    }
    let transfer;
    await db.runTransaction(async (transaction) => {
      const request = await transaction.get(requestRef);
      if (request.data().tipRefundBlocked === true) throw new functions.https.HttpsError("failed-precondition", "This payout was adjusted by a tip refund. Please create a new request.");
      const priorAttempt = request.data().transferAttemptStartedAt;
      if (priorAttempt && Date.now() - priorAttempt.toMillis() > 23 * 60 * 60 * 1000 && !request.data().stripeTransferId) {
        throw new functions.https.HttpsError("failed-precondition", "This transfer needs provider reconciliation before retry.");
      }
      transaction.set(requestRef, {transferDispatching: true, transferAttemptStartedAt: priorAttempt || FieldValue.serverTimestamp()}, {merge: true});
    });
    try {
      transfer = await stripe.transfers.create({
        amount: Math.round(reservation.breakdown.riderNetPayout * 100),
        currency: "gbp",
        destination: reservation.stripeAccountId,
        metadata: {
          riderId,
          payoutRequestId: reservation.requestId,
          deliveryId: reservation.deliveryId || "",
          payoutFeePayer: "rider",
          riderGrossShare: String(reservation.breakdown.riderGrossShare),
          stripeFeeDeductedFromRider: String(reservation.breakdown.stripeFeeDeductedFromRider),
          riderNetPayout: String(reservation.breakdown.riderNetPayout),
        },
      }, {
        idempotencyKey: stripeTransferIdempotencyKey(reservation.requestId),
      });
    } catch (error) {
      if (!error || error.type !== "StripeInvalidRequestError") {
        throw new functions.https.HttpsError("unavailable", "Transfer confirmation is pending. Retry this same payout request.");
      }
      await db.runTransaction(async (transaction) => {
        const requestDoc = await transaction.get(requestRef);
        const requestData = requestDoc.data() || {};
        const status = text(requestData.status || requestData.payoutStatus).toLowerCase();
        if (status !== "reserved") return;
        const allocations = await payoutAllocation.readRequestAllocations(transaction, db, requestRef.id);
        const wallet = await transaction.get(walletRef);
        payoutAllocation.writePayoutLedger(transaction, db, {requestId: requestRef.id, version: reservation.reservationVersion, riderId, amountPence: payoutAllocation.minor(reservation.breakdown.riderGrossShare), phase: "released", balanceBeforePence: payoutAllocation.minor(wallet.data().availableBalance || 0), balanceAfterPence: payoutAllocation.minor((wallet.data().availableBalance || 0) + reservation.breakdown.riderGrossShare)});
        payoutAllocation.setAllocationState(transaction, allocations, "released");
        transaction.set(requestRef, {
          status: "failed",
          payoutStatus: "failed",
          payoutFailureStage: "stripe_transfer",
          transferDispatching: false,
          failureReason: error && (error.message || error.code) || "Stripe transfer failed.",
          fundsReserved: false,
          failedAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
        transaction.set(walletRef, {
          availableBalance: FieldValue.increment(reservation.breakdown.riderGrossShare),
          pendingWithdrawal: FieldValue.increment(-reservation.breakdown.riderGrossShare),
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
      });
      throw new functions.https.HttpsError("internal", "Stripe transfer failed. Funds were restored for retry.");
    }
    await db.runTransaction(async (transaction) => {
      const requestDoc = await transaction.get(requestRef);
      const requestData = requestDoc.data() || {};
      const allocationDocs = await payoutAllocation.readRequestAllocations(transaction, db, requestRef.id);
      const existingTransferId = text(requestData.stripeTransferId);
      if (existingTransferId && existingTransferId !== transfer.id) {
        throw new Error("Payout transfer identity mismatch");
      }
      if (existingTransferId && ["paid", "failed", "cancelled", "canceled"].includes(requestData.status)) return;
      const payoutPatch = {
        payoutStatus: "processing",
        status: "processing",
        stripeTransferId: transfer.id,
        transferDispatching: false,
        destinationPaymentId: typeof transfer.destination_payment === "string" ? transfer.destination_payment : transfer.destination_payment && transfer.destination_payment.id || null,
        payoutCreatedAt: FieldValue.serverTimestamp(),
        processedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      };
      for (const doc of allocationDocs) transaction.set(doc.ref, {stripeTransferId: transfer.id}, {merge: true});
      transaction.set(requestRef, payoutPatch, {merge: true});
      reservation.deliveryRefs.forEach((path) => {
        transaction.set(db.doc(path), {
          ...payoutPatch,
          payoutRequestId: reservation.requestId,
        }, {merge: true});
      });
      transaction.set(db.collection("riderWalletTransactions").doc(`stripe_transfer_${reservation.requestId}`), {
        id: `stripe_transfer_${reservation.requestId}`,
        riderId,
        deliveryId: reservation.deliveryId || null,
        withdrawalRequestId: reservation.requestId,
        type: "payout_completed",
        amount: -reservation.breakdown.riderGrossShare,
        grossDeliveryEarning: reservation.breakdown.riderGrossShare,
        stripePaymentFee: reservation.breakdown.stripeFeeDeductedFromRider,
        netPayout: reservation.breakdown.riderNetPayout,
        totalCustomerPaid: reservation.breakdown.totalCustomerPaid,
        circumPlatformCommission: reservation.breakdown.circumPlatformCommission,
        status: "processing",
        stripeTransferId: transfer.id,
        feePayer: "rider",
        notes: "Stripe Connect Express rider payout transfer.",
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
    });
    if (!transfer.idempotent) {
      await db.collection("riderPayoutAudit").add({
        riderId,
        payoutRequestId: requestRef.id,
        action: "stripe_transfer_created",
        stripeTransferId: transfer.id,
        stripeMode: mode,
        amount,
        feePayer: "rider",
        actorId: context.auth.uid,
        createdAt: FieldValue.serverTimestamp(),
      });
    }
    return {
      requestId: requestRef.id,
      stripeTransferId: transfer.id,
      status: "processing",
      feePayer: "rider",
      stripeFeeDeductedFromRider: transfer.metadata && transfer.metadata.stripeFeeDeductedFromRider,
      riderNetPayout: transfer.metadata && transfer.metadata.riderNetPayout,
      feeChecklist: "Stripe Dashboard -> Connect settings -> set payout/fee payer to connected account/rider where available.",
    };
  });
}

function requestRiderWithdrawal() {
  return riderCallable(async (data, context) => {
    const riderId = text(context.auth && context.auth.uid);
    await assertActor(context, riderId);
    if (hasRawBankFields(data)) {
      throw new functions.https.HttpsError(
          "invalid-argument",
          "Bank details must be managed through Stripe Connect.",
      );
    }
    const amount = roundMoney(data && data.amount);
    if (amount <= 0) {
      throw new functions.https.HttpsError(
          "invalid-argument",
          "Enter a valid withdrawal amount.",
      );
    }
    const db = getFirestore();
    const {profile} = await loadRider(riderId);
    const readiness = await computeRiderPayoutReadiness(riderId);
    const stripeAccountId = text(
        profile.stripeConnectAccountId || profile.stripeAccountId,
    );
    const requestRef = db.collection("payoutRequests").doc(`active_${riderId}`);
    const walletRef = db.collection("riderEarnings").doc(riderId);
    await db.runTransaction(async (transaction) => {
      const [requestDoc, walletDoc] = await Promise.all([
        transaction.get(requestRef),
        transaction.get(walletRef),
      ]);
      const existing = requestDoc.data() || {};
      const existingStatus = text(
          existing.status || existing.payoutStatus,
      ).toLowerCase();
      const wallet = walletDoc.data() || {};
      const available = roundMoney(
          wallet.availableBalance || wallet.availableEarnings || wallet.accountBalance,
      );
      const minimum = roundMoney(profile.minimumWithdrawalAmount || 1);
      const failure = riderWithdrawalFailure({
        amount,
        available,
        minimum,
        existingStatus,
        approvedRider: readiness.checks.riderApproved === true,
        stripeReady: readiness.ready === true,
        payoutPaused: profile.payoutPaused === true,
      });
      const failures = {
        approval_required: ["failed-precondition", "Rider approval is required before withdrawal."],
        stripe_not_ready: ["failed-precondition", "Complete Stripe payout setup before requesting withdrawal."],
        duplicate_pending: ["already-exists", "A withdrawal is already pending."],
        invalid_amount: ["invalid-argument", "Enter a valid withdrawal amount."],
        below_minimum: ["failed-precondition", `Minimum withdrawal is £${minimum.toFixed(2)}.`],
        exceeds_available: ["failed-precondition", "Withdrawal exceeds available cash earnings."],
      };
      if (failure) {
        const [code, message] = failures[failure];
        throw new functions.https.HttpsError(code, message);
      }
      transaction.set(requestRef, {
        requestId: requestRef.id,
        riderId,
        riderEmail: profile.email || null,
        amount,
        status: "requested",
        payoutStatus: "requested",
        paymentProvider: "stripe_connect_express",
        stripeAccountId,
        payoutFeePayer: "rider",
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: false});
    });
    await db.collection("riderPayoutAudit").add({
      riderId,
      payoutRequestId: requestRef.id,
      action: "withdrawal_requested",
      amount,
      actorId: riderId,
      createdAt: FieldValue.serverTimestamp(),
    });
    return {
      requestId: requestRef.id,
      amount,
      status: "requested",
    };
  });
}

function cancelRiderWithdrawal() {
  return riderCallable(async (data, context) => {
    const riderId = text(context.auth && context.auth.uid);
    await assertActor(context, riderId);
    const requestId = text(data && data.requestId) || `active_${riderId}`;
    const db = getFirestore();
    const requestRef = db.collection("payoutRequests").doc(requestId);
    await db.runTransaction(async (transaction) => {
      const requestDoc = await transaction.get(requestRef);
      if (!requestDoc.exists) {
        throw new functions.https.HttpsError(
            "not-found",
            "No active withdrawal request was found.",
        );
      }
      const request = requestDoc.data() || {};
      if (text(request.riderId) !== riderId) {
        throw new functions.https.HttpsError(
            "permission-denied",
            "You can only cancel your own withdrawal request.",
        );
      }
      const status = text(request.status || request.payoutStatus).toLowerCase();
      if (!["requested", "pending"].includes(status)) {
        throw new functions.https.HttpsError(
            "failed-precondition",
            "This withdrawal can no longer be cancelled.",
        );
      }
      transaction.set(requestRef, {
        status: "cancelled",
        payoutStatus: "cancelled",
        cancelledAt: FieldValue.serverTimestamp(),
        cancelledBy: riderId,
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    });
    await db.collection("riderPayoutAudit").add({
      riderId,
      payoutRequestId: requestId,
      action: "withdrawal_cancelled",
      actorId: riderId,
      createdAt: FieldValue.serverTimestamp(),
    });
    return {
      requestId,
      status: "cancelled",
    };
  });
}

function adminReviewRiderWithdrawal() {
  return riderCallable(async (data, context) => {
    const riderId = text(data && data.riderId);
    const requestId = text(data && data.requestId);
    const action = text(data && data.action).toLowerCase();
    const reason = text(data && data.reason);
    await assertActor(context, riderId, {adminOnly: true});
    if (!riderId || !requestId || action !== "rejected") {
      throw new functions.https.HttpsError(
          "invalid-argument",
          "Rider, payout request and a supported review action are required.",
      );
    }
    if (!reason) {
      throw new functions.https.HttpsError(
          "invalid-argument",
          "A payout review reason is required.",
      );
    }
    const db = getFirestore();
    const requestRef = db.collection("payoutRequests").doc(requestId);
    const result = await db.runTransaction(async (transaction) => {
      const requestDoc = await transaction.get(requestRef);
      if (!requestDoc.exists) {
        throw new functions.https.HttpsError(
            "not-found",
            "Payout request was not found.",
        );
      }
      const request = requestDoc.data() || {};
      if (text(request.riderId) !== riderId) {
        throw new functions.https.HttpsError(
            "permission-denied",
            "Payout request does not belong to this rider.",
        );
      }
      const status = text(request.status || request.payoutStatus).toLowerCase();
      if (status === "rejected") {
        return {requestId, status: "rejected", idempotent: true};
      }
      if (!["requested", "pending", "admin_review_required", "blocked_admin_review"].includes(status)) {
        throw new functions.https.HttpsError(
            "failed-precondition",
            "This payout request can no longer be rejected.",
        );
      }
      transaction.set(requestRef, {
        status: "rejected",
        payoutStatus: "rejected",
        reviewStatus: "rejected",
        rejectedAt: FieldValue.serverTimestamp(),
        processedAt: FieldValue.serverTimestamp(),
        processedBy: context.auth.uid,
        rejectionReason: reason,
        reviewReason: reason,
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
      return {requestId, status: "rejected", idempotent: false};
    });
    if (!result.idempotent) {
      await db.collection("riderPayoutAudit").add({
        riderId,
        payoutRequestId: requestId,
        action: "withdrawal_rejected",
        reason,
        actorId: context.auth.uid,
        createdAt: FieldValue.serverTimestamp(),
      });
    }
    return result;
  });
}

async function processStripeConnectEventOnce(db, event, handler) {
  const eventId = text(event && event.id);
  if (!eventId) {
    throw new Error("Stripe Connect webhook event id is missing.");
  }
  const eventRef = db.collection("stripeConnectWebhookEvents").doc(eventId);
  return db.runTransaction(async (transaction) => {
    const existingEvent = await transaction.get(eventRef);
    if (existingEvent.exists) {
      return {
        duplicate: true,
        eventId,
        previousStatus: existingEvent.data().status || "processed",
      };
    }
    const result = await handler(transaction);
    transaction.create(eventRef, {
      eventId,
      type: event.type,
      stripeAccountId: text(event.account),
      status: "processed",
      createdAt: FieldValue.serverTimestamp(),
      result: result || {},
    });
    return {
      duplicate: false,
      eventId,
      ...(result || {}),
    };
  });
}

function handleStripeConnectWebhook(stripeOrFactory) {
  return stripeWebhookRuntime.https.onRequest(async (req, res) => {
    const stripe = stripeFrom(stripeOrFactory);
    const signature = req.headers["stripe-signature"];
    const webhookSecret = process.env.STRIPE_WEBHOOK_SECRET;
    let event;
    try {
      if (!webhookSecret) {
        console.error("Stripe Connect webhook secret is not configured.");
        res.status(500).send("Webhook secret missing");
        return;
      }
      event = stripe.webhooks.constructEvent(req.rawBody, signature, webhookSecret);
    } catch (error) {
      console.error("Stripe Connect webhook signature failed", error.message);
      res.status(400).send("Invalid signature");
      return;
    }
    const db = getFirestore();
    try {
      const object = (event.data && event.data.object) || {};
      if (event.type === "account.updated") {
        const riderId = text(object.metadata && object.metadata.riderId);
        if (riderId) {
          await updateRiderConnectFields(riderId, connectPatch(object, {
            stripeMode: stripeClientMode(stripe),
          }));
        }
      }
      if (event.type === "external_account.updated" ||
        event.type === "account.external_account.updated") {
        const accountId = text(object.account || event.account);
        if (accountId) {
          const processed = await processStripeConnectEventOnce(db, event, async () => ({
            stripeAccountId: accountId,
            status: "account_sync_requested",
          }));
          if (!processed.duplicate) {
            const account = await stripe.accounts.retrieve(accountId);
            const riderId = await riderIdForStripeAccount(db, account);
            if (riderId) {
              await updateRiderConnectFields(riderId, connectPatch(account, {
                stripeMode: stripeClientMode(stripe),
                stripeExternalAccountUpdatedAt: FieldValue.serverTimestamp(),
              }));
              await db.collection("riderPayoutAudit").add({
                riderId,
                action: "stripe_external_account_updated",
                stripeAccountId: account.id,
                stripeMode: stripeClientMode(stripe),
                createdAt: FieldValue.serverTimestamp(),
              });
            }
          }
        }
      }
      if (event.type === "payout.created" ||
        event.type === "payout.paid" ||
        event.type === "payout.failed" ||
        event.type === "payout.canceled") {
        const accountId = text(event.account || object.account || object.destination);
        const status = event.type === "payout.paid" ? "paid" :
          event.type === "payout.created" ? "scheduled" :
          event.type === "payout.canceled" ? "canceled" :
          "failed";
        const releaseBalance = false; // A failed bank payout leaves funds in the connected account.
        const payoutRequestId = text(object.metadata && object.metadata.payoutRequestId);
        let paidSources = new Set();
        if (object.automatic === true) {
          const rows = await stripe.balanceTransactions.list({payout: object.id, limit: 100}, {stripeAccount: accountId}).autoPagingToArray({limit: 10000});
          paidSources = new Set(rows.map((row) => typeof row.source === "string" ? row.source : row.source && row.source.id).filter(Boolean));
        }
        await processStripeConnectEventOnce(db, event, async (transaction) => {
          const query = await transaction.get(db.collection("payoutRequests")
              .where("stripeAccountId", "==", accountId)
              .where("status", "in", ["processing", "pending", "requested", "scheduled"]));
          const matchedDocs = query.docs.filter((doc) => doc.id === payoutRequestId || (doc.data().destinationPaymentId && paidSources.has(doc.data().destinationPaymentId)));
          const allocationDocs = new Map();
          for (const doc of matchedDocs) allocationDocs.set(doc.id, await payoutAllocation.readRequestAllocations(transaction, db, doc.id));
          let matched = 0;
          matchedDocs.forEach((doc) => {
            const payout = doc.data() || {};
            const riderId = text(payout.riderId);
            const amount = Number(payout.amount || 0);
            const reserved = payout.fundsReserved === true;
            matched += 1;
            if (status === "paid" || releaseBalance) payoutAllocation.setAllocationState(transaction, allocationDocs.get(doc.id), status === "paid" ? "paid" : "released", object.id);
            transaction.set(doc.ref, {
              status: ["failed", "canceled"].includes(status) ? "processing" : status,
              payoutStatus: status,
              stripePayoutId: object.id,
              failureReason: object.failure_message || object.failure_code || null,
              payoutScheduledAt: status === "scheduled" ? FieldValue.serverTimestamp() : null,
              paidAt: status === "paid" ? FieldValue.serverTimestamp() : null,
              failedAt: status === "failed" ? FieldValue.serverTimestamp() : null,
              canceledAt: status === "canceled" ? FieldValue.serverTimestamp() : null,
              updatedAt: FieldValue.serverTimestamp(),
            }, {merge: true});
            if (riderId && amount > 0 && status === "paid") {
              transaction.set(db.collection("riderEarnings").doc(riderId), {
                pendingWithdrawal: reserved ? FieldValue.increment(-amount) : FieldValue.increment(0),
                totalWithdrawn: status === "paid" ? FieldValue.increment(amount) : FieldValue.increment(0),
                withdrawnEarnings: status === "paid" ? FieldValue.increment(amount) : FieldValue.increment(0),
                availableBalance: releaseBalance ? FieldValue.increment(amount) : FieldValue.increment(0),
                updatedAt: FieldValue.serverTimestamp(),
              }, {merge: true});
            }
          });
          if (!matched) transaction.set(db.collection("riderPayoutAudit").doc(`unmatched_${event.id}`), {action: "payout_lineage_review_required", stripePayoutId: object.id, accountId, status, createdAt: FieldValue.serverTimestamp()});
          return {status, matched, reviewRequired: matched === 0};
        });
      }
      if (event.type === "transfer.created" || event.type === "transfer.failed") {
        const requestId = text(object.metadata && object.metadata.payoutRequestId);
        if (requestId) {
          const requestRef = db.collection("payoutRequests").doc(requestId);
          await processStripeConnectEventOnce(db, event, async (transaction) => {
            const request = await transaction.get(requestRef);
            const requestData = request.data() || {};
            const riderId = text(requestData.riderId);
            const amount = Number(requestData.amount || object.amount / 100 || 0);
            const reserved = requestData.fundsReserved === true;
            const currentStatus = text(requestData.status || requestData.payoutStatus).toLowerCase();
            const active = ["reserved", "processing", "pending", "requested"].includes(currentStatus);
            if (!active) return {requestId, active, status: currentStatus};
            if ((requestData.stripeTransferId && requestData.stripeTransferId !== object.id) ||
                (object.currency && object.currency !== "gbp") || (object.amount && object.amount !== Math.round(requestData.riderNetPayout * 100))) throw new Error("Transfer identity mismatch");
            const allocations = await payoutAllocation.readRequestAllocations(transaction, db, requestId);
            const walletRef = db.collection("riderEarnings").doc(riderId);
            const wallet = await transaction.get(walletRef);
            if (event.type === "transfer.failed" && reserved) {
              payoutAllocation.setAllocationState(transaction, allocations, "released", object.id);
              payoutAllocation.writePayoutLedger(transaction, db, {requestId, version: requestData.reservationVersion || 0, riderId, amountPence: payoutAllocation.minor(amount), phase: "released",
                balanceBeforePence: payoutAllocation.minor(wallet.data().availableBalance || 0), balanceAfterPence: payoutAllocation.minor((wallet.data().availableBalance || 0) + amount)});
            }
            transaction.set(requestRef, {
              status: event.type === "transfer.failed" ? "failed" : "processing",
              stripeTransferId: object.id,
              transferDispatching: false,
              fundsReserved: event.type === "transfer.failed" ? false : reserved,
              destinationPaymentId: typeof object.destination_payment === "string" ? object.destination_payment : requestData.destinationPaymentId || null,
              failureReason: object.failure_message || object.failure_code || null,
              updatedAt: FieldValue.serverTimestamp(),
            }, {merge: true});
            if (event.type === "transfer.failed" && active && riderId && amount > 0) {
              transaction.set(db.collection("riderEarnings").doc(riderId), {
                availableBalance: FieldValue.increment(amount),
                pendingWithdrawal: reserved ? FieldValue.increment(-amount) : FieldValue.increment(0),
                updatedAt: FieldValue.serverTimestamp(),
              }, {merge: true});
            }
            return {requestId, active, status: event.type === "transfer.failed" ? "failed" : "processing"};
          });
        }
      }
      res.json({received: true});
    } catch (error) {
      console.error("Stripe Connect webhook handling failed", error);
      res.status(500).send("Webhook handling failed");
    }
  });
}

function scheduledRiderStripeStatusSync(stripeOrFactory) {
  return stripeSecretRuntime.pubsub.schedule("every 6 hours").onRun(async () => {
    const stripe = stripeFrom(stripeOrFactory);
    const db = getFirestore();
    const byId = new Map();
    const addDocs = (snapshot) => {
      snapshot.docs.forEach((doc) => byId.set(doc.id, doc));
    };
    addDocs(await db.collection("riderProfiles")
        .where("stripeAccountId", ">", "")
        .limit(200)
        .get());
    addDocs(await db.collection("riderProfiles")
        .where("stripeConnectAccountId", ">", "")
        .limit(200)
        .get());
    let synced = 0;
    let failed = 0;
    for (const doc of byId.values()) {
      const profile = doc.data() || {};
      const accountId = text(profile.stripeAccountId || profile.stripeConnectAccountId);
      if (!accountId) continue;
      try {
        const account = await retrieveUsableAccount(stripe, doc.id, accountId);
        if (!account) {
          failed += 1;
          continue;
        }
        await updateRiderConnectFields(doc.id, connectPatch(account, {
          stripeMode: stripeClientMode(stripe),
        }));
        synced += 1;
      } catch (error) {
        failed += 1;
        console.error("Scheduled rider Stripe sync failed", {
          riderId: doc.id,
          stripeAccountId: accountId,
          message: error && error.message,
        });
      }
    }
    return {synced, failed};
  });
}

function redactLegacyPayoutBankFields() {
  return riderCallable(async (data, context) => {
    await assertActor(context, text((data && data.riderId) || (context.auth && context.auth.uid)), {adminOnly: true});
    const limit = Math.min(Number((data && data.limit) || 50), 200);
    const snapshot = await getFirestore().collection("payoutRequests").limit(limit).get();
    const batch = getFirestore().batch();
    let redacted = 0;
    snapshot.docs.forEach((doc) => {
      const record = doc.data() || {};
      if (!hasRawBankFields(record)) return;
      redacted += 1;
      batch.set(doc.ref, {
        bankName: "REMOVED",
        sortCode: "REMOVED",
        accountNumber: "REMOVED",
        bankAccountNumber: "REMOVED",
        bankDetailsRedactedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    });
    await batch.commit();
    return {redacted};
  });
}

module.exports = {
  createStripeConnectAccountForRider,
  createStripeOnboardingLink,
  refreshStripeOnboardingLink,
  syncStripeConnectStatus,
  createStripeAccountManagementLink,
  riderPayoutReadiness,
  createRiderTransferOrPayout,
  requestRiderWithdrawal,
  cancelRiderWithdrawal,
  adminReviewRiderWithdrawal,
  resetRiderTestStripeAccount,
  handleStripeConnectWebhook,
  scheduledRiderStripeStatusSync,
  redactLegacyPayoutBankFields,
  adminBaseUrl,
  estimateStripeFee,
  resolveRiderPayoutBreakdown,
  stripeConnectAccountIdempotencyKey,
  riderWithdrawalFailure,
  stripeStatusFromAccount,
  computeRiderPayoutReadiness,
};
