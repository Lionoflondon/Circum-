/* eslint-disable max-len, require-jsdoc */
const {initializeApp} = require("firebase-admin/app");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {getAuth} = require("firebase-admin/auth");
const {getMessaging} = require("firebase-admin/messaging");
const functions = require("firebase-functions/v1");
const {defineSecret} = require("firebase-functions/params");
const stripeConfig = functions.config().stripe || {};
const stripeWebhookSecret = defineSecret("STRIPE_WEBHOOK_SECRET");
const stripe = require("stripe")(stripeConfig.livekey);
const stripeConnectClient = () => stripe;
const {v4: uuidv4} = require("uuid");

const sendPackage = require("./send-package");
const getAvaliableRequests = require("./get-avaliable-requests");
const acceptRideRequests = require("./accept-ride-requests");
const sendMessage = require("./send-message");
const sendRiderUpdate = require("./send-rider-update");
const healthPlus = require("./health-plus");
const iris = require("./iris");
const deliveryAdjustments = require("./delivery-adjustments");
const platformNotifications = require("./platform-notifications");
const legends = require("./legends");
const giftsPayment = require("./gifts-payment");
const communicationEngine = require("./communication-engine");
const deliveryPolicy = require("./delivery-policy");
const deliveryTracking = require("./delivery-tracking");
const ratingsTipping = require("./ratings-tipping");
const riderEarnings = require("./rider-earnings");
const stripeRefunds = require("./stripe-refunds");
const riderEarningsSummary = require("./rider-earnings-summary");
const founderRiderAccess = require("./founder-rider-access");
const healthPlusOperations = require("./health-plus-operations");
const rothLedger = require("./roth-ledger");
const businessPayments = require("./business-payments");
const riderConnect = require("./rider-connect");
const senderTrust = require("./sender-trust");
const referrals = require("./referrals");
const movementLedger = require("./movement-ledger");
const giftStoryAutomation = require("./gift-story-automation");
const riderPresence = require("./rider-presence");
const freeAddressSearch = require("./free-address-search");
const senderBooking = require("./sender-booking");
const senderFinance = require("./sender-finance");
const senderSavedAddresses = require("./sender-saved-addresses");
const deliveryCleanup = require("./delivery-cleanup");
const staleDelivery = require("./stale-delivery");
const accountClosure = require("./account-closure");
const businessAccess = require("./business-access");
const riderIrisAcknowledgement = require("./rider-iris-acknowledgement");
const adminIrisReferenceImages = require("./admin-iris-reference-images");

initializeApp();

function allowCors(req, res) {
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Headers", "Content-Type, Authorization");
  res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
  if (req.method === "OPTIONS") {
    res.status(204).send("");
    return true;
  }
  return false;
}

function asText(value) {
  return `${value || ""}`.trim();
}

function asMoney(value) {
  const number = Number(value);
  if (!Number.isFinite(number)) return null;
  return Math.round(number * 100) / 100;
}

function asPence(value) {
  const number = Number(value);
  if (!Number.isFinite(number)) return null;
  return Math.round(number);
}

function terminalPaymentStatus(status) {
  return ["succeeded", "paid", "completed", "checkout_completed"].includes(
      asText(status).toLowerCase(),
  );
}

function blockedDeliveryStatus(delivery = {}) {
  const statuses = [
    delivery.status,
    delivery.deliveryStatus,
    delivery.deliveryStage,
    delivery.flowStatus,
  ].map((status) => asText(status).toLowerCase());
  return statuses.some((status) => [
    "cancelled",
    "canceled",
    "expired",
    "completed",
    "delivered",
    "archived",
    "archived_stale",
    "failed",
  ].includes(status));
}

async function requireHttpSender(req) {
  const header = asText(req.headers.authorization || req.headers.Authorization);
  const match = header.match(/^Bearer\s+(.+)$/i);
  if (!match) {
    const error = new Error("Sender authentication is required.");
    error.status = 401;
    throw error;
  }
  const decoded = await getAuth().verifyIdToken(match[1]);
  return {
    uid: decoded.uid,
    email: decoded.email || "",
    name: decoded.name || decoded.displayName || "",
  };
}

function legacyPricingInput(body = {}, delivery = null) {
  if (delivery) {
    return {
      quoteId: delivery.quoteId,
      distanceMiles: delivery.distanceMiles ||
        delivery.pricingInputs && delivery.pricingInputs.distanceMiles ||
        delivery.pricingBreakdown && delivery.pricingBreakdown.distanceMiles,
      weightKg: delivery.weightKg ||
        delivery.parcelWeightKg ||
        delivery.parcel && delivery.parcel.weightKg ||
        delivery.pricingInputs && delivery.pricingInputs.weightKg,
      selectedSpeed: delivery.selectedSpeed ||
        delivery.selectedServiceLevel ||
        delivery.serviceLevel ||
        delivery.selectedTier,
      vanguardProtocolEnabled: delivery.vanguardProtocolEnabled === true ||
        delivery.vanguard === true,
      iris: delivery.iris || delivery.irisDeliveryEstimate || {},
    };
  }
  const pricing = body.pricingInput || body.pricingInputs || {};
  return {
    quoteId: asText(body.quoteId) || undefined,
    distanceMiles: pricing.distanceMiles,
    weightKg: pricing.weightKg,
    selectedSpeed: pricing.selectedSpeed || body.selectedSpeed,
    vanguardProtocolEnabled: pricing.vanguardProtocolEnabled === true ||
      body.vanguardProtocolEnabled === true,
    iris: pricing.iris || body.iris || {},
  };
}

function validateLegacyPricingInput(input = {}) {
  const distanceMiles = asMoney(input.distanceMiles);
  const weightKg = asMoney(input.weightKg);
  if (distanceMiles == null || distanceMiles <= 0) {
    const error = new Error("Authoritative delivery distance is unavailable.");
    error.status = 412;
    error.code = "missing-authoritative-pricing";
    throw error;
  }
  if (weightKg == null || weightKg <= 0) {
    const error = new Error("Authoritative parcel weight is unavailable.");
    error.status = 412;
    error.code = "missing-authoritative-pricing";
    throw error;
  }
  return input;
}

function sendPaymentError(res, error) {
  const status = Number(error.status || 400);
  return res.status(status).send({
    error: error.message || "Payment request failed.",
    code: error.code || "payment-request-failed",
  });
}

exports.sendPackage = sendPackage;
exports.getAvaliableRequests = getAvaliableRequests;
exports.getAvailableRequests = getAvaliableRequests;
exports.acceptRideRequests = acceptRideRequests;
exports.sendMessage = sendMessage;
exports.sendCircumMessage = communicationEngine.sendCircumMessage;
exports.markConversationRead = communicationEngine.markConversationRead;
exports.setConversationTyping = communicationEngine.setConversationTyping;
exports.sendRiderUpdate = sendRiderUpdate;
exports.createHealthPlusCheckoutSession = healthPlus.createHealthPlusCheckoutSession;
exports.updateHealthPlusPickupStatus = healthPlus.updateHealthPlusPickupStatus;
exports.analyseIris = iris.analyseIris;
exports.adjudicateIris = iris.adjudicateIris;
exports.reportLoadDiscrepancy = deliveryAdjustments.reportLoadDiscrepancy;
exports.cancelAdjustedCollection = deliveryAdjustments.cancelAdjustedCollection;
exports.createDeliveryAdjustmentPayment = deliveryAdjustments.createDeliveryAdjustmentPayment;
exports.finalizeDeliveryAdjustmentPayment = deliveryAdjustments.finalizeDeliveryAdjustmentPayment;
exports.onDeliveryCreated = platformNotifications.onDeliveryCreated;
exports.onDeliveryUpdated = platformNotifications.onDeliveryUpdated;
exports.onChatMessageCreated = platformNotifications.onChatMessageCreated;
exports.onSupportTicketCreated = platformNotifications.onSupportTicketCreated;
exports.onDisputeCreated = platformNotifications.onDisputeCreated;
exports.onRiderProfileUpdated = platformNotifications.onRiderProfileUpdated;
exports.onPayoutUpdated = platformNotifications.onPayoutUpdated;
exports.escalateUnclaimedDeliveries = platformNotifications.escalateUnclaimedDeliveries;
exports.awardLegendOnCompletion = legends.awardLegendOnCompletion;
exports.createGiftPayment = giftsPayment.createGiftPayment(stripe);
exports.finalizeGiftPayment = giftsPayment.finalizeGiftPayment(stripe);
exports.recordRiderArrival = deliveryPolicy.recordRiderArrival;
exports.reportWaitingContext = deliveryPolicy.reportWaitingContext;
exports.markRiderNoShow = deliveryPolicy.markRiderNoShow;
exports.cancelDelivery = deliveryPolicy.requestSenderCancellation;
exports.updateDeliveryTrackingStatus = deliveryTracking.updateDeliveryTrackingStatus;
exports.updateDeliveryLiveLocation = deliveryTracking.updateDeliveryLiveLocation;
exports.submitDeliveryRating = ratingsTipping.submitDeliveryRating;
exports.submitDeliveryTip = ratingsTipping.submitDeliveryTip(stripe);

exports.getRiderEarningsSummary = riderEarningsSummary.getRiderEarningsSummary();
exports.setFounderRiderAccess = founderRiderAccess.setFounderRiderAccess();
exports.startAdminConversation = communicationEngine.startAdminConversation;
exports.getOrCreateSupportConversation = communicationEngine.getOrCreateSupportConversation;
exports.updateSupportConversationStatus = communicationEngine.updateSupportConversationStatus;
exports.reportCircumMessage = communicationEngine.reportCircumMessage;
exports.sendCircumAnnouncement = communicationEngine.sendCircumAnnouncement;
exports.onHealthPlusPickupOperationalWrite = healthPlusOperations.onHealthPlusPickupOperationalWrite;
exports.processHealthPlusReminders = healthPlusOperations.processHealthPlusReminders;
exports.resetHealthPlusMonthlyUsage = healthPlusOperations.resetHealthPlusMonthlyUsage;
exports.generateHealthPlusRecurringBookings = healthPlusOperations.generateHealthPlusRecurringBookings;
exports.onGiftRequestCreated = platformNotifications.onGiftRequestCreated;
exports.onGiftRequestUpdated = platformNotifications.onGiftRequestUpdated;
exports.onGiftCampaignParticipantUpdated = platformNotifications.onGiftCampaignParticipantUpdated;
exports.awardFoundingRiderOnApproval = legends.awardFoundingRiderOnApproval;
exports.awardFoundingRiderOnRiderApproval = legends.awardFoundingRiderOnRiderApproval;
exports.awardPatronOnBusinessInvoicePaid = legends.awardPatronOnBusinessInvoicePaid;
exports.grantRecognition = legends.grantRecognition;
exports.revokeRecognition = legends.revokeRecognition;
exports.issueRothCredit = rothLedger.issueRothCredit;
exports.issueRothToWallets = rothLedger.issueRothToWallets;
exports.debitRothCredit = rothLedger.debitRothCredit;
exports.redeemGiftCard = rothLedger.redeemGiftCard;
exports.setWalletFrozen = rothLedger.setWalletFrozen;
exports.createWalletTopUp = rothLedger.createWalletTopUp(stripe);
exports.applyCheckoutRoth = rothLedger.applyCheckoutRoth;
exports.initialiseSenderWallet = rothLedger.initialiseSenderWallet;
exports.getSenderWallet = rothLedger.getSenderWallet;
exports.getSenderWalletTransactions = rothLedger.getSenderWalletTransactions;
exports.completeSenderWalletOnboarding = rothLedger.completeSenderWalletOnboarding;
exports.requestSenderWalletDebit = rothLedger.requestSenderWalletDebit;
exports.requestSenderWalletRefund = rothLedger.requestSenderWalletRefund;
exports.reportRating = ratingsTipping.reportRating;
exports.confirmRiderIrisAssessment = riderIrisAcknowledgement.confirmRiderIrisAssessment;
exports.getIrisReferenceImage = adminIrisReferenceImages.getIrisReferenceImage;
exports.finalizeIrisReferenceImage = adminIrisReferenceImages.finalizeIrisReferenceImage;
exports.deleteIrisReferenceImage = adminIrisReferenceImages.deleteIrisReferenceImage;
exports.closeCircumAccount = accountClosure.closeAccount;
exports.createBusinessRothCheckout = businessPayments.createBusinessRothCheckout(stripe);
exports.createBusinessInvoiceCheckout = businessPayments.createBusinessInvoiceCheckout(stripe);
exports.createBusinessAccount = businessAccess.createBusinessAccount;
exports.lookupBusinessByCompanyCode = businessAccess.lookupBusinessByCompanyCode;
exports.requestBusinessAccess = businessAccess.requestBusinessAccess;
exports.reviewBusinessAccessRequest = businessAccess.reviewBusinessAccessRequest;
exports.createStripeConnectAccountForRider = riderConnect.createStripeConnectAccountForRider(stripeConnectClient);
exports.createStripeOnboardingLink = riderConnect.createStripeOnboardingLink(stripeConnectClient);
exports.refreshStripeOnboardingLink = riderConnect.refreshStripeOnboardingLink(stripeConnectClient);
exports.syncStripeConnectStatus = riderConnect.syncStripeConnectStatus(stripeConnectClient);
exports.createRiderTransferOrPayout = riderConnect.createRiderTransferOrPayout(stripeConnectClient);
exports.cancelRiderWithdrawal = riderConnect.cancelRiderWithdrawal();
exports.resetRiderTestStripeAccount = riderConnect.resetRiderTestStripeAccount();
exports.handleStripeConnectWebhook = riderConnect.handleStripeConnectWebhook(stripeConnectClient);
exports.scheduledRiderStripeStatusSync = riderConnect.scheduledRiderStripeStatusSync(stripeConnectClient);
exports.redactLegacyPayoutBankFields = riderConnect.redactLegacyPayoutBankFields();
exports.syncSenderTrustBaseline = senderTrust.syncSenderTrustBaseline;
exports.ensureReferralCode = referrals.ensureReferralCode;
exports.attachReferralCode = referrals.attachReferralCode;
exports.activateReferral = referrals.activateReferral;
exports.activateReferralOnDeliveryCompleted = referrals.activateReferralOnDeliveryCompleted;
exports.activateReferralOnGiftCompleted = referrals.activateReferralOnGiftCompleted;
exports.activateReferralOnHealthPlusCompleted = referrals.activateReferralOnHealthPlusCompleted;
exports.onGiftMovementWrite = movementLedger.onGiftMovementWrite;
exports.onHealthMovementWrite = movementLedger.onHealthMovementWrite;
exports.onHealthPaymentMovementWrite = movementLedger.onHealthPaymentMovementWrite;
exports.onGiftDeliveryCompleted = giftStoryAutomation.onGiftDeliveryCompleted;
exports.resolveGiftStoryAccess = giftStoryAutomation.resolveGiftStoryAccess;
exports.recordGiftStoryEvent = giftStoryAutomation.recordGiftStoryEvent;
exports.updateGiftStoryPrivacy = giftStoryAutomation.updateGiftStoryPrivacy;
exports.retryGiftStoryAutomation = giftStoryAutomation.retryGiftStoryAutomation;
exports.manageGiftStoryAccess = giftStoryAutomation.manageGiftStoryAccess;
exports.createGiftStoryVideoUpload = giftStoryAutomation.createGiftStoryVideoUpload;
exports.finalizeGiftStoryVideoUpload = giftStoryAutomation.finalizeGiftStoryVideoUpload;
exports.getGiftStoryVideoDownload = giftStoryAutomation.getGiftStoryVideoDownload;
exports.giftStoryLanding = giftStoryAutomation.giftStoryLanding;
exports.submitGiftStoryThankYou = giftStoryAutomation.submitGiftStoryThankYou;
exports.acknowledgeGiftStory = giftStoryAutomation.acknowledgeGiftStory;
exports.saveGiftStoryToVault = giftStoryAutomation.saveGiftStoryToVault;
exports.getGiftStoryActionState = giftStoryAutomation.getGiftStoryActionState;
exports.onStoryNotificationWrite = giftStoryAutomation.onStoryNotificationWrite;
exports.cleanupExpiredGiftStories = giftStoryAutomation.cleanupExpiredGiftStories;
exports.requestSenderCancellation = deliveryPolicy.requestSenderCancellation;
exports.previewSenderCancellation = deliveryPolicy.previewSenderCancellation;
exports.recordArrivalZoneCheck = deliveryPolicy.recordArrivalZoneCheck;
exports.recordCustomerArrivalResponse = deliveryPolicy.recordCustomerArrivalResponse;
exports.goOnline = riderPresence.goOnline;
exports.goOffline = riderPresence.goOffline;
exports.updateRiderPresence = riderPresence.updateRiderPresence;
exports.onDeliveryPresenceWrite = riderPresence.onDeliveryPresenceWrite;
exports.onRiderRecordAvailabilityWrite = riderPresence.onRiderRecordAvailabilityWrite;
exports.onRiderProfileAvailabilityWrite = riderPresence.onRiderProfileAvailabilityWrite;
exports.markStaleRiderPresenceOffline = riderPresence.markStaleRiderPresenceOffline;
exports.searchFreeUkAddresses = freeAddressSearch.searchFreeUkAddresses;
exports.getSenderRothBalance = senderBooking.getSenderRothBalance;
exports.createSenderBookingQuote = senderBooking.createSenderBookingQuote;
exports.createSenderPaymentSession = senderBooking.createSenderPaymentSession(stripe);
exports.createSenderPaidDelivery = senderBooking.createSenderPaidDelivery(stripe);
exports.saveSenderDraft = senderBooking.saveSenderDraft;
exports.loadSenderDraft = senderBooking.loadSenderDraft;
exports.deleteSenderDraft = senderBooking.deleteSenderDraft;
exports.cleanupExpiredSenderDrafts = senderBooking.cleanupExpiredSenderDrafts;
exports.listSenderPaymentMethods = senderFinance.listSenderPaymentMethods(stripe);
exports.createSenderSetupIntent = senderFinance.createSenderSetupIntent(stripe);
exports.detachSenderPaymentMethod = senderFinance.detachSenderPaymentMethod(stripe);
exports.setDefaultSenderPaymentMethod = senderFinance.setDefaultSenderPaymentMethod(stripe);
exports.saveSenderCheckoutPreference = senderFinance.saveSenderCheckoutPreference;
exports.saveSenderSavedAddress = senderSavedAddresses.saveSenderSavedAddress;
exports.deleteSenderSavedAddress = senderSavedAddresses.deleteSenderSavedAddress;
exports.archiveExpiredDeliveries = deliveryCleanup.archiveExpiredDeliveries;
exports.resolveStaleDeliveryLock = staleDelivery.resolveStaleDeliveryLock;
exports.reconcileStaleDeliveryLocks = staleDelivery.reconcileStaleDeliveryLocks;

const generateResponse = function(intent) {
  // Generate a response based on the intent's status
  switch (intent.status) {
    case "requires_action":
      // Card requires authentication
      return {
        clientSecret: intent.client_secret,
        requiresAction: true,
        status: intent.status,
      };
    case "requires_payment_method":
      // Card was not properly authenticated, suggest a new payment method
      return {
        // error: "Your card was denied, please provide a new payment method",
        clientSecret: intent.client_secret,
        status: intent.status,
      };
    case "succeeded":
      // Payment is complete, authentication not required
      // To cancel the payment after capture you will need to issue a Refund (https://stripe.com/docs/api/refunds).
      console.log("💰 Payment received!");
      console.log(intent.status);
      return {clientSecret: intent.client_secret, status: intent.status};
  }
  return {
    error: "Failed",
  };
};


const createPaymentIntentHandler = async (req, res) => {
  if (allowCors(req, res)) return;
  const {
    amount,
    currency,
    pushToken,
    name,
    email,
    deliveryId,
    saveCard,
    paymentRequestId,
  } = req.body;

  try {
    const sender = await requireHttpSender(req);
    const db = getFirestore();
    const requestedCurrency = asText(currency || "gbp").toLowerCase();
    if (requestedCurrency !== "gbp") {
      const error = new Error("Circum delivery payments are charged in GBP.");
      error.status = 400;
      error.code = "unsupported-currency";
      throw error;
    }

    const submittedAmountPence = asPence(amount);
    if (submittedAmountPence == null || submittedAmountPence <= 0) {
      const error = new Error("A valid displayed payment amount is required.");
      error.status = 400;
      error.code = "invalid-client-amount";
      throw error;
    }

    const deliveryRef = asText(deliveryId) ?
      db.collection("deliveryRequests").doc(asText(deliveryId)) :
      null;
    const deliverySnap = deliveryRef ? await deliveryRef.get() : null;
    const delivery = deliverySnap && deliverySnap.exists ? deliverySnap.data() : null;
    if (delivery) {
      const owner = asText(delivery.senderId || delivery.userId);
      if (owner !== sender.uid) {
        const error = new Error("Delivery payment is not available for this Sender.");
        error.status = 403;
        error.code = "permission-denied";
        throw error;
      }
      if (blockedDeliveryStatus(delivery)) {
        const error = new Error("This delivery can no longer be paid.");
        error.status = 412;
        error.code = "delivery-not-payable";
        throw error;
      }
      if (terminalPaymentStatus(delivery.paymentStatus || delivery.stripePaymentStatus)) {
        const error = new Error("This delivery has already been paid.");
        error.status = 409;
        error.code = "already-paid";
        throw error;
      }
    }

    const pricingInput = legacyPricingInput(req.body, delivery);
    const quote = delivery && asMoney(delivery.price || delivery.paidAmount) != null ?
      {
        quoteId: asText(delivery.quoteId) || `legacy_delivery_${deliverySnap.id}`,
        total: asMoney(delivery.price || delivery.paidAmount),
        finalAmount: asMoney(delivery.price || delivery.paidAmount),
        amountDue: asMoney(delivery.price || delivery.paidAmount),
        currency: "GBP",
        pricingSource: "stored_delivery_price",
        lineItems: delivery.pricingBreakdown && delivery.pricingBreakdown.lineItems ||
          delivery.pricingBreakdown && delivery.pricingBreakdown.items ||
          [],
      } :
      senderBooking._private.quotePayload(validateLegacyPricingInput(pricingInput), sender.uid);
    const authoritativeAmountPence = asPence(Number(quote.total) * 100);
    if (authoritativeAmountPence == null || authoritativeAmountPence <= 0) {
      const error = new Error("Authoritative delivery pricing is unavailable.");
      error.status = 412;
      error.code = "missing-authoritative-pricing";
      throw error;
    }

    const idempotencyKey = asText(paymentRequestId) ||
      asText(deliveryId) ||
      `${sender.uid}_${quote.quoteId}`;
    const sessionRef = db.collection("legacyCorePaymentSessions")
        .doc(`core_${idempotencyKey}`);
    const existingSession = await sessionRef.get();
    if (existingSession.exists) {
      const existing = existingSession.data() || {};
      if (existing.clientSecret && existing.paymentIntentId) {
        return res.send({
          clientSecret: existing.clientSecret,
          status: existing.status,
          paymentIntentId: existing.paymentIntentId,
          customerId: existing.customerId,
          ephemeralKey: existing.ephemeralKey,
          amount: existing.authoritativeAmountPence,
          currency: "gbp",
          idempotent: true,
          authoritativePricing: existing.authoritativePricing,
        });
      }
    }

    let customerId;

    const userRef = await db.collection("users").doc(sender.uid).get();

    if (userRef.exists) {
      const userData = userRef.data();
      customerId = userData.stripeCustomerId || userData.customerId || undefined;
    }

    const params = {
      amount: authoritativeAmountPence,
      currency: "gbp",
      metadata: {
        name: name || sender.name,
        email: email || sender.email,
        pushToken: pushToken,
        userId: sender.uid,
        deliveryId: deliveryId || "",
        paymentRequestId: idempotencyKey,
        submittedAmountPence: `${submittedAmountPence}`,
        authoritativeAmountPence: `${authoritativeAmountPence}`,
        pricingSource: quote.pricingSource || "sender_backend_quote_v1",
      },
      payment_method_types: ["card"],
      setup_future_usage: saveCard ? "off_session" : undefined,
    };

    // Set customerId if it exists
    if (customerId && saveCard == true) {
      params.customer = customerId;
    }

    // create customerId if it doesnt exist
    if (!customerId) {
      const customer = await stripe.customers.create({
        name: name || sender.name,
        email: email || sender.email,
      });
        // phone: phone,

      customerId = customer.id;

      if (saveCard == true) {
        params.customer = customerId;
      }

      await db.collection("users").doc(sender.uid).set({
        customerId: customer.id,
        stripeCustomerId: customer.id,
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    }

    const ephemeralKey = await stripe.ephemeralKeys.create(
        {customer: customerId},
        {apiVersion: "2020-08-27"},
    );


    const intent = await stripe.paymentIntents.create(params, {
      idempotencyKey: `core_delivery_${idempotencyKey}`,
    });

    const paymentRecord = {
      paymentRequestId: idempotencyKey,
      paymentIntentId: intent.id,
      userId: sender.uid,
      userEmail: sender.email || email || "",
      deliveryId: deliveryId || null,
      quoteId: quote.quoteId || null,
      customerId,
      clientSecret: intent.client_secret,
      ephemeralKey: ephemeralKey.secret,
      status: intent.status,
      paymentStatus: intent.status,
      submittedAmountPence,
      authoritativeAmountPence,
      pricingDiscrepancyPence: submittedAmountPence - authoritativeAmountPence,
      currency: "GBP",
      authoritativePricing: quote,
      pricingSource: quote.pricingSource || "sender_backend_quote_v1",
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    };
    await sessionRef.set(paymentRecord, {merge: true});
    await db.collection("senderPaymentRecords").doc(intent.id).set({
      ...paymentRecord,
      amount: authoritativeAmountPence / 100,
      provider: "stripe",
    }, {merge: true});

    if (deliveryRef) {
      await deliveryRef.set({
        stripePaymentIntentId: intent.id,
        paymentStatus: intent.status,
        stripePaymentStatus: intent.status,
        paymentUpdatedAt: FieldValue.serverTimestamp(),
        authoritativePricing: quote,
        pricingDiscrepancyPence: submittedAmountPence - authoritativeAmountPence,
      }, {merge: true});
    }

    const response = generateResponse(intent);
    response.paymentIntentId = intent.id;
    response.customerId = customerId;
    response.ephemeralKey = ephemeralKey.secret;
    response.amount = authoritativeAmountPence;
    response.currency = "gbp";
    response.authoritativePricing = quote;

    console.log(`Intent: ${intent}`);
    return res.send(response);
  } catch (e) {
    console.log(e);
    return sendPaymentError(res, e);
  }
};

exports.StripePayEndpointMethodId = functions.https.onRequest(createPaymentIntentHandler);
exports.createPaymentIntent = functions.https.onRequest(createPaymentIntentHandler);

const confirmPaymentIntentHandler = async (req, res) => {
  if (allowCors(req, res)) return;
  const {
    paymentIntentId,
  } = req.body;

  try {
    if (paymentIntentId) {
      // Confirm the PaymentIntent to finalize payment after handling a required action
      // on the client.
      const intent = await stripe.paymentIntents.confirm(paymentIntentId);
      // After confirm, if the PaymentIntent's status is succeeded, fulfill the order.
      return res.send(generateResponse(intent));
    } return res.sendStatus(400);
  } catch (e) {
    // Handle "hard declines" e.g. insufficient funds, expired card, etc
    // See https://stripe.com/docs/declines/codes for more.
    return res.send({error: e.message});
  }
};

exports.StripePayEndpointIntentId = functions.https.onRequest(confirmPaymentIntentHandler);
exports.confirmPaymentIntent = functions.https.onRequest(confirmPaymentIntentHandler);

exports.StripeWebhook = functions.runWith({secrets: [stripeWebhookSecret]}).https.onRequest(async (req, res) => {
  const sig = req.headers["stripe-signature"];
  // console.log(sig);

  const stripeWebhookSigningSecret = stripeWebhookSecret.value() || stripeConfig.webhooksecret;
  if (!stripeWebhookSigningSecret) {
    return res.status(500).send({error: "Stripe webhook secret is not configured"});
  }

  let event;
  try {
    event = stripe.webhooks.constructEvent(req.rawBody, sig, stripeWebhookSigningSecret);
  } catch (err) {
    console.error("Stripe webhook signature verification failed:", err.message);
    return res.status(400).send({error: "Invalid Stripe webhook signature"});
  }

  console.log("💰 Webhook working!");
  console.log(`Event: ${event.type}`);

  if (event.type === "charge.refunded") {
    const refundResult = await stripeRefunds.syncChargeRefund({db: getFirestore(), event});
    return res.send({success: true, refund: refundResult});
  }

  if (event.type === "payment_intent.succeeded" ||
      event.type === "payment_intent.processing" ||
      event.type === "payment_intent.payment_failed" ||
      event.type === "payment_intent.canceled") {
    const tipResult = await ratingsTipping.processStripeTipIntent(stripe, event.data.object);
    if (tipResult && tipResult.handled) return res.send({success: true, tip: tipResult});
  }

  if (event.type === "charge.succeeded") {
    console.log("💰 Payment completed!");
    const sessionData = event.data.object;
    const metadata = sessionData.metadata;

    const messageObj = JSON.stringify({
      // sessionData,
      metadata,
      success: true,
    });


    const message = {
      apns: {
        payload: {
          aps: {
            "content-available": 1,
          },
        },
      },
      data: {
        "type": "payment",
        "data": messageObj,
      },
      // notification: {
      //   title: `${req.user.firstName}`,
      //   body: text,
      // },
      token: metadata.pushToken,

    };

    getMessaging().send(message).then(
        (response)=> {
          console.log(`Successfully sent message: ${response}`);
          // console.log(`token: ${metadata.pushToken}`);
        },
    ).catch((err)=>{
      //   console.log(err)
      // console.log('new error')
    });
  }

  if (event.type == "checkout.session.completed") {
    console.log("💰 Payment completed!");
    const sessionData = event.data.object;
    const metadata = sessionData.metadata;

    const messageObj = JSON.stringify({
      // sessionData,
      metadata,
      success: true,
    });


    const message = {
      apns: {
        payload: {
          aps: {
            "content-available": 1,
          },
        },
      },
      data: {
        "type": "payment",
        "data": messageObj,
      },
      // notification: {
      //   title: `${req.user.firstName}`,
      //   body: text,
      // },
      token: metadata.pushToken,

    };

    getMessaging().send(message).then(
        (response)=> {
          console.log(`Successfully sent message: ${response}`);
        },
    ).catch((err)=>{
      //   console.log(err)
      // console.log('new error')
    });
  }

  res.send({success: true});
});

exports.RetrieveCardDetails = functions.https.onRequest(async (req, res) => {
  try {
    const {
      customerId,
    } = req.body;
    // const customer = await stripe.customers.retrieve(customerId);

    const paymentMethods = await stripe.paymentMethods.list({
      customer: customerId,
      type: "card",
    });

    res.json(paymentMethods);
    // const cards = customer.sources.data.filter((source) => source.object === "card");
    // res.json(cards);
  } catch (error) {
    console.error(error);
    res.status(500).json({error: "Unable to retrieve cards"});
  }
});


exports.calculateEarnings = functions.https.onRequest(async (req, res) => {
  if (allowCors(req, res)) return;
  try {
    const {riderId} = req.body;

    if (!riderId) {
      return res.status(404).send({msg: "riderId is required"});
    }

    const paymentRef = await getFirestore().collection("payments").doc(riderId).get();

    let accountBalance = 0;
    if (paymentRef.exists) {
      const paymentData = paymentRef.data();
      accountBalance = paymentData.accountBalance || 0;
    }

    // Retrieve the 'history' database reference
    const historyRef = getFirestore().collection("history");

    // Query the history for the riderId
    const snapshot = await historyRef.where("riderId", "==", riderId).get();

    let totalAmountEarned = 0;

    // Loop through the history records and calculate the total amount earned
    snapshot.forEach((childSnapshot) => {
      const historyEntry = childSnapshot.data();
      totalAmountEarned += historyEntry.price || 0;
    });

    const currentDate = new Date();

    // Initialize an object to store daily earnings
    const weeklyEarnings = {
      Sun: 0,
      Mon: 0,
      Tue: 0,
      Wed: 0,
      Thu: 0,
      Fri: 0,
      Sat: 0,
    };

    // Calculate the start date of the week (assuming Sunday is the start of the week)
    const startDate = new Date(currentDate);
    startDate.setDate(startDate.getDate() - 7);

    // Calculate the end date of the week (assuming Saturday is the end of the week)
    const endDate = new Date(currentDate);
    // endDate.setDate(endDate.getDate() + (6 - endDate.getDay()));

    // Query Firestore for earnings within the current week for the given user
    const earningsSnapshot = await getFirestore().collection("history")
        .where("riderId", "==", riderId)
        .where("createdAt", ">=", startDate)
        .where("createdAt", "<=", endDate)
        .get();

    // Aggregate earnings by day
    earningsSnapshot.forEach((doc) => {
      const earningData = doc.data();

      // console.log(earningData);
      const earningDate = earningData.createdAt.toDate();
      const dayOfWeek = earningDate.toLocaleDateString("en-US", {weekday: "short"});

      weeklyEarnings[dayOfWeek] += earningData.price || 0;
    });

    // response.json(weeklyEarnings);

    res.status(200).send({
      accountBalance: accountBalance,
      totalAmountEarned: totalAmountEarned,
      totalTrips: snapshot.size,
      weeklyEarnings: weeklyEarnings,
    });
  } catch (error) {
    console.error("Error calculating total amount earned:", error);
    res.status(500).send({
      error: error,
    });
  }
});

exports.endTrip = functions.https.onRequest(async (req, res) => {
  if (allowCors(req, res)) return;
  try {
    const {riderId, requestId, riderName} = req.body;

    if (!requestId) {
      return res.status(404).send({msg: "requestId is required"});
    }

    if (!riderId) {
      return res.status(404).send({msg: "riderId is required"});
    }

    if (!riderName) {
      return res.status(404).send({msg: "riderName is required"});
    }

    // Retrieve the 'history' database reference
    const ride = await getFirestore().collection("deliveryRequests").where("requestId", "==", requestId).get();
    const rideData = ride.docs[0];
    const rideDataRes = rideData.data();

    if (!rideData.exists) {
      return res.status(404).send({msg: "Trip already completed"});
    }

    if (rideDataRes.riderId != riderId) {
      return res.status(400).send({msg: "riderId does not match"});
    }

    const rideCost = rideDataRes.price;


    const uuid1 = uuidv4();
    const uuid2 = uuidv4();
    const uuiduuid = `${uuid1}${uuid2}`;
    await riderEarnings.creditRiderEarnings({
      db: getFirestore(), riderId, deliveryId: requestId, amount: rideCost,
    });

    const irisData = require("./iris-core");
    const privateIrisDoc = await getFirestore()
        .collection("irisPrivate")
        .doc(requestId)
        .get();
    const privateIrisData = privateIrisDoc.exists ? privateIrisDoc.data() : {};
    const learningSnapshot = irisData.createLearningSnapshot({
      ...(rideDataRes.iris || {}),
      verification: privateIrisData.verification || {},
    }, {
      ...rideDataRes,
      completedAt: Date.now(),
    });

    await getFirestore().collection("deliveryRequests").doc(rideData.id).update({
      "status": "completed",
      "historyId": uuiduuid,
      "updatedAt": Date.now(),
    });
    await getFirestore().collection("irisPrivate").doc(requestId).set({
      requestId,
      learningSnapshot,
      updatedAt: Date.now(),
    }, {merge: true});

    const newRideData = rideDataRes;
    newRideData.userId = rideData.id;
    newRideData.riderName = riderName;
    newRideData.status = "completed";
    newRideData.timestamp = Date.now();

    await getFirestore().collection("history").doc(uuiduuid).set(newRideData);

    res.status(200).send({historyId: uuiduuid});
  } catch (error) {
    console.error("Error calculating total amount earned:", error);
    res.status(500).send({
      error: error,
    });
  }
});
