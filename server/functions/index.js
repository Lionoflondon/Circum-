/* eslint-disable max-len, require-jsdoc */
const {initializeApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const {getMessaging} = require("firebase-admin/messaging");
const functions = require("firebase-functions/v1");
const {defineSecret} = require("firebase-functions/params");
const stripeWebhookSecret = defineSecret("STRIPE_WEBHOOK_SECRET");
const {
  assertStripeEventMode,
  resolveStripeRuntimeConfig,
} = require("./stripe-config");
let cachedStripeRuntimeConfig = null;
let cachedStripe = null;

function getStripeRuntimeConfig() {
  if (!cachedStripeRuntimeConfig) {
    cachedStripeRuntimeConfig = resolveStripeRuntimeConfig();
  }
  return cachedStripeRuntimeConfig;
}

function getStripeClient() {
  if (!cachedStripe) {
    const runtimeConfig = getStripeRuntimeConfig();
    cachedStripe = require("stripe")(runtimeConfig.secretKey);
    cachedStripe._circumStripeMode = runtimeConfig.mode;
  }
  return cachedStripe;
}

const stripe = new Proxy({}, {
  get(_target, property) {
    return getStripeClient()[property];
  },
});
const stripeConnectClient = () => stripe;

const sendPackage = require("./send-package");
const getAvaliableRequests = require("./get-avaliable-requests");
const acceptRideRequests = require("./accept-ride-requests");
const sendMessage = require("./send-message");
const sendRiderUpdate = require("./send-rider-update");
const healthPlus = require("./health-plus");
const healthMembershipLifecycle = require("./health-membership-lifecycle");
const iris = require("./iris");
const irisPhotoAnalysis = require("./iris-photo-analysis");
const deliveryAdjustments = require("./delivery-adjustments");
const platformNotifications = require("./platform-notifications");
const legends = require("./legends");
const giftsPayment = require("./gifts-payment");
const communicationEngine = require("./communication-engine");
const deliveryPolicy = require("./delivery-policy");
const deliveryTracking = require("./delivery-tracking");
const deliveryEvidence = require("./delivery-evidence");
const ratingsTipping = require("./ratings-tipping");
const stripeRefunds = require("./stripe-refunds");
const riderEarningsSummary = require("./rider-earnings-summary");
const founderRiderAccess = require("./founder-rider-access");
const founderReviewFixture = require("./founder-review-fixture");
const healthPlusOperations = require("./health-plus-operations");
const rothLedger = require("./roth-ledger");
const rothGrantCampaigns = require("./roth-grant-campaigns");
const businessPayments = require("./business-payments");
const riderConnect = require("./rider-connect");
const senderTrust = require("./sender-trust");
const referrals = require("./referrals");
const movementLedger = require("./movement-ledger");
const movementTimeline = require("./movement-timeline");
const giftStoryAutomation = require("./gift-story-automation");
const riderPresence = require("./rider-presence");
const freeAddressSearch = require("./free-address-search");
const senderBooking = require("./sender-booking");
const senderFinance = require("./sender-finance");
const {senderPaymentCallable} = require("./sender-app-check");
const senderSavedAddresses = require("./sender-saved-addresses");
const senderAccount = require("./sender-account");
const riderAccount = require("./rider-account");
const deliveryCleanup = require("./delivery-cleanup");
const staleDelivery = require("./stale-delivery");
const accountClosure = require("./account-closure");
const businessAccess = require("./business-access");
const riderIrisAcknowledgement = require("./rider-iris-acknowledgement");
const adminIrisReferenceImages = require("./admin-iris-reference-images");
const adminRiderAuthority = require("./admin-rider-authority");
const adminGovernance = require("./admin-governance");
const adminOperationsAuthority = require("./admin-operations-authority");
const {routeCheckoutSessionCompleted} = require("./checkout-session-router");
const {createStripeWebhookProcessor} = require("./stripe-webhook-core");

initializeApp();
getFirestore().settings({ignoreUndefinedProperties: true});

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

exports.sendPackage = sendPackage;
exports.getAvaliableRequests = getAvaliableRequests;
exports.getAvailableRequests = getAvaliableRequests;
exports.getNearbyRequests = getAvaliableRequests;
exports.acceptRideRequests = acceptRideRequests;
exports.sendMessage = sendMessage;
exports.sendCircumMessage = communicationEngine.sendCircumMessage;
exports.markConversationRead = communicationEngine.markConversationRead;
exports.setConversationTyping = communicationEngine.setConversationTyping;
exports.sendRiderUpdate = sendRiderUpdate;
exports.createHealthPlusCheckoutSession =
  healthPlus.createHealthPlusCheckoutSession;
exports.createHealthPlusBooking = healthPlus.createHealthPlusBooking;
exports.updateSenderHealthPlusBooking =
  healthPlus.updateSenderHealthPlusBooking;
exports.updateHealthPlusPickupStatus = healthPlus.updateHealthPlusPickupStatus;
exports.analyseIris = iris.analyseIris;
exports.analyseParcelPhotoForIris = irisPhotoAnalysis.analyseParcelPhotoForIris;
exports.adjudicateIris = iris.adjudicateIris;
exports.reportLoadDiscrepancy = deliveryAdjustments.reportLoadDiscrepancy;
exports.reviewDeliveryAdjustment = deliveryAdjustments.reviewDeliveryAdjustment;
exports.cancelAdjustedCollection = deliveryAdjustments.cancelAdjustedCollection;
exports.createDeliveryAdjustmentPayment =
  deliveryAdjustments.createDeliveryAdjustmentPayment;
exports.finalizeDeliveryAdjustmentPayment =
  deliveryAdjustments.finalizeDeliveryAdjustmentPayment;
exports.onDeliveryCreated = platformNotifications.onDeliveryCreated;
exports.onDeliveryUpdated = platformNotifications.onDeliveryUpdated;
exports.onChatMessageCreated = platformNotifications.onChatMessageCreated;
exports.onSupportTicketCreated = platformNotifications.onSupportTicketCreated;
exports.onDisputeCreated = platformNotifications.onDisputeCreated;
exports.onRiderProfileUpdated = platformNotifications.onRiderProfileUpdated;
exports.onPayoutUpdated = platformNotifications.onPayoutUpdated;
exports.escalateUnclaimedDeliveries =
  platformNotifications.escalateUnclaimedDeliveries;
exports.awardLegendOnCompletion = legends.awardLegendOnCompletion;
exports.createGiftPayment = giftsPayment.createGiftPayment(stripe);
exports.finalizeGiftPayment = giftsPayment.finalizeGiftPayment(stripe);
exports.cancelGiftPayment = giftsPayment.cancelGiftPayment(stripe);
exports.cleanupExpiredGiftVoiceDrafts =
  giftsPayment.cleanupExpiredGiftVoiceDrafts;
exports.onGiftRequestVoiceMediaDeleted =
  giftsPayment.onGiftRequestVoiceMediaDeleted;
exports.recordRiderArrival = deliveryPolicy.recordRiderArrival;
exports.reportWaitingContext = deliveryPolicy.reportWaitingContext;
exports.markRiderNoShow = deliveryPolicy.markRiderNoShow;
exports.requestRiderCancellation = require("./rider-cancellation").requestRiderCancellation;
exports.cancelDelivery = deliveryPolicy.requestSenderCancellation(stripe);
exports.updateDeliveryTrackingStatus =
  deliveryTracking.updateDeliveryTrackingStatus;
exports.completeDelivery = require("./delivery-completion-reconciled").completeDelivery;
exports.recordDeliveryEvidence = deliveryEvidence.recordDeliveryEvidence;
exports.submitDeliveryEvidence = deliveryEvidence.submitDeliveryEvidence;
exports.updateDeliveryLiveLocation =
  deliveryTracking.updateDeliveryLiveLocation;
exports.reconcilePendingDeliverySettlements =
  deliveryTracking.reconcilePendingDeliverySettlements;
exports.submitDeliveryRating = ratingsTipping.submitDeliveryRating;
exports.repairRiderRatingFeedback = ratingsTipping.repairRiderRatingFeedback;
exports.submitDeliveryTip = ratingsTipping.submitDeliveryTip(stripe);
exports.refundDeliveryTip = ratingsTipping.refundDeliveryTip(stripe);

exports.getRiderEarningsSummary =
  riderEarningsSummary.getRiderEarningsSummary();
exports.adminReconcileRiderEarnings = riderEarningsSummary.adminReconcileRiderEarnings();
exports.scheduledRiderEarningsReconciliation = riderEarningsSummary.scheduledRiderEarningsReconciliation;
exports.setFounderRiderAccess = founderRiderAccess.setFounderRiderAccess();
exports.designateGooglePlayReviewAccount = founderReviewFixture.designateReviewAccount();
exports.revokeGooglePlayReviewAccount = founderReviewFixture.revokeReviewAccount();
exports.createGooglePlayReviewFixture = founderReviewFixture.createReviewFixture();
exports.getGooglePlayReviewFixture = founderReviewFixture.getReviewFixture();
exports.setGooglePlayReviewPresence = founderReviewFixture.setReviewPresence();
exports.updateGooglePlayReviewFixtureLocation = founderReviewFixture.updateReviewFixtureLocation();
exports.startAdminConversation = communicationEngine.startAdminConversation;
exports.getOrCreateSupportConversation =
  communicationEngine.getOrCreateSupportConversation;
exports.submitWebsiteSupportRequest =
  communicationEngine.submitWebsiteSupportRequest;
exports.updateSupportConversationStatus =
  communicationEngine.updateSupportConversationStatus;
exports.reportCircumMessage = communicationEngine.reportCircumMessage;
exports.sendCircumAnnouncement = communicationEngine.sendCircumAnnouncement;
exports.retryNotificationDelivery = communicationEngine.retryNotificationDelivery;
exports.onHealthPlusPickupOperationalWrite =
  healthPlusOperations.onHealthPlusPickupOperationalWrite;
exports.processHealthPlusReminders =
  healthPlusOperations.processHealthPlusReminders;
exports.resetHealthPlusMonthlyUsage =
  healthPlusOperations.resetHealthPlusMonthlyUsage;
exports.generateHealthPlusRecurringBookings =
  healthPlusOperations.generateHealthPlusRecurringBookings;
exports.onGiftRequestCreated = platformNotifications.onGiftRequestCreated;
exports.onGiftRequestUpdated = platformNotifications.onGiftRequestUpdated;
exports.onGiftCampaignParticipantUpdated =
  platformNotifications.onGiftCampaignParticipantUpdated;
exports.awardFoundingRiderOnApproval = legends.awardFoundingRiderOnApproval;
exports.awardFoundingRiderOnRiderApproval =
  legends.awardFoundingRiderOnRiderApproval;
exports.awardPatronOnBusinessInvoicePaid =
  legends.awardPatronOnBusinessInvoicePaid;
exports.grantRecognition = legends.grantRecognition;
exports.revokeRecognition = legends.revokeRecognition;
exports.createRothGrantCampaign = rothGrantCampaigns.createRothGrantCampaign;
exports.adminGrantRothToUser = rothGrantCampaigns.adminGrantRothToUser;
exports.dryRunRothGrantCampaign = rothGrantCampaigns.dryRunRothGrantCampaign;
exports.approveRothGrantCampaign = rothGrantCampaigns.approveRothGrantCampaign;
exports.executeRothGrantCampaign = rothGrantCampaigns.executeRothGrantCampaign;
exports.reconcileRothGrantCampaign = rothGrantCampaigns.reconcileRothGrantCampaign;
exports.cancelRothGrantCampaign = rothGrantCampaigns.cancelRothGrantCampaign;
exports.debitRothCredit = rothLedger.debitRothCredit;
exports.redeemGiftCard = rothLedger.redeemGiftCard;
exports.setWalletFrozen = rothLedger.setWalletFrozen;
exports.createWalletTopUp = rothLedger.createWalletTopUp(stripe);
exports.applyCheckoutRoth = rothLedger.applyCheckoutRoth;
exports.initialiseSenderWallet = rothLedger.initialiseSenderWallet;
exports.getSenderWallet = rothLedger.getSenderWallet;
exports.getSenderWalletTransactions = rothLedger.getSenderWalletTransactions;
exports.completeSenderWalletOnboarding =
  rothLedger.completeSenderWalletOnboarding;
exports.requestSenderWalletDebit = rothLedger.requestSenderWalletDebit;
exports.requestSenderWalletRefund = rothLedger.requestSenderWalletRefund;
exports.reportRating = ratingsTipping.reportRating;
exports.confirmRiderIrisAssessment =
  riderIrisAcknowledgement.confirmRiderIrisAssessment;
exports.getIrisReferenceImage = adminIrisReferenceImages.getIrisReferenceImage;
exports.finalizeIrisReferenceImage =
  adminIrisReferenceImages.finalizeIrisReferenceImage;
exports.deleteIrisReferenceImage =
  adminIrisReferenceImages.deleteIrisReferenceImage;
exports.closeCircumAccount = accountClosure.closeAccount;
exports.createBusinessRothCheckout =
  businessPayments.createBusinessRothCheckout(stripe);
exports.listBusinessRothTransactions =
  businessPayments.listBusinessRothTransactions;
exports.adminCreateBusinessInvoice =
  businessPayments.adminCreateBusinessInvoice;
exports.createBusinessInvoiceCheckout =
  businessPayments.createBusinessInvoiceCheckout(stripe);
exports.cancelBusinessInvoiceCheckout = businessPayments.cancelBusinessInvoiceCheckout(stripe);
exports.createBusinessAccount = businessAccess.createBusinessAccount;
exports.ensureBusinessCompanyCode = businessAccess.ensureBusinessCompanyCode;
exports.lookupBusinessByCompanyCode =
  businessAccess.lookupBusinessByCompanyCode;
exports.requestBusinessAccess = businessAccess.requestBusinessAccess;
exports.reviewBusinessAccessRequest =
  businessAccess.reviewBusinessAccessRequest;
exports.updateBusinessProfile = businessAccess.updateBusinessProfile;
exports.inviteBusinessMember = businessAccess.inviteBusinessMember;
exports.updateBusinessMemberRole = businessAccess.updateBusinessMemberRole;
exports.updateBusinessMemberStatus = businessAccess.updateBusinessMemberStatus;
exports.removeBusinessMember = businessAccess.removeBusinessMember;
exports.recordBusinessIrisMoment = businessAccess.recordBusinessIrisMoment;
exports.createStripeConnectAccountForRider =
  riderConnect.createStripeConnectAccountForRider(stripeConnectClient);
exports.createStripeOnboardingLink =
  riderConnect.createStripeOnboardingLink(stripeConnectClient);
exports.refreshStripeOnboardingLink =
  riderConnect.refreshStripeOnboardingLink(stripeConnectClient);
exports.syncStripeConnectStatus =
  riderConnect.syncStripeConnectStatus(stripeConnectClient);
exports.createStripeAccountManagementLink =
  riderConnect.createStripeAccountManagementLink(stripeConnectClient);
exports.riderPayoutReadiness = riderConnect.riderPayoutReadiness();
exports.createRiderTransferOrPayout =
  riderConnect.createRiderTransferOrPayout(stripeConnectClient);
exports.requestRiderWithdrawal = riderConnect.requestRiderWithdrawal();
exports.cancelRiderWithdrawal = riderConnect.cancelRiderWithdrawal();
exports.adminReviewRiderWithdrawal = riderConnect.adminReviewRiderWithdrawal();
exports.adminReviewRider = adminRiderAuthority.adminReviewRider;
exports.adminGovernanceAction = adminGovernance.adminGovernanceAction;
exports.adminResolveAccess = adminOperationsAuthority.adminResolveAccess;
exports.adminQueryPage = adminOperationsAuthority.adminQueryPage;
exports.adminRecordAuditEntry = adminOperationsAuthority.adminRecordAuditEntry;
exports.adminSaveAdminUser = adminOperationsAuthority.adminSaveAdminUser;
exports.adminUpdateDeliveryOperation =
  adminOperationsAuthority.adminUpdateDeliveryOperation;
exports.adminArchiveDelivery = adminOperationsAuthority.adminArchiveDelivery;
exports.adminUpdateIrisReview = adminOperationsAuthority.adminUpdateIrisReview;
exports.adminUpdateSenderAccountStatus =
  adminOperationsAuthority.adminUpdateSenderAccountStatus;
exports.adminUpdateBusinessAccountStatus =
  adminOperationsAuthority.adminUpdateBusinessAccountStatus;
exports.adminUpdateBusinessOperation =
  adminOperationsAuthority.adminUpdateBusinessOperation;
exports.adminUpdateBusinessMember =
  adminOperationsAuthority.adminUpdateBusinessMember;
exports.adminUpdateHealthPlusPickup =
  adminOperationsAuthority.adminUpdateHealthPlusPickup;
exports.adminUpdateHealthPlusSchedule =
  adminOperationsAuthority.adminUpdateHealthPlusSchedule;
exports.adminUpdateHealthPlusProfile =
  adminOperationsAuthority.adminUpdateHealthPlusProfile;
exports.adminUpdateFinanceWorkflow =
  adminOperationsAuthority.adminUpdateFinanceWorkflow;
exports.adminRequestAccountMergeReview =
  adminOperationsAuthority.adminRequestAccountMergeReview;
exports.adminUpdateGiftWorkflow =
  adminOperationsAuthority.adminUpdateGiftWorkflow;
exports.adminUpdateGiftCampaignParticipant =
  adminOperationsAuthority.adminUpdateGiftCampaignParticipant;
exports.adminSaveGiftBrandPartner =
  adminOperationsAuthority.adminSaveGiftBrandPartner;
exports.adminSuggestGiftCampaignMatch =
  adminOperationsAuthority.adminSuggestGiftCampaignMatch;
exports.adminApproveGiftCampaignMatch =
  adminOperationsAuthority.adminApproveGiftCampaignMatch;
exports.adminBulkGiftCampaignAction =
  adminOperationsAuthority.adminBulkGiftCampaignAction;
exports.adminUpdateIrisRepositoryRecord =
  adminOperationsAuthority.adminUpdateIrisRepositoryRecord;
exports.adminUpdateIrisCandidateWorkflow =
  adminOperationsAuthority.adminUpdateIrisCandidateWorkflow;
exports.adminSaveGiftRequestEditor =
  adminOperationsAuthority.adminSaveGiftRequestEditor;
exports.adminUpdateGiftWorkspace =
  adminOperationsAuthority.adminUpdateGiftWorkspace;
exports.adminUpdatePlatformRecord =
  adminOperationsAuthority.adminUpdatePlatformRecord;
exports.adminAddAdminNote = adminOperationsAuthority.adminAddAdminNote;
exports.adminRecordRiderEvent =
  adminOperationsAuthority.adminRecordRiderEvent;
exports.adminResolveMessageReport =
  adminOperationsAuthority.adminResolveMessageReport;
exports.resetRiderTestStripeAccount =
  riderConnect.resetRiderTestStripeAccount();
exports.handleStripeConnectWebhook =
  riderConnect.handleStripeConnectWebhook(stripeConnectClient);
exports.scheduledRiderStripeStatusSync =
  riderConnect.scheduledRiderStripeStatusSync(stripeConnectClient);
exports.redactLegacyPayoutBankFields =
  riderConnect.redactLegacyPayoutBankFields();
exports.syncSenderTrustBaseline = senderTrust.syncSenderTrustBaseline;
exports.adminUpdateSenderTrust = senderTrust.adminUpdateSenderTrust;
exports.ensureReferralCode = referrals.ensureReferralCode;
exports.attachReferralCode = referrals.attachReferralCode;
exports.activateReferral = referrals.activateReferral;
exports.activateReferralOnDeliveryCompleted =
  referrals.activateReferralOnDeliveryCompleted;
exports.activateReferralOnGiftCompleted =
  referrals.activateReferralOnGiftCompleted;
exports.activateReferralOnHealthPlusCompleted =
  referrals.activateReferralOnHealthPlusCompleted;
exports.onGiftMovementWrite = movementLedger.onGiftMovementWrite;
exports.onHealthMovementWrite = movementLedger.onHealthMovementWrite;
exports.onHealthPaymentMovementWrite =
  movementLedger.onHealthPaymentMovementWrite;
exports.onMovementTimelineWrite = movementTimeline.onMovementTimelineWrite;
exports.onDeliveryLiveLocationWrite =
  movementTimeline.onDeliveryLiveLocationWrite;
exports.onGiftDeliveryCompleted = giftStoryAutomation.onGiftDeliveryCompleted;
exports.getSenderGiftStory = giftStoryAutomation.getSenderGiftStory;
exports.resolveGiftStoryAccess = giftStoryAutomation.resolveGiftStoryAccess;
exports.recordGiftStoryEvent = giftStoryAutomation.recordGiftStoryEvent;
exports.recordGiftStoryGuestEvent =
  giftStoryAutomation.recordGiftStoryGuestEvent;
exports.updateGiftStoryPrivacy = giftStoryAutomation.updateGiftStoryPrivacy;
exports.retryGiftStoryAutomation = giftStoryAutomation.retryGiftStoryAutomation;
exports.manageGiftStoryAccess = giftStoryAutomation.manageGiftStoryAccess;
exports.createGiftStoryVideoUpload =
  giftStoryAutomation.createGiftStoryVideoUpload;
exports.finalizeGiftStoryVideoUpload =
  giftStoryAutomation.finalizeGiftStoryVideoUpload;
exports.getGiftStoryVideoDownload =
  giftStoryAutomation.getGiftStoryVideoDownload;
exports.giftStoryLanding = giftStoryAutomation.giftStoryLanding;
exports.submitGiftStoryThankYou = giftStoryAutomation.submitGiftStoryThankYou;
exports.acknowledgeGiftStory = giftStoryAutomation.acknowledgeGiftStory;
exports.saveGiftStoryToVault = giftStoryAutomation.saveGiftStoryToVault;
exports.getGiftStoryActionState = giftStoryAutomation.getGiftStoryActionState;
exports.onStoryNotificationWrite = giftStoryAutomation.onStoryNotificationWrite;
exports.cleanupExpiredGiftStories =
  giftStoryAutomation.cleanupExpiredGiftStories;
exports.requestSenderCancellation = deliveryPolicy.requestSenderCancellation(stripe);
exports.previewSenderCancellation = deliveryPolicy.previewSenderCancellation;
exports.reconcilePendingSenderCancellations =
  deliveryPolicy.reconcilePendingSenderCancellations(stripe);
exports.recordArrivalZoneCheck = deliveryPolicy.recordArrivalZoneCheck;
exports.recordCustomerArrivalResponse =
  deliveryPolicy.recordCustomerArrivalResponse;
exports.goOnline = riderPresence.goOnline;
exports.goOffline = riderPresence.goOffline;
exports.updateRiderPresence = riderPresence.updateRiderPresence;
exports.onDeliveryPresenceWrite = riderPresence.onDeliveryPresenceWrite;
exports.markStaleRiderPresenceOffline =
  riderPresence.markStaleRiderPresenceOffline;
exports.searchFreeUkAddresses = freeAddressSearch.searchFreeUkAddresses;
exports.resolveUkAddressPlace = freeAddressSearch.resolveUkAddressPlace;
exports.getSenderRothBalance = senderBooking.getSenderRothBalance;
exports.getSenderRoutePreview = senderBooking.getSenderRoutePreview;
exports.getSenderPaymentMode = senderPaymentCallable((_data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
        "unauthenticated",
        "Sign in to continue payment.",
    );
  }
  return {mode: getStripeRuntimeConfig().mode};
});
exports.createSenderBookingQuote = senderBooking.createSenderBookingQuote;
exports.createSenderPaymentSession =
  senderBooking.createSenderPaymentSession(stripe);
exports.createSenderPaidDelivery =
  senderBooking.createSenderPaidDelivery(stripe);
exports.finalizeSenderWebCheckout =
  senderBooking.finalizeSenderWebCheckout(stripe);
exports.saveSenderDraft = senderBooking.saveSenderDraft;
exports.loadSenderDraft = senderBooking.loadSenderDraft;
exports.deleteSenderDraft = senderBooking.deleteSenderDraft;
exports.cleanupExpiredSenderDrafts = senderBooking.cleanupExpiredSenderDrafts;
exports.listSenderPaymentMethods =
  senderFinance.listSenderPaymentMethods(stripe);
exports.createSenderSetupIntent = senderFinance.createSenderSetupIntent(stripe);
exports.detachSenderPaymentMethod =
  senderFinance.detachSenderPaymentMethod(stripe);
exports.setDefaultSenderPaymentMethod =
  senderFinance.setDefaultSenderPaymentMethod(stripe);
exports.saveSenderCheckoutPreference =
  senderFinance.saveSenderCheckoutPreference;
exports.saveSenderSavedAddress = senderSavedAddresses.saveSenderSavedAddress;
exports.deleteSenderSavedAddress =
  senderSavedAddresses.deleteSenderSavedAddress;
exports.updateSenderProfile = senderAccount.updateSenderProfile;
exports.updateSenderProfilePhoto = senderAccount.updateSenderProfilePhoto;
exports.updateSenderPushToken = senderAccount.updateSenderPushToken;
exports.updateSenderNotificationState =
  senderAccount.updateSenderNotificationState;
exports.ensureSenderAccount = senderAccount.ensureSenderAccount;
exports.markSenderLegendCelebrationSeen =
  senderAccount.markSenderLegendCelebrationSeen;
exports.recordWebsiteVisit = senderAccount.recordWebsiteVisit;
exports.requestSenderEmailChange = senderAccount.requestSenderEmailChange;
exports.updateSenderLocation = senderAccount.updateSenderLocation;
exports.recordIrisLearningCandidate = senderAccount.recordIrisLearningCandidate;
exports.recordIrisLearningOutlier = senderAccount.recordIrisLearningOutlier;
exports.updateRiderProfile = riderAccount.updateRiderProfile;
exports.verifyRiderAccountAccess = riderAccount.verifyRiderAccountAccess;
exports.cleanupRiderDocumentChunks = riderAccount.cleanupRiderDocumentChunks;
exports.ensurePublicRiderId = riderAccount.ensurePublicRiderId;
exports.advanceRiderOnboarding = riderAccount.advanceRiderOnboarding;
exports.requestRiderEmailChange = riderAccount.requestRiderEmailChange;
exports.updateRiderPushToken = riderAccount.updateRiderPushToken;
exports.updateRiderNotificationState =
  riderAccount.updateRiderNotificationState;
exports.recordRiderJobDecision = riderAccount.recordRiderJobDecision;
exports.ensureRiderRothWallet = riderAccount.ensureRiderRothWallet;
exports.createWeightAdjustedNotification =
  riderAccount.createWeightAdjustedNotification;
exports.submitRiderApplication = riderAccount.submitRiderApplication;
exports.updateRiderApplicationSection =
  riderAccount.updateRiderApplicationSection;
exports.submitRiderDocument = riderAccount.submitRiderDocument;
exports.archiveExpiredDeliveries = deliveryCleanup.archiveExpiredDeliveries;
exports.resolveStaleDeliveryLock = staleDelivery.resolveStaleDeliveryLock;
exports.reconcileStaleDeliveryLocks = staleDelivery.reconcileStaleDeliveryLocks;

let stripeWebhookProcessor;
function normalStripeWebhookProcessor() {
  if (!stripeWebhookProcessor) {
    stripeWebhookProcessor = createStripeWebhookProcessor({
      stripe,
      resolveRuntimeConfig: () => resolveStripeRuntimeConfig({
        webhookSecret: stripeWebhookSecret.value(),
        requireWebhookSecret: true,
      }),
      assertEventMode: assertStripeEventMode,
      db: getFirestore(),
      messaging: getMessaging(),
      giftsPayment,
      ratingsTipping,
      stripeRefunds,
      senderBooking,
      businessPayments,
      healthPlus,
      healthMembershipLifecycle,
      rothLedger,
      routeCheckoutSessionCompleted,
      logger: console,
    });
  }
  return stripeWebhookProcessor;
}

exports.StripeWebhook = functions
    .runWith({secrets: [stripeWebhookSecret, "STRIPE_SECRET_KEY"]})
    .https.onRequest(async (req, res) => {
      try {
        const result = await normalStripeWebhookProcessor()({
          rawBody: req.rawBody,
          signature: req.headers["stripe-signature"],
          requestId: req.headers["x-cloud-trace-context"] || "",
        });
        return res.status(result.status).send(result.body);
      } catch (error) {
        console.error("stripe_webhook_processing_failed", {
          reason: error && error.message ? error.message : "internal_error",
        });
        return res.status(500).send({error: "Webhook processing failed"});
      }
    });

exports.RetrieveCardDetails = functions.https.onRequest(async (req, res) => {
  return res.status(410).json({
    error: "retired_card_details_endpoint",
    message: "Use listSenderPaymentMethods for authenticated payment method access.",
  });
});

exports.calculateEarnings = functions.https.onRequest(async (req, res) => {
  if (allowCors(req, res)) return;
  return res.status(410).send({
    error: "retired_rider_earnings_endpoint",
    message: "Use getRiderEarningsSummary for authenticated Rider earnings access.",
  });
});

exports.endTrip = functions.https.onRequest(async (req, res) => {
  if (allowCors(req, res)) return;
  return res.status(410).send({
    error: "retired_delivery_completion_endpoint",
    message: "Use updateDeliveryTrackingStatus for backend-authoritative delivery completion.",
  });
});

exports.reconcileBusinessInvoiceCheckouts = businessPayments.reconcileBusinessInvoiceCheckouts(stripe);

// Private QA namespace only; no Stripe SDK, dispatch or notification side effects.
const qaLifecycle = require("./qa-lifecycle");
exports.qaLifecycleFixture = qaLifecycle.callable();
exports.expireQaLifecycleFixtures = qaLifecycle.scheduled();

const qaSpecialFlow = require("./qa-special-flow");
exports.qaSpecialFlowFixture = qaSpecialFlow.callable();
exports.expireQaSpecialFlowFixtures = qaSpecialFlow.scheduled();
