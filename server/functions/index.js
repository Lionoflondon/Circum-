/* eslint-disable max-len, require-jsdoc */
const {initializeApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const {getMessaging} = require("firebase-admin/messaging");
const {getAuth} = require("firebase-admin/auth");
const functions = require("firebase-functions/v1");
const stripeConfig = functions.config().stripe || {};
function firebaseProjectId() {
  try {
    const parsed = JSON.parse(process.env.FIREBASE_CONFIG || "{}");
    return parsed.projectId || process.env.GCLOUD_PROJECT || "";
  } catch (_) {
    return process.env.GCLOUD_PROJECT || "";
  }
}
function stripeMode(secret) {
  if (`${secret || ""}`.startsWith("sk_live_")) return "live";
  if (`${secret || ""}`.startsWith("sk_test_")) return "test";
  return "unknown";
}
function resolveStripeSecretKey() {
  const projectId = firebaseProjectId();
  const liveKey = stripeConfig.livekey;
  const configured = process.env.STRIPE_SECRET_KEY || stripeConfig.secret_key || liveKey;
  if (projectId === "circum-2797c" && stripeMode(configured) === "test") {
    if (stripeMode(liveKey) === "live") {
      console.warn("Stripe secret mode: test secret ignored in production; using configured live key.");
      return liveKey;
    }
    throw new Error("Production Stripe secret is test mode. Refusing to start Stripe functions.");
  }
  console.info(`Stripe secret mode: ${stripeMode(configured)}`);
  return configured;
}
const stripeSecretKey = resolveStripeSecretKey();
const stripe = require("stripe")(stripeSecretKey);
stripe._circumStripeMode = stripeMode(stripeSecretKey);
const stripeConnectClient = () => {
  const secret = resolveStripeSecretKey();
  const client = require("stripe")(secret);
  client._circumStripeMode = stripeMode(secret);
  return client;
};
const {v4: uuidv4} = require("uuid");

const sendPackage = require("./send-package");
const getAvaliableRequests = require("./get-avaliable-requests");
const acceptRideRequests = require("./accept-ride-requests");
const sendMessage = require("./send-message");
const sendRiderUpdate = require("./send-rider-update");
const healthPlus = require("./health-plus");
const healthPlusOperations = require("./health-plus-operations");
const iris = require("./iris");
const deliveryAdjustments = require("./delivery-adjustments");
const platformNotifications = require("./platform-notifications");
const legends = require("./legends");
const giftsPayment = require("./gifts-payment");
const rothLedger = require("./roth-ledger");
const businessPayments = require("./business-payments");
const riderConnect = require("./rider-connect");
const senderTrust = require("./sender-trust");
const referrals = require("./referrals");
const movementLedger = require("./movement-ledger");
const giftStoryAutomation = require("./gift-story-automation");
const deliveryPolicy = require("./delivery-policy");
const riderPresence = require("./rider-presence");
const freeAddressSearch = require("./free-address-search");
const senderBooking = require("./sender-booking");
const deliveryTracking = require("./delivery-tracking");
const {calculateWalletCheckout} = require("./wallet-core");

initializeApp();

exports.sendPackage = sendPackage;
exports.getAvaliableRequests = getAvaliableRequests;
exports.getAvailableRequests = getAvaliableRequests;
exports.acceptRideRequests = acceptRideRequests;
exports.sendMessage = sendMessage;
exports.sendRiderUpdate = sendRiderUpdate;
exports.createHealthPlusCheckoutSession = healthPlus.createHealthPlusCheckoutSession;
exports.updateHealthPlusPickupStatus = healthPlus.updateHealthPlusPickupStatus;
exports.onHealthPlusPickupOperationalWrite = healthPlusOperations.onHealthPlusPickupOperationalWrite;
exports.processHealthPlusReminders = healthPlusOperations.processHealthPlusReminders;
exports.resetHealthPlusMonthlyUsage = healthPlusOperations.resetHealthPlusMonthlyUsage;
exports.generateHealthPlusRecurringBookings = healthPlusOperations.generateHealthPlusRecurringBookings;
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
exports.issueRothCredit = rothLedger.issueRothCredit;
exports.issueRothToWallets = rothLedger.issueRothToWallets;
exports.debitRothCredit = rothLedger.debitRothCredit;
exports.redeemGiftCard = rothLedger.redeemGiftCard;
exports.setWalletFrozen = rothLedger.setWalletFrozen;
exports.createWalletTopUp = rothLedger.createWalletTopUp(stripe);
exports.applyCheckoutRoth = rothLedger.applyCheckoutRoth;
exports.createBusinessRothCheckout = businessPayments.createBusinessRothCheckout(stripe);
exports.createBusinessInvoiceCheckout = businessPayments.createBusinessInvoiceCheckout(stripe);
exports.createStripeConnectAccountForRider = riderConnect.createStripeConnectAccountForRider(stripeConnectClient);
exports.createStripeOnboardingLink = riderConnect.createStripeOnboardingLink(stripeConnectClient);
exports.refreshStripeOnboardingLink = riderConnect.refreshStripeOnboardingLink(stripeConnectClient);
exports.syncStripeConnectStatus = riderConnect.syncStripeConnectStatus(stripeConnectClient);
exports.createRiderTransferOrPayout = riderConnect.createRiderTransferOrPayout(stripeConnectClient);
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
exports.onStoryNotificationWrite = giftStoryAutomation.onStoryNotificationWrite;
exports.cleanupExpiredGiftStories = giftStoryAutomation.cleanupExpiredGiftStories;
exports.requestSenderCancellation = deliveryPolicy.requestSenderCancellation;
exports.recordRiderArrival = deliveryPolicy.recordRiderArrival;
exports.recordArrivalZoneCheck = deliveryPolicy.recordArrivalZoneCheck;
exports.recordCustomerArrivalResponse = deliveryPolicy.recordCustomerArrivalResponse;
exports.reportWaitingContext = deliveryPolicy.reportWaitingContext;
exports.markRiderNoShow = deliveryPolicy.markRiderNoShow;
exports.goOnline = riderPresence.goOnline;
exports.goOffline = riderPresence.goOffline;
exports.updateRiderPresence = riderPresence.updateRiderPresence;
exports.onDeliveryPresenceWrite = riderPresence.onDeliveryPresenceWrite;
exports.markStaleRiderPresenceOffline = riderPresence.markStaleRiderPresenceOffline;
exports.searchFreeUkAddresses = freeAddressSearch.searchFreeUkAddresses;
exports.getSenderRothBalance = senderBooking.getSenderRothBalance;
exports.createSenderBookingQuote = senderBooking.createSenderBookingQuote;
exports.createSenderPaymentSession = senderBooking.createSenderPaymentSession(stripe);
exports.createSenderPaidDelivery = senderBooking.createSenderPaidDelivery(stripe);
exports.updateDeliveryTrackingStatus = deliveryTracking.updateDeliveryTrackingStatus;

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
  const {
    // paymentMethodId,
    amount,
    currency,
    // useStripeSdk,
    pushToken,
    name,
    // phone,
    email,
    userId,
    saveCard,
    useWallet,
    paymentCurrency,
    referenceId,
  } = req.body;

  //   const orderAmount = calculateOrderAmount(items);
  const orderTotalGbp = Number(amount || 0) / 100;

  try {
    let customerId;

    const userRef = await getFirestore().collection("users").doc(userId).get();

    if (userRef.exists) {
      const userData = userRef.data();
      customerId = userData.customerId || undefined;
    }
    let split = calculateWalletCheckout({
      orderTotalGbp,
      walletBalanceGbp: 0,
      selectedCurrency: paymentCurrency || currency || "gbp",
    });
    if (useWallet === true && userId) {
      const walletIdentity = `${email || userId}`.trim().toLowerCase();
      const walletRef = await getFirestore().collection("wallets").doc(walletIdentity).get();
      const walletData = walletRef.exists ? walletRef.data() : {};
      const walletBalance = Number(walletData.balance == null ? walletData.rothCredit || 0 : walletData.balance || 0);
      split = calculateWalletCheckout({
        orderTotalGbp,
        walletBalanceGbp: walletBalance,
        selectedCurrency: paymentCurrency || currency || "gbp",
      });
      if (split.walletContributionGbp > 0 && !split.stripeRequired) {
        await rothLedger.applyWalletDebit({
          userId,
          userEmail: email,
          amount: split.walletContributionGbp,
          type: "delivery_payment",
          referenceId: referenceId || null,
          notes: "Wallet applied to Circum delivery payment.",
          transactionId: referenceId ? `wallet_delivery_${referenceId}` : undefined,
          metadata: {
            orderTotalGbp: split.orderTotalGbp,
            remainingGbp: split.remainingGbp,
            service: "delivery",
          },
        });
      }
      if (!split.stripeRequired) {
        return res.send({
          status: "succeeded",
          walletPaidInFull: true,
          orderTotalGbp: split.orderTotalGbp,
          walletContributionGbp: split.walletContributionGbp,
          remainingStripeAmountGbp: 0,
        });
      }
    }

    const params = {
      amount: split.stripeAmountMinor,
      // confirm: true,
      currency: split.customerPaymentCurrency,
      // automatic_payment_methods: {
      //   enabled: true,
      //   allow_redirects: "never",
      // },
      // payment_method: paymentMethodId,
      // use_stripe_sdk: useStripeSdk,
      metadata: {
        name: name,
        email: email,
        pushToken: pushToken,
        paymentType: "delivery",
        userId: userId || "",
        userEmail: email || "",
        requestId: referenceId || "",
        walletApplied: split.walletContributionGbp > 0 ? "true" : "false",
        orderTotalGbp: `${split.orderTotalGbp}`,
        walletContributionGbp: `${split.walletContributionGbp}`,
        remainingGbp: `${split.remainingGbp}`,
        customerPaymentCurrency: split.customerPaymentCurrency,
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
        name: name,
        email: email,
      });
        // phone: phone,

      customerId = customer.id;

      if (saveCard == true) {
        params.customer = customerId;
      }

      await getFirestore().collection("users").doc(userId).update({
        customerId: customer.id,
      });
    }

    const ephemeralKey = await stripe.ephemeralKeys.create(
        {customer: customerId},
        {apiVersion: "2020-08-27"},
    );


    const intent = await stripe.paymentIntents.create(params);

    const response = generateResponse(intent);
    response.customerId = customerId;
    response.ephemeralKey = ephemeralKey.secret,

    console.log(`Intent: ${intent}`);
    return res.send(response);
  } catch (e) {
    console.log(e);
    // Handle "hard declines" e.g. insufficient funds, expired card, etc
    // See https://stripe.com/docs/declines/codes for more.
    return res.send({error: e.message});
  }
};

exports.StripePayEndpointMethodId = functions.https.onRequest(createPaymentIntentHandler);
exports.createPaymentIntent = functions.https.onRequest(createPaymentIntentHandler);

const confirmPaymentIntentHandler = async (req, res) => {
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

exports.StripeWebhook = functions.https.onRequest(async (req, res) => {
  const sig = req.headers["stripe-signature"];
  // console.log(sig);

  const stripeWebhookSigningSecret = stripeConfig.webhooksecret;
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

  if (event.type === "charge.succeeded") {
    console.log("💰 Payment completed!");
    const sessionData = event.data.object;
    const metadata = sessionData.metadata;
    if (metadata && metadata.type === "wallet_top_up") {
      await rothLedger.recordWalletTopUpFromStripeSession(sessionData, event.id);
    }
    if (metadata && (metadata.type === "business_roth_purchase" || metadata.type === "business_invoice_payment")) {
      await businessPayments.handleBusinessCheckoutSession(sessionData, event.id);
    }
    if (metadata && metadata.walletApplied === "true" && metadata.walletContributionGbp) {
      const service = metadata.paymentType === "gifts" ? "gifts" :
        metadata.feature === "health_plus" ? "health_plus" :
          "delivery";
      await rothLedger.applyWalletDebit({
        userId: metadata.senderId || metadata.userId || metadata.uid || metadata.userEmail,
        userEmail: metadata.senderEmail || metadata.userEmail || metadata.email,
        amount: Number(metadata.walletContributionGbp || 0),
        type: service === "gifts" ? "gift_payment" : service === "health_plus" ? "health_payment" : "delivery_payment",
        referenceId: metadata.giftDraftId || metadata.bookingId || metadata.requestId || sessionData.id,
        notes: `Roth applied to ${service.replace("_", " ")} checkout.`,
        transactionId: `wallet_${service}_${metadata.giftDraftId || metadata.bookingId || metadata.requestId || sessionData.id}`,
        metadata: {stripeEventId: event.id, service, stripeCheckoutSessionId: sessionData.id},
      });
    }

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
    const userId = metadata && (metadata.senderId || metadata.userId || metadata.uid);
    if (userId) {
      await rothLedger.safeRecordRothMovement({
        userId,
        amount: Number(sessionData.amount || sessionData.amount_captured || 0) / 100,
        balanceType: rothLedger.BALANCE_TYPES.rothCredit,
        type: rothLedger.TRANSACTION_TYPES.stripePaymentRecord,
        reason: "Stripe charge recorded in Roth ledger.",
        relatedEntityId: metadata.requestId || metadata.bookingId || metadata.giftDraftId || null,
        paymentProvider: "stripe",
        providerTransactionId: sessionData.id,
        transactionId: `stripe_charge_${sessionData.id}`,
        ledgerOnly: true,
        metadata: {stripeEventId: event.id, service: metadata.type || "circum"},
      });
    }
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
    const userId = metadata && (metadata.senderId || metadata.userId || metadata.uid);
    if (metadata && (metadata.type === "business_roth_purchase" || metadata.type === "business_invoice_payment")) {
      await businessPayments.handleBusinessCheckoutSession(sessionData, event.id);
    }
    if (userId) {
      await rothLedger.safeRecordRothMovement({
        userId,
        amount: Number(sessionData.amount_total || 0) / 100,
        balanceType: rothLedger.BALANCE_TYPES.rothCredit,
        type: rothLedger.TRANSACTION_TYPES.stripePaymentRecord,
        reason: "Stripe Checkout session recorded in Roth ledger.",
        relatedEntityId: metadata.requestId || metadata.bookingId || metadata.giftDraftId || null,
        paymentProvider: "stripe",
        providerTransactionId: sessionData.payment_intent || sessionData.id,
        transactionId: `stripe_checkout_${sessionData.id}`,
        ledgerOnly: true,
        metadata: {stripeEventId: event.id, service: metadata.type || "circum"},
      });
    }
  }

  res.send({success: true});
});

exports.calculateEarnings = functions.https.onRequest(async (req, res) => {
  try {
    const {riderId} = req.body;
    const authHeader = req.get("Authorization") || "";
    const match = authHeader.match(/^Bearer (.+)$/);

    if (!match) {
      return res.status(401).send({msg: "Authorization token is required"});
    }

    let decodedToken;
    try {
      decodedToken = await getAuth().verifyIdToken(match[1]);
    } catch (error) {
      return res.status(401).send({msg: "Invalid authorization token"});
    }

    if (!riderId) {
      return res.status(404).send({msg: "riderId is required"});
    }

    if (decodedToken.uid !== riderId) {
      return res.status(403).send({msg: "riderId does not match authenticated user"});
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
  try {
    const {riderId, requestId, riderName} = req.body;
    const authHeader = req.get("Authorization") || "";
    const match = authHeader.match(/^Bearer (.+)$/);

    if (!match) {
      return res.status(401).send({msg: "Authorization token is required"});
    }

    let decodedToken;
    try {
      decodedToken = await getAuth().verifyIdToken(match[1]);
    } catch (error) {
      return res.status(401).send({msg: "Invalid authorization token"});
    }

    if (!requestId) {
      return res.status(404).send({msg: "requestId is required"});
    }

    if (!riderId) {
      return res.status(404).send({msg: "riderId is required"});
    }

    if (!riderName) {
      return res.status(404).send({msg: "riderName is required"});
    }

    if (decodedToken.uid !== riderId) {
      return res.status(403).send({msg: "riderId does not match authenticated user"});
    }

    // Retrieve the 'history' database reference
    const ride = await getFirestore().collection("deliveryRequests").where("requestId", "==", requestId).get();
    const rideData = ride.docs[0];

    if (!rideData || !rideData.exists) {
      return res.status(404).send({msg: "Trip not found"});
    }

    const rideDataRes = rideData.data();

    if (rideDataRes.riderId !== riderId) {
      return res.status(403).send({msg: "riderId does not match"});
    }

    if (rideDataRes.status === "completed") {
      return res.status(409).send({
        msg: "Trip already completed",
        historyId: rideDataRes.historyId || "",
      });
    }

    const rideCost = rideDataRes.price;


    const uuid1 = uuidv4();
    const uuid2 = uuidv4();
    const uuiduuid = `${uuid1}${uuid2}`;
    let riderBalance = 0;

    const paymentRef = getFirestore().collection("payments").doc(riderId);

    const getPaymentData = await paymentRef.get();
    const paymentData = getPaymentData.data();

    if (getPaymentData.exists) {
      riderBalance = paymentData.accountBalance || 0;
    }

    await paymentRef.set({
      accountBalance: riderBalance+ rideCost,
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
