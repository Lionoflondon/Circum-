/* eslint-disable max-len, require-jsdoc */
const {initializeApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const functions = require("firebase-functions/v1");
const {defineSecret} = require("firebase-functions/params");
const stripeConfig = functions.config().stripe || {};
const stripeWebhookSecret = defineSecret("STRIPE_WEBHOOK_SECRET");
const {
  assertStripeEventMode,
  resolveStripeRuntimeConfig,
} = require("./stripe-config");
let cachedStripeRuntimeConfig = null;
let cachedStripe = null;

function getStripeRuntimeConfig() {
  if (!cachedStripeRuntimeConfig) {
    cachedStripeRuntimeConfig = resolveStripeRuntimeConfig({
      config: stripeConfig,
    });
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
const iris = require("./iris");
const irisPhotoAnalysis = require("./iris-photo-analysis");
const deliveryAdjustments = require("./delivery-adjustments");
const platformNotifications = require("./platform-notifications");
const legends = require("./legends");
const giftsPayment = require("./gifts-payment");
const communicationEngine = require("./communication-engine");
const deliveryPolicy = require("./delivery-policy");
const deliveryTracking = require("./delivery-tracking");
const deliveryCompletedEvent = require("./delivery-completed-event");
const deliveryEvidence = require("./delivery-evidence");
const deliveryEvidenceMedia = require("./delivery-evidence-media");
const scheduledRoadChargeRefunds = require("./scheduled-road-charge-refunds");
const ratingsTipping = require("./ratings-tipping");
const stripeRefunds = require("./stripe-refunds");
const riderEarningsSummary = require("./rider-earnings-summary");
const founderRiderAccess = require("./founder-rider-access");
const founderAuthority = require("./founder-authority");
const healthPlusOperations = require("./health-plus-operations");
const rothLedger = require("./roth-ledger");
const businessPayments = require("./business-payments");
const riderConnect = require("./rider-connect");
const senderTrust = require("./sender-trust");
const referrals = require("./referrals");
const movementLedger = require("./movement-ledger");
const movementTimeline = require("./movement-timeline");
const deliveryEventProjections = require("./delivery-event-projections");
const deliveryWatchdog = require("./delivery-watchdog");
const marketplaceIntelligence = require("./marketplace-intelligence");
const giftStoryAutomation = require("./gift-story-automation");
const riderPresence = require("./rider-presence");
const freeAddressSearch = require("./free-address-search");
const senderBooking = require("./sender-booking");
const senderFinance = require("./sender-finance");
const senderSavedAddresses = require("./sender-saved-addresses");
const senderAccount = require("./sender-account");
const riderAccount = require("./rider-account");
const deliveryCleanup = require("./delivery-cleanup");
const staleDelivery = require("./stale-delivery");
const accountClosure = require("./account-closure");
const businessAccess = require("./business-access");
const businessOperations = require("./business-operations");
const riderIrisAcknowledgement = require("./rider-iris-acknowledgement");
const adminIrisReferenceImages = require("./admin-iris-reference-images");
const adminRiderAuthority = require("./admin-rider-authority");
const adminGovernance = require("./admin-governance");
const adminOperationsAuthority = require("./admin-operations-authority");
const operationsHealthCentre = require("./operations-health-centre");
const legacyFinancialEndpoints = require("./legacy-financial-endpoints");
const {routeCheckoutSessionCompleted} = require("./checkout-session-router");

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
exports.cleanupExpiredGiftVoiceDrafts =
  giftsPayment.cleanupExpiredGiftVoiceDrafts;
exports.onGiftRequestVoiceMediaDeleted =
  giftsPayment.onGiftRequestVoiceMediaDeleted;
exports.recordRiderArrival = deliveryPolicy.recordRiderArrival;
exports.reportWaitingContext = deliveryPolicy.reportWaitingContext;
exports.markRiderNoShow = deliveryPolicy.markRiderNoShow;
exports.cancelDelivery = deliveryPolicy.requestSenderCancellation;
exports.updateDeliveryTrackingStatus =
  deliveryTracking.updateDeliveryTrackingStatus;
exports.completeDelivery = deliveryTracking.completeDelivery;
exports.updateDeliveryLiveLocation =
  deliveryTracking.updateDeliveryLiveLocation;
exports.onDeliveryCompletedEvent =
  deliveryCompletedEvent.onDeliveryCompletedEvent;
exports.recordDeliveryEvidence = deliveryEvidence.recordDeliveryEvidence;
exports.onDeliveryEvidencePhotoFinalized =
  deliveryEvidenceMedia.onDeliveryEvidencePhotoFinalized;
exports.settleScheduledRoadChargeCashRefund =
  scheduledRoadChargeRefunds.settleScheduledRoadChargeCashRefund;
exports.submitDeliveryRating = ratingsTipping.submitDeliveryRating;
exports.submitDeliveryTip = ratingsTipping.submitDeliveryTip(stripe);

exports.getRiderEarningsSummary =
  riderEarningsSummary.getRiderEarningsSummary();
exports.adminReconcileRiderEarnings = riderEarningsSummary.adminReconcileRiderEarnings();
exports.scheduledRiderEarningsReconciliation = riderEarningsSummary.scheduledRiderEarningsReconciliation;
exports.setFounderRiderAccess = founderRiderAccess.setFounderRiderAccess();
exports.founderDesignateTestAccount =
  founderAuthority.founderDesignateTestAccount();
exports.founderRevokeTestAccount =
  founderAuthority.founderRevokeTestAccount();
exports.founderListTestAccounts =
  founderAuthority.founderListTestAccounts();
exports.founderPreflightE2E =
  founderAuthority.founderPreflightE2E();
exports.founderRiderOperationalPreflight =
  founderAuthority.founderRiderOperationalPreflight();
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
exports.adminCreateBusinessInvoice =
  businessPayments.adminCreateBusinessInvoice;
exports.createBusinessInvoiceCheckout =
  businessPayments.createBusinessInvoiceCheckout(stripe);
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
exports.getBusinessOperationsWorkspace =
  businessOperations.getBusinessOperationsWorkspace;
exports.getBusinessDeliveryTimeline =
  businessOperations.getBusinessDeliveryTimeline;
exports.createStripeConnectAccountForRider =
  riderConnect.createStripeConnectAccountForRider(stripeConnectClient);
exports.createStripeOnboardingLink =
  riderConnect.createStripeOnboardingLink(stripeConnectClient);
exports.refreshStripeOnboardingLink =
  riderConnect.refreshStripeOnboardingLink(stripeConnectClient);
exports.syncStripeConnectStatus =
  riderConnect.syncStripeConnectStatus(stripeConnectClient);
exports.riderPayoutReadiness = riderConnect.riderPayoutReadiness();
exports.createRiderTransferOrPayout =
  riderConnect.createRiderTransferOrPayout(stripeConnectClient);
exports.requestRiderWithdrawal = riderConnect.requestRiderWithdrawal();
exports.cancelRiderWithdrawal = riderConnect.cancelRiderWithdrawal();
exports.adminReviewRiderWithdrawal = riderConnect.adminReviewRiderWithdrawal();
exports.adminReviewRider = adminRiderAuthority.adminReviewRider;
exports.adminRepairCanonicalRider =
  adminRiderAuthority.adminRepairCanonicalRider;
exports.adminGovernanceAction = adminGovernance.adminGovernanceAction;
exports.adminResolveAccess = adminOperationsAuthority.adminResolveAccess;
exports.adminRecordAuditEntry = adminOperationsAuthority.adminRecordAuditEntry;
exports.adminSaveAdminUser = adminOperationsAuthority.adminSaveAdminUser;
exports.adminDuplicateDelivery = adminOperationsAuthority.adminDuplicateDelivery;
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
exports.pipelineHealthReset = deliveryCleanup.pipelineHealthReset();
exports.operationsHealthScan =
  operationsHealthCentre.operationsHealthScan();
exports.operationsHealthRepair =
  operationsHealthCentre.operationsHealthRepair();
exports.liveDeliveryDiagnostics =
  operationsHealthCentre.liveDeliveryDiagnostics();
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
exports.onNotificationOperationalWrite = deliveryEventProjections.onNotificationOperationalWrite;
exports.onChatOperationalCreate = deliveryEventProjections.onChatOperationalCreate;
exports.onChatMessageOperationalCreate = deliveryEventProjections.onChatMessageOperationalCreate;
exports.onDeliveryEvidenceOperationalWrite = deliveryEventProjections.onDeliveryEvidenceOperationalWrite;
exports.deliveryLifecycleWatchdog = deliveryWatchdog.deliveryLifecycleWatchdog;
exports.acknowledgeOperationalIncident = deliveryWatchdog.acknowledgeOperationalIncident;
exports.resolveOperationalIncident = deliveryWatchdog.resolveOperationalIncident;
exports.onDeliveryIntelligenceEventCreate = marketplaceIntelligence.onDeliveryIntelligenceEventCreate;
exports.onDeliveryLocationRiskWrite = marketplaceIntelligence.onDeliveryLocationRiskWrite;
exports.onDeliveryDisputeIntelligenceCreate = marketplaceIntelligence.onDeliveryDisputeIntelligenceCreate;
exports.onDriverRatingIntelligenceCreate = marketplaceIntelligence.onDriverRatingIntelligenceCreate;
exports.onMarketplaceRiskFlagCreate = marketplaceIntelligence.onMarketplaceRiskFlagCreate;
exports.reviewMarketplaceRiskFlag = marketplaceIntelligence.reviewMarketplaceRiskFlag;
exports.onDeliveryLiveLocationWrite =
  movementTimeline.onDeliveryLiveLocationWrite;
exports.onGiftDeliveryCompleted = giftStoryAutomation.onGiftDeliveryCompleted;
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
exports.requestSenderCancellation = deliveryPolicy.requestSenderCancellation;
exports.previewSenderCancellation = deliveryPolicy.previewSenderCancellation;
exports.recordArrivalZoneCheck = deliveryPolicy.recordArrivalZoneCheck;
exports.recordCustomerArrivalResponse =
  deliveryPolicy.recordCustomerArrivalResponse;
exports.goOnline = riderPresence.goOnline;
exports.goOffline = riderPresence.goOffline;
exports.updateRiderPresence = riderPresence.updateRiderPresence;
exports.onDeliveryPresenceWrite = riderPresence.onDeliveryPresenceWrite;
exports.onRiderRecordAvailabilityWrite =
  riderPresence.onRiderRecordAvailabilityWrite;
exports.onRiderProfileAvailabilityWrite =
  riderPresence.onRiderProfileAvailabilityWrite;
exports.markStaleRiderPresenceOffline =
  riderPresence.markStaleRiderPresenceOffline;
exports.searchFreeUkAddresses = freeAddressSearch.searchFreeUkAddresses;
exports.resolveUkAddressPlace = freeAddressSearch.resolveUkAddressPlace;
exports.getSenderRothBalance = senderBooking.getSenderRothBalance;
exports.createSenderBookingQuote = senderBooking.createSenderBookingQuote;
exports.createSenderPaymentSession =
  senderBooking.createSenderPaymentSession(stripe);
exports.createSenderPaidDelivery =
  senderBooking.createSenderPaidDelivery(stripe);
exports.finalizeSenderWebCheckout =
  senderBooking.finalizeSenderWebCheckout(stripe);
exports.recoverIneligibleSenderDelivery =
  senderBooking.recoverIneligibleSenderDelivery;
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
exports.purgeFounderTestPipeline = deliveryCleanup.purgeFounderTestPipeline();
exports.resolveStaleDeliveryLock = staleDelivery.resolveStaleDeliveryLock;
exports.reconcileStaleDeliveryLocks = staleDelivery.reconcileStaleDeliveryLocks;

exports.StripeWebhook = functions
    .runWith({secrets: [stripeWebhookSecret]})
    .https.onRequest(async (req, res) => {
      const sig = req.headers["stripe-signature"];
      // console.log(sig);

      let webhookRuntimeConfig;
      try {
        webhookRuntimeConfig = resolveStripeRuntimeConfig({
          config: stripeConfig,
          webhookSecret: stripeWebhookSecret.value(),
          requireWebhookSecret: true,
        });
      } catch (error) {
        console.error("Stripe webhook configuration failed closed", {
          mode: webhookRuntimeConfig && webhookRuntimeConfig.mode,
          firebaseProject:
            webhookRuntimeConfig && webhookRuntimeConfig.firebaseProject,
          reason:
          error && error.message ? error.message : "invalid_configuration",
        });
        return res
            .status(500)
            .send({error: "Stripe webhook secret is not configured"});
      }

      let event;
      try {
        event = getStripeClient().webhooks.constructEvent(
            req.rawBody,
            sig,
            webhookRuntimeConfig.webhookSecret,
        );
        assertStripeEventMode(event, webhookRuntimeConfig);
      } catch (err) {
        console.error(
            "Stripe webhook signature verification failed:",
            err.message,
        );
        return res
            .status(400)
            .send({error: "Invalid Stripe webhook signature"});
      }

      console.log("💰 Webhook working!");
      console.log(`Event: ${event.type}`);

      if (event.type === "charge.refunded") {
        const refundResult = await stripeRefunds.syncChargeRefund({
          db: getFirestore(),
          event,
        });
        return res.send({success: true, refund: refundResult});
      }

      if (
        event.type === "payment_intent.succeeded" ||
      event.type === "payment_intent.processing" ||
      event.type === "payment_intent.payment_failed" ||
      event.type === "payment_intent.canceled"
      ) {
        const tipResult = await ratingsTipping.processStripeTipIntent(
            stripe,
            event.data.object,
        );
        if (tipResult && tipResult.handled) {
          return res.send({success: true, tip: tipResult});
        }
        try {
          const senderIntentResult =
            await senderBooking.handleSenderPaymentIntent(
                stripe,
                event.data.object,
                event.id,
            );
          if (senderIntentResult && senderIntentResult.handled) {
            return res.send({success: true, sender: senderIntentResult});
          }
        } catch (error) {
          console.error("Sender PaymentIntent webhook finalization failed", {
            eventId: event.id,
            paymentIntentId:
              event.data && event.data.object ? event.data.object.id : null,
            status:
              event.data && event.data.object ? event.data.object.status : null,
            error: error && error.message ? error.message : error,
          });
          return res
              .status(500)
              .send({success: false, error: "sender_payment_intent_failed"});
        }
      }

      if (event.type == "checkout.session.completed") {
        console.log("💰 Payment completed!");
        const sessionData = event.data.object;
        const metadata = sessionData.metadata || {};

        try {
          await routeCheckoutSessionCompleted(sessionData, event.id, {
            businessPayments,
            giftsPayment,
            healthPlus,
            rothLedger,
            senderBooking: {
              handleSenderCheckoutSession:
                (session, eventId) =>
                  senderBooking.handleSenderCheckoutSession(
                      stripe,
                      session,
                      eventId,
                  ),
            },
            logger: console,
          });
        } catch (error) {
          console.error("Stripe checkout session finalization failed", {
            eventId: event.id,
            sessionId: sessionData && sessionData.id ? sessionData.id : null,
            metadataType: metadata.type || null,
            purchaseRequestId: metadata.purchaseRequestId || null,
            paymentIntentId:
            sessionData && sessionData.payment_intent ?
              sessionData.payment_intent :
              null,
            error: error && error.message ? error.message : error,
          });
          return res
              .status(500)
              .send({success: false, error: "checkout_finalization_failed"});
        }
      }

      res.send({success: true});
    });

exports.RetrieveCardDetails = legacyFinancialEndpoints.retrieveCardDetails(stripe);
exports.calculateEarnings = legacyFinancialEndpoints.calculateEarnings();

exports.endTrip = functions.https.onRequest(async (req, res) => {
  if (allowCors(req, res)) return;
  return res.status(410).send({
    error: "retired_delivery_completion_endpoint",
    message: "Use updateDeliveryTrackingStatus for backend-authoritative delivery completion.",
  });
});
