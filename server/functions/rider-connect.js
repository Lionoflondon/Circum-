/* eslint-disable max-len, require-jsdoc */
const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");

const safeConfig = functions.config() || {};
const appBaseUrl = process.env.APP_BASE_URL || (safeConfig.app && safeConfig.app.base_url) || "https://circumuk.com";
const adminBaseUrl = process.env.ADMIN_BASE_URL || (safeConfig.admin && safeConfig.admin.base_url) || "https://admin.circumuk.com";
const riderStripeReturnUrl = `${appBaseUrl}/rider/stripe/return`;
const riderStripeRefreshUrl = `${appBaseUrl}/rider/stripe/refresh`;

const rawBankFields = ["bankName", "sortCode", "accountNumber", "bankAccountNumber"];
const stripeSecretRuntime = functions.runWith({secrets: ["STRIPE_SECRET_KEY"]});
const stripeWebhookRuntime = functions.runWith({secrets: ["STRIPE_SECRET_KEY", "STRIPE_WEBHOOK_SECRET"]});

function text(value) {
  return `${value || ""}`.trim();
}

function stripeFrom(stripeOrFactory) {
  return typeof stripeOrFactory === "function" ? stripeOrFactory() : stripeOrFactory;
}

function hasRawBankFields(data) {
  return rawBankFields.some((field) => {
    const value = text(data && data[field]);
    return value.length > 0 && value !== "REMOVED";
  });
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

function approved(profile) {
  const status = text(profile && (profile.approvalStatus || profile.verificationStatus || profile.onboardingStatus)).toLowerCase();
  return status === "approved" || status === "verified";
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

function connectPatch(account, extra = {}) {
  const requirements = account.requirements || {};
  const currentlyDue = requirements.currently_due || [];
  const pastDue = requirements.past_due || [];
  const payoutsEnabled = account.payouts_enabled === true;
  const chargesEnabled = account.charges_enabled === true;
  const detailsSubmitted = account.details_submitted === true;
  const onboardingComplete = detailsSubmitted && payoutsEnabled;
  return {
    stripeConnectAccountId: account.id,
    stripeAccountId: account.id,
    stripeConnectType: "express",
    stripeConnectStatus: onboardingComplete ? "payouts_enabled" : "verification_required",
    stripeDetailsSubmitted: detailsSubmitted,
    stripeChargesEnabled: chargesEnabled,
    stripePayoutsEnabled: payoutsEnabled,
    stripeOnboardingStatus: onboardingComplete ? "complete" : "incomplete",
    payoutsEnabled,
    chargesEnabled,
    onboardingComplete,
    payoutPaused: false,
    payoutFeePayer: "rider",
    stripeRequirementsDue: currentlyDue,
    stripeRequirementsPastDue: pastDue,
    stripeDisabledReason: requirements.disabled_reason || null,
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

function createStripeConnectAccountForRider(stripeOrFactory) {
  return stripeSecretRuntime.https.onCall(async (data, context) => {
    const stripe = stripeFrom(stripeOrFactory);
    const riderId = text((data && data.riderId) || (context.auth && context.auth.uid));
    await assertActor(context, riderId);
    const {profile} = await loadRider(riderId);
    if (!approved(profile)) {
      throw new functions.https.HttpsError("failed-precondition", "Admin approval is required before payout setup.");
    }
    if (text(profile.stripeConnectAccountId || profile.stripeAccountId)) {
      return {
        stripeConnectAccountId: profile.stripeConnectAccountId || profile.stripeAccountId,
        stripeAccountId: profile.stripeAccountId || profile.stripeConnectAccountId,
        stripeConnectType: "express",
        payoutFeePayer: "rider",
        alreadyExists: true,
      };
    }
    const account = await stripe.accounts.create({
      type: "express",
      country: "GB",
      email: text(profile.email || (data && data.email) || (context.auth && context.auth.token && context.auth.token.email)) || undefined,
      business_type: "individual",
      capabilities: {
        transfers: {requested: true},
      },
      metadata: {
        riderId,
        payoutFeePayer: "rider",
        platform: "circum",
      },
    });
    await updateRiderConnectFields(riderId, connectPatch(account, {
      stripeConnectStatus: "account_created",
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
      payoutFeePayer: "rider",
    };
  });
}

function createStripeOnboardingLink(stripeOrFactory) {
  return stripeSecretRuntime.https.onCall(async (data, context) => {
    const stripe = stripeFrom(stripeOrFactory);
    const riderId = text((data && data.riderId) || (context.auth && context.auth.uid));
    await assertActor(context, riderId);
    const {profile} = await loadRider(riderId);
    if (!approved(profile)) {
      throw new functions.https.HttpsError("failed-precondition", "Admin approval is required before payout setup.");
    }
    let accountId = text(profile.stripeConnectAccountId || profile.stripeAccountId);
    if (!accountId) {
      const created = await stripe.accounts.create({
        type: "express",
        country: "GB",
        email: text(profile.email || (context.auth && context.auth.token && context.auth.token.email)) || undefined,
        business_type: "individual",
        capabilities: {transfers: {requested: true}},
        metadata: {riderId, payoutFeePayer: "rider", platform: "circum"},
      });
      accountId = created.id;
      await updateRiderConnectFields(riderId, connectPatch(created, {
        stripeConnectStatus: "account_created",
      }));
    }
    const returnUrl = riderStripeReturnUrl;
    const refreshUrl = riderStripeRefreshUrl;
    const link = await stripe.accountLinks.create({
      account: accountId,
      refresh_url: refreshUrl,
      return_url: returnUrl,
      type: "account_onboarding",
    });
    await updateRiderConnectFields(riderId, {
      stripeConnectStatus: "onboarding_link_created",
      payoutFeePayer: "rider",
      lastStripeSyncAt: FieldValue.serverTimestamp(),
    });
    return {
      url: link.url,
      stripeConnectAccountId: accountId,
      stripeAccountId: accountId,
      stripeConnectType: "express",
      returnUrl,
      refreshUrl,
    };
  });
}

function refreshStripeOnboardingLink(stripe) {
  return createStripeOnboardingLink(stripe);
}

function syncStripeConnectStatus(stripeOrFactory) {
  return stripeSecretRuntime.https.onCall(async (data, context) => {
    const stripe = stripeFrom(stripeOrFactory);
    const riderId = text((data && data.riderId) || (context.auth && context.auth.uid));
    await assertActor(context, riderId);
    const {profile} = await loadRider(riderId);
    const accountId = text(profile.stripeConnectAccountId || profile.stripeAccountId);
    if (!accountId) {
      throw new functions.https.HttpsError("failed-precondition", "Stripe payout setup has not started.");
    }
    const account = await stripe.accounts.retrieve(accountId);
    const patch = connectPatch(account);
    await updateRiderConnectFields(riderId, patch);
    return {
      stripeConnectAccountId: account.id,
      stripeAccountId: account.id,
      stripeConnectType: "express",
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

function createRiderTransferOrPayout(stripeOrFactory) {
  return stripeSecretRuntime.https.onCall(async (data, context) => {
    const stripe = stripeFrom(stripeOrFactory);
    const riderId = text(data && data.riderId);
    const amount = Number((data && data.amount) || 0);
    const requestId = text(data && data.requestId);
    await assertActor(context, riderId, {adminOnly: true});
    if (!riderId || amount <= 0) {
      throw new functions.https.HttpsError("invalid-argument", "Rider and amount are required.");
    }
    if (hasRawBankFields(data)) {
      throw new functions.https.HttpsError("invalid-argument", "Raw bank details are not accepted.");
    }
    const db = getFirestore();
    const {profile} = await loadRider(riderId);
    if (!approved(profile)) {
      throw new functions.https.HttpsError("failed-precondition", "Rider must be approved first.");
    }
    const stripeAccountId = text(profile.stripeConnectAccountId || profile.stripeAccountId);
    if (!stripeAccountId || profile.onboardingComplete !== true || profile.payoutsEnabled !== true || profile.payoutPaused === true) {
      throw new functions.https.HttpsError("failed-precondition", "Rider Stripe payout setup is not ready.");
    }
    const walletRef = db.collection("riderEarnings").doc(riderId);
    const requestRef = requestId ? db.collection("payoutRequests").doc(requestId) : db.collection("payoutRequests").doc();
    const transfer = await db.runTransaction(async (transaction) => {
      const wallet = await transaction.get(walletRef);
      const existingRequest = await transaction.get(requestRef);
      const walletData = wallet.data() || {};
      const available = Number(walletData.availableBalance || 0);
      if (available < amount) {
        throw new functions.https.HttpsError("failed-precondition", "Withdrawal exceeds available balance.");
      }
      const pendingDelta = existingRequest.exists ? 0 : amount;
      const created = await stripe.transfers.create({
        amount: Math.round(amount * 100),
        currency: "gbp",
        destination: stripeAccountId,
        metadata: {
          riderId,
          payoutRequestId: requestRef.id,
          payoutFeePayer: "rider",
        },
      });
      transaction.set(requestRef, {
        requestId: requestRef.id,
        riderId,
        riderEmail: profile.email || null,
        amount,
        status: "processing",
        stripeAccountId,
        stripeTransferId: created.id,
        feePayer: "rider",
        payoutFeePayer: "rider",
        paymentProvider: "stripe_connect_express",
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
        processedAt: FieldValue.serverTimestamp(),
        processedBy: context.auth.uid,
      }, {merge: true});
      transaction.set(walletRef, {
        availableBalance: FieldValue.increment(-amount),
        pendingWithdrawal: FieldValue.increment(pendingDelta),
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
      transaction.set(db.collection("riderWalletTransactions").doc(`stripe_transfer_${requestRef.id}`), {
        id: `stripe_transfer_${requestRef.id}`,
        riderId,
        withdrawalRequestId: requestRef.id,
        type: "withdrawal",
        amount: -amount,
        status: "processing",
        stripeTransferId: created.id,
        feePayer: "rider",
        notes: "Stripe Connect Express rider payout transfer.",
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      return created;
    });
    await db.collection("riderPayoutAudit").add({
      riderId,
      payoutRequestId: requestRef.id,
      action: "stripe_transfer_created",
      stripeTransferId: transfer.id,
      amount,
      feePayer: "rider",
      actorId: context.auth.uid,
      createdAt: FieldValue.serverTimestamp(),
    });
    return {
      requestId: requestRef.id,
      stripeTransferId: transfer.id,
      status: "processing",
      feePayer: "rider",
      feeChecklist: "Stripe Dashboard -> Connect settings -> set payout/fee payer to connected account/rider where available.",
    };
  });
}

function handleStripeConnectWebhook(stripeOrFactory) {
  return stripeWebhookRuntime.https.onRequest(async (req, res) => {
    const stripe = stripeFrom(stripeOrFactory);
    const signature = req.headers["stripe-signature"];
    const webhookSecret = process.env.STRIPE_WEBHOOK_SECRET ||
      (safeConfig.stripe && safeConfig.stripe.connect_webhook_secret) ||
      (safeConfig.stripe && safeConfig.stripe.webhook_secret);
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
        if (riderId) await updateRiderConnectFields(riderId, connectPatch(object));
      }
      if (event.type === "payout.paid" || event.type === "payout.failed") {
        const accountId = text(object.destination || object.account || event.account);
        const status = event.type === "payout.paid" ? "paid" : "failed";
        const query = await db.collection("payoutRequests")
            .where("stripeAccountId", "==", accountId)
            .where("status", "in", ["processing", "pending", "requested"])
            .limit(10)
            .get();
        const batch = db.batch();
        query.docs.forEach((doc) => {
          const payout = doc.data() || {};
          const riderId = text(payout.riderId);
          const amount = Number(payout.amount || 0);
          batch.set(doc.ref, {
            status,
            stripePayoutId: object.id,
            failureReason: object.failure_message || object.failure_code || null,
            paidAt: status === "paid" ? FieldValue.serverTimestamp() : null,
            failedAt: status === "failed" ? FieldValue.serverTimestamp() : null,
            updatedAt: FieldValue.serverTimestamp(),
          }, {merge: true});
          if (riderId && amount > 0) {
            batch.set(db.collection("riderEarnings").doc(riderId), {
              pendingWithdrawal: FieldValue.increment(-amount),
              totalWithdrawn: status === "paid" ? FieldValue.increment(amount) : FieldValue.increment(0),
              withdrawnEarnings: status === "paid" ? FieldValue.increment(amount) : FieldValue.increment(0),
              availableBalance: status === "failed" ? FieldValue.increment(amount) : FieldValue.increment(0),
              updatedAt: FieldValue.serverTimestamp(),
            }, {merge: true});
          }
        });
        await batch.commit();
      }
      if (event.type === "transfer.created" || event.type === "transfer.failed") {
        const requestId = text(object.metadata && object.metadata.payoutRequestId);
        if (requestId) {
          const requestRef = db.collection("payoutRequests").doc(requestId);
          const request = await requestRef.get();
          const requestData = request.data() || {};
          const riderId = text(requestData.riderId);
          const amount = Number(requestData.amount || object.amount / 100 || 0);
          await db.collection("payoutRequests").doc(requestId).set({
            status: event.type === "transfer.failed" ? "failed" : "processing",
            stripeTransferId: object.id,
            failureReason: object.failure_message || object.failure_code || null,
            updatedAt: FieldValue.serverTimestamp(),
          }, {merge: true});
          if (event.type === "transfer.failed" && riderId && amount > 0) {
            await db.collection("riderEarnings").doc(riderId).set({
              availableBalance: FieldValue.increment(amount),
              pendingWithdrawal: FieldValue.increment(-amount),
              updatedAt: FieldValue.serverTimestamp(),
            }, {merge: true});
          }
        }
      }
      res.json({received: true});
    } catch (error) {
      console.error("Stripe Connect webhook handling failed", error);
      res.status(500).send("Webhook handling failed");
    }
  });
}

function redactLegacyPayoutBankFields() {
  return functions.https.onCall(async (data, context) => {
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
  createRiderTransferOrPayout,
  handleStripeConnectWebhook,
  redactLegacyPayoutBankFields,
  adminBaseUrl,
};
