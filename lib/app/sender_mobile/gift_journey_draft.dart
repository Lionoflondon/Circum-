import '../gifts/gift_system_policy.dart';
import '../send_package/models/suggestions.m.dart';

enum SenderGiftMode {
  someone,
  myself,
  anonymous,
  campaign,
}

const senderGiftModeFieldName = 'giftMode';
const senderGiftAnonymousGiftTypeFieldName = 'anonymousGiftType';
const senderGiftSenderRevealModeFieldName = 'senderRevealMode';
const senderGiftSelfGiftFrequencyFieldName = 'selfGiftFrequency';
const senderGiftCampaignIdFieldName = 'campaignId';
const senderGiftCampaignNameFieldName = 'campaignName';
const senderGiftIrisSuggestionFieldName = 'irisSuggestion';
const senderGiftPendingIrisSuggestion = 'Pending IRIS gift recommendation';
const senderGiftPaymentDraftCollectionName = 'giftPaymentDrafts';
const senderGiftAdminReviewCollectionName = 'giftRequests';
const senderGiftPaymentCallableName = 'createGiftPayment';
const senderGiftRothBalanceCallableName = 'getSenderRothBalance';
const senderGiftIrisUnsupportedCopy =
    'IRIS’s real catalog only tags gift signals for Beauty/Fashion. None of your selected themes fall in that range, so there’s nothing to suggest yet.';
const senderGiftIrisPartialUnsupportedCopy =
    'No IRIS coverage yet for some themes.';

const senderGiftIrisSignalMap = {
  'Fashion': 'fashionInterest',
  'Beauty': 'beautyInterest',
  'Makeup': 'beautyInterest',
  'Skincare': 'skincareInterest',
  'Fragrance': 'fragranceInterest',
  'Jewellery': 'jewelleryInterest',
};

const senderGiftRevealModeOptions = {
  'anonymous_forever': 'Stay anonymous',
  'reveal_after_delivery': 'Reveal after delivery',
  'reveal_immediately': 'Reveal immediately',
};

const senderGiftSelfFrequencyOptions = {
  'one_off': 'One-off',
  'monthly': 'Monthly',
  'quarterly': 'Quarterly',
  'custom': 'Custom',
};

const senderGiftBudgetOptions = [50, 100, 250, 500, 1000, 1500];

List<String> senderGiftIrisSignalsForThemes(Iterable<String> themes) {
  return themes
      .map((theme) => senderGiftIrisSignalMap[theme.trim()])
      .whereType<String>()
      .toSet()
      .toList();
}

List<String> senderGiftUnsupportedIrisThemes(Iterable<String> themes) {
  return themes
      .where((theme) =>
          theme.trim().isNotEmpty &&
          !senderGiftIrisSignalMap.containsKey(theme.trim()))
      .toSet()
      .toList();
}

class SenderGiftBriefPreview {
  final String emotionalDirection;
  final String experienceDirection;
  final String thingsToAvoid;
  final String confidence;
  final bool humanReviewRequired;

  const SenderGiftBriefPreview({
    required this.emotionalDirection,
    required this.experienceDirection,
    required this.thingsToAvoid,
    required this.confidence,
    required this.humanReviewRequired,
  });
}

class SenderGiftTheme {
  final String label;
  final String source;
  final bool knownToIris;

  const SenderGiftTheme({
    required this.label,
    required this.source,
    required this.knownToIris,
  });

  factory SenderGiftTheme.catalogue(String label) {
    return SenderGiftTheme(
      label: label.trim(),
      source: 'catalogue',
      knownToIris: senderGiftIrisSignalMap.containsKey(label.trim()),
    );
  }

  factory SenderGiftTheme.custom(String label) {
    return SenderGiftTheme(
      label: label.trim(),
      source: 'custom',
      knownToIris: false,
    );
  }

  Map<String, Object?> toMap() => {
        'label': label,
        'source': source,
        'knownToIris': knownToIris,
      };
}

class SenderGiftVoiceNote {
  final bool hasVoiceNote;
  final int durationSeconds;
  final String? localUrl;
  final String? localPath;
  final String? storagePath;
  final String? downloadUrl;
  final DateTime createdAt;
  final String? transcript;
  final String? language;

  const SenderGiftVoiceNote({
    required this.hasVoiceNote,
    required this.durationSeconds,
    this.localUrl,
    this.localPath,
    this.storagePath,
    this.downloadUrl,
    required this.createdAt,
    this.transcript,
    this.language,
  });

  Map<String, Object?> toMap() => {
        'hasVoiceNote': hasVoiceNote,
        'durationSeconds': durationSeconds,
        'localUrl': localUrl ?? localPath,
        'localPath': localPath ?? localUrl,
        'storagePath': storagePath,
        'downloadUrl': downloadUrl,
        'createdAt': createdAt.toIso8601String(),
        'transcript': transcript,
        'language': language,
      };
}

class SenderGiftIrisBrief {
  final String emotionalDirection;
  final String experienceDirection;
  final String thingsToAvoid;
  final List<String> catalogueCoverage;
  final String confidence;
  final int personalisationScore;
  final String allergySafetyNotes;
  final List<String> recommendedPartnerCategories;
  final DateTime createdAt;

  const SenderGiftIrisBrief({
    required this.emotionalDirection,
    required this.experienceDirection,
    required this.thingsToAvoid,
    required this.catalogueCoverage,
    required this.confidence,
    required this.personalisationScore,
    required this.allergySafetyNotes,
    required this.recommendedPartnerCategories,
    required this.createdAt,
  });

  Map<String, Object?> toMap() => {
        'emotionalDirection': emotionalDirection,
        'experienceDirection': experienceDirection,
        'thingsToAvoid': thingsToAvoid,
        'catalogueCoverage': catalogueCoverage,
        'confidence': confidence,
        'personalisationScore': personalisationScore,
        'allergySafetyNotes': allergySafetyNotes,
        'recommendedPartnerCategories': recommendedPartnerCategories,
        'createdAt': createdAt.toIso8601String(),
      };
}

const senderGiftInterestOptions = [
  'Fashion',
  'Beauty',
  'Makeup',
  'Skincare',
  'Tech',
  'Gaming',
  'Gym',
  'Travel',
  'Books',
  'Food',
  'Cooking',
  'Coffee',
  'Tea',
  'Christian',
  'Muslim',
  'Jewish',
  'Spiritual',
  'Charity',
  'Aviation',
  'Music',
  'Luxury',
  'Minimalist',
  'Home Decor',
  'Fragrance',
  'Art',
  'Design',
  'Architecture',
  'Gardening',
  'Film',
  'Theatre',
  'Sports',
  'Football',
  'Running',
  'Cycling',
  'Swimming',
  'Photography',
  'Cars',
  'Motorcycles',
  'Jewellery',
  'Watches',
  'Writing',
  'Animals',
  'Nature',
  'Sustainability',
  'Collectibles',
  'Restaurants',
  'Fine Dining',
  'Michelin Dining',
  'Street Food',
  'Brunch',
  'Afternoon Tea',
  'Luxury Travel',
  'City Breaks',
  'Adventure Travel',
  'Cruises',
  'Hotels',
  'Spa Experiences',
  'Wellness Retreats',
  'Luxury Fashion',
  'Streetwear',
  'Handbags',
  'Sneakers',
  'Interior Design',
  'Home Fragrance',
  'Musicals',
  'Opera',
  'Live Music',
  'Festivals',
  'Cinema',
  'TV & Streaming',
  'Business',
  'Entrepreneurship',
  'Investing',
  'Startups',
  'Personal Development',
  'Leadership',
  'Wine Appreciation',
  'Whisky Appreciation',
  'Craft Beverages',
];

class GiftJourneyDraft {
  final SenderGiftMode mode;
  final String? recipientName;
  final String? relationship;
  final String? occasion;
  final String? recipientPhone;
  final String? recipientEmail;
  final String? notes;
  final String? deliveryAddress;
  final Suggestion? deliveryAddressData;
  final String? deliveryDate;
  final String? deliveryTimeWindow;
  final bool flexibleDelivery;
  final String? personalMessage;
  final List<String> interests;
  final String? customInterest;
  final List<SenderGiftTheme> giftThemes;
  final SenderGiftVoiceNote? voiceNote;
  final SenderGiftIrisBrief? irisGiftBrief;
  final String? clothingSize;
  final String? shoeSize;
  final String? ringSize;
  final String? favouriteColours;
  final String? likedBrands;
  final List<String> preferredStyles;
  final String? foodAllergies;
  final String? medicalAllergies;
  final String? dietaryRestrictions;
  final String? culturalConsiderations;
  final String? safetyThingsToAvoid;
  final String? giftTeamNotes;
  final String? senderRevealMode;
  final String? selfGiftFrequency;
  final bool allowCircumSocialUse;
  final bool allowBrandTagging;
  final bool allowPublicPosting;
  final String? recipientContentConsent;
  final String? campaignId;
  final String? campaignName;
  final String? campaignType;
  final String? campaignTagline;
  final double? campaignCompatibilityScore;
  final String? campaignMatchSummary;
  final String? campaignParticipantId;
  final String? giftRequestId;
  final String? giftDeliveryId;
  final String? linkedGiftDeliveryStatus;
  final bool riderCompletionAccepted;
  final bool deliveryVerificationCompleted;
  final bool deliveryAuditSuccessful;
  final bool activeDeliveryDispute;
  final bool giftStoryAdminOverride;
  final String? giftStoryAdminUserId;
  final String? giftStoryAdminOverrideReason;
  final String? giftStoryAdminOverrideAt;
  final String? giftStoryPreviousStatus;
  final String? giftStoryOverrideType;
  final double budget;

  const GiftJourneyDraft({
    required this.mode,
    this.recipientName,
    this.relationship,
    this.occasion,
    this.recipientPhone,
    this.recipientEmail,
    this.notes,
    this.deliveryAddress,
    this.deliveryAddressData,
    this.deliveryDate,
    this.deliveryTimeWindow,
    this.flexibleDelivery = false,
    this.personalMessage,
    this.interests = const [],
    this.customInterest,
    this.giftThemes = const [],
    this.voiceNote,
    this.irisGiftBrief,
    this.clothingSize,
    this.shoeSize,
    this.ringSize,
    this.favouriteColours,
    this.likedBrands,
    this.preferredStyles = const [],
    this.foodAllergies,
    this.medicalAllergies,
    this.dietaryRestrictions,
    this.culturalConsiderations,
    this.safetyThingsToAvoid,
    this.giftTeamNotes,
    this.senderRevealMode,
    this.selfGiftFrequency,
    this.allowCircumSocialUse = false,
    this.allowBrandTagging = false,
    this.allowPublicPosting = false,
    this.recipientContentConsent,
    this.campaignId,
    this.campaignName,
    this.campaignType,
    this.campaignTagline,
    this.campaignCompatibilityScore,
    this.campaignMatchSummary,
    this.campaignParticipantId,
    this.giftRequestId,
    this.giftDeliveryId,
    this.linkedGiftDeliveryStatus,
    this.riderCompletionAccepted = false,
    this.deliveryVerificationCompleted = false,
    this.deliveryAuditSuccessful = false,
    this.activeDeliveryDispute = false,
    this.giftStoryAdminOverride = false,
    this.giftStoryAdminUserId,
    this.giftStoryAdminOverrideReason,
    this.giftStoryAdminOverrideAt,
    this.giftStoryPreviousStatus,
    this.giftStoryOverrideType,
    this.budget = 100,
  });

  factory GiftJourneyDraft.forMode(SenderGiftMode mode) {
    return GiftJourneyDraft(
      mode: mode,
      relationship: switch (mode) {
        SenderGiftMode.myself => 'Myself',
        SenderGiftMode.anonymous => 'Anonymous Recipient',
        SenderGiftMode.campaign => 'Community Member',
        SenderGiftMode.someone => null,
      },
      occasion: mode == SenderGiftMode.campaign ? 'Community Campaign' : null,
      recipientName: mode == SenderGiftMode.myself ? 'Myself' : null,
      senderRevealMode:
          mode == SenderGiftMode.anonymous || mode == SenderGiftMode.campaign
              ? 'anonymous_forever'
              : 'reveal_immediately',
      selfGiftFrequency: mode == SenderGiftMode.myself ? 'one_off' : null,
    );
  }

  String get giftModeValue => switch (mode) {
        SenderGiftMode.someone => 'gift_someone',
        SenderGiftMode.myself => 'gift_myself',
        SenderGiftMode.anonymous => 'anonymous_gift',
        SenderGiftMode.campaign => 'anonymous_gift',
      };

  String? get anonymousGiftType => switch (mode) {
        SenderGiftMode.anonymous => 'direct',
        SenderGiftMode.campaign => 'campaign',
        _ => null,
      };

  String get modeLabel => switch (mode) {
        SenderGiftMode.someone => 'Gift someone',
        SenderGiftMode.myself => 'Gift myself',
        SenderGiftMode.anonymous => 'Anonymous gift',
        SenderGiftMode.campaign => 'Campaign',
      };

  bool get giftStoryUnlocked {
    if (_hasAuditedManualLock) return false;
    if (_hasAuditedManualUnlock) return true;
    return linkedGiftDeliveryStatus == 'delivered' &&
        riderCompletionAccepted &&
        deliveryVerificationCompleted &&
        deliveryAuditSuccessful &&
        !activeDeliveryDispute;
  }

  String get giftStoryStatus => giftStoryUnlocked ? 'unlocked' : 'locked';

  bool get giftStoryManuallyLocked => _hasAuditedManualLock;

  bool get _hasAuditedManualUnlock =>
      giftStoryOverrideType == 'manual_unlock' && _hasCompleteOverrideAudit;

  bool get _hasAuditedManualLock =>
      giftStoryOverrideType == 'manual_lock' && _hasCompleteOverrideAudit;

  bool get _hasCompleteOverrideAudit =>
      (giftStoryAdminUserId ?? '').trim().isNotEmpty &&
      (giftStoryAdminOverrideReason ?? '').trim().isNotEmpty &&
      (giftStoryAdminOverrideAt ?? '').trim().isNotEmpty &&
      (giftStoryPreviousStatus ?? '').trim().isNotEmpty;

  SenderGiftBriefPreview get giftBriefPreview {
    if (irisGiftBrief != null) {
      return SenderGiftBriefPreview(
        emotionalDirection: irisGiftBrief!.emotionalDirection,
        experienceDirection: irisGiftBrief!.experienceDirection,
        thingsToAvoid: irisGiftBrief!.thingsToAvoid,
        confidence: irisGiftBrief!.confidence,
        humanReviewRequired: irisGiftBrief!.confidence == 'Needs review' ||
            irisGiftBrief!.catalogueCoverage.isEmpty,
      );
    }
    final selectedInterests = giftThemeLabels;
    final signals = senderGiftIrisSignalsForThemes(selectedInterests);
    final unsupported = senderGiftUnsupportedIrisThemes(selectedInterests);
    final hasRelationship = (relationship ?? '').trim().isNotEmpty;
    final hasOccasion = (occasion ?? '').trim().isNotEmpty;
    final hasNotes = (notes ?? '').trim().isNotEmpty;
    final confidenceScore = 42 +
        (hasRelationship ? 10 : 0) +
        (hasOccasion ? 10 : 0) +
        (hasNotes ? 12 : 0) +
        ((personalMessage ?? '').trim().isNotEmpty ? 8 : 0) +
        (selectedInterests.isNotEmpty ? 8 : 0) +
        ((likedBrands ?? '').trim().isNotEmpty ? 3 : 0) +
        ((favouriteColours ?? '').trim().isNotEmpty ? 3 : 0);
    final humanReview =
        confidenceScore < 70 || unsupported.isNotEmpty || !hasNotes;
    return SenderGiftBriefPreview(
      emotionalDirection: hasOccasion
          ? 'Shape a ${occasion!.toLowerCase()} gift around ${relationship ?? 'the relationship'}.'
          : 'Shape a warm, relationship-led gift experience.',
      experienceDirection: signals.isEmpty
          ? 'Thoughtful concierge curation before product selection.'
          : 'Supported IRIS signals: ${signals.join(' · ')}.',
      thingsToAvoid: unsupported.isEmpty
          ? 'Avoid product assumptions until the Gifts Team reviews the request.'
          : 'Avoid unsupported catalogue guesses for ${unsupported.join(', ')}.',
      confidence: confidenceScore >= 82
          ? 'High'
          : confidenceScore >= 70
              ? 'Medium'
              : 'Needs review',
      humanReviewRequired: humanReview,
    );
  }

  List<String> get giftThemeLabels {
    if (giftThemes.isNotEmpty) {
      return giftThemes.map((theme) => theme.label).toList();
    }
    return {
      ...interests,
      if ((customInterest ?? '').trim().isNotEmpty) customInterest!.trim(),
    }.toList();
  }

  List<SenderGiftTheme> get normalizedGiftThemes {
    if (giftThemes.isNotEmpty) return giftThemes;
    return [
      for (final interest in interests)
        if (interest.trim().isNotEmpty) SenderGiftTheme.catalogue(interest),
      if ((customInterest ?? '').trim().isNotEmpty)
        SenderGiftTheme.custom(customInterest!.trim()),
    ];
  }

  String get safetySummary {
    final parts = [
      if ((foodAllergies ?? '').trim().isNotEmpty)
        'Food allergies: ${foodAllergies!.trim()}',
      if ((medicalAllergies ?? '').trim().isNotEmpty)
        'Medical allergies: ${medicalAllergies!.trim()}',
      if ((dietaryRestrictions ?? '').trim().isNotEmpty)
        'Dietary restrictions: ${dietaryRestrictions!.trim()}',
      if ((culturalConsiderations ?? '').trim().isNotEmpty)
        'Religious or cultural considerations: ${culturalConsiderations!.trim()}',
      if ((safetyThingsToAvoid ?? '').trim().isNotEmpty)
        'Things to avoid: ${safetyThingsToAvoid!.trim()}',
      if ((giftTeamNotes ?? '').trim().isNotEmpty)
        'Anything else: ${giftTeamNotes!.trim()}',
    ];
    return parts.isEmpty
        ? 'No allergies, restrictions, or safety notes supplied.'
        : parts.join('\n');
  }

  SenderGiftIrisBrief generateIrisBrief() {
    final themes = normalizedGiftThemes;
    final labels = themes.map((theme) => theme.label).toList();
    final signals = senderGiftIrisSignalsForThemes(labels);
    final unsupported = themes
        .where((theme) => !theme.knownToIris)
        .map((theme) => theme.label)
        .toList();
    final hasNotes = (notes ?? '').trim().isNotEmpty;
    final hasSafetyNotes = safetySummary !=
        'No allergies, restrictions, or safety notes supplied.';
    final hasMessage = (personalMessage ?? '').trim().isNotEmpty;
    final hasVoice = voiceNote?.hasVoiceNote == true;
    final score = (52 +
            ((relationship ?? '').trim().isNotEmpty ? 8 : 0) +
            ((occasion ?? '').trim().isNotEmpty ? 8 : 0) +
            (hasNotes ? 12 : 0) +
            (hasMessage ? 8 : 0) +
            (hasVoice ? 6 : 0) +
            (themes.isNotEmpty ? 8 : 0) +
            ((likedBrands ?? '').trim().isNotEmpty ? 3 : 0) +
            ((favouriteColours ?? '').trim().isNotEmpty ? 3 : 0) +
            (preferredStyles.isNotEmpty ? 4 : 0) +
            (hasSafetyNotes ? 4 : 0))
        .clamp(0, 96);
    final confidence = score >= 82
        ? 'High'
        : score >= 70
            ? 'Medium'
            : 'Needs review';
    return SenderGiftIrisBrief(
      emotionalDirection:
          'Shape the experience around ${relationship ?? 'the relationship'} and ${occasion ?? 'the moment'}.',
      experienceDirection: signals.isEmpty
          ? 'Concierge-led curation using the personal context provided.'
          : 'Use supported IRIS gift signals: ${signals.join(' · ')}.',
      thingsToAvoid: [
        if (unsupported.isEmpty)
          'Avoid product assumptions until the Gifts Team reviews the request.'
        else
          'Do not treat ${unsupported.join(', ')} as catalogue-backed interests.',
        if (hasSafetyNotes) safetySummary,
      ].join('\n'),
      catalogueCoverage: signals,
      confidence: confidence,
      personalisationScore: score,
      allergySafetyNotes: safetySummary,
      recommendedPartnerCategories: signals.isEmpty
          ? const ['Concierge curation']
          : signals.map((signal) => signal.replaceAll('Interest', '')).toList(),
      createdAt: DateTime.now(),
    );
  }

  GiftJourneyDraft copyWith({
    String? recipientName,
    String? relationship,
    String? occasion,
    String? recipientPhone,
    String? recipientEmail,
    String? notes,
    String? deliveryAddress,
    Suggestion? deliveryAddressData,
    String? deliveryDate,
    String? deliveryTimeWindow,
    bool? flexibleDelivery,
    String? personalMessage,
    List<String>? interests,
    String? customInterest,
    List<SenderGiftTheme>? giftThemes,
    SenderGiftVoiceNote? voiceNote,
    bool clearVoiceNote = false,
    SenderGiftIrisBrief? irisGiftBrief,
    String? clothingSize,
    String? shoeSize,
    String? ringSize,
    String? favouriteColours,
    String? likedBrands,
    List<String>? preferredStyles,
    String? foodAllergies,
    String? medicalAllergies,
    String? dietaryRestrictions,
    String? culturalConsiderations,
    String? safetyThingsToAvoid,
    String? giftTeamNotes,
    String? senderRevealMode,
    String? selfGiftFrequency,
    bool? allowCircumSocialUse,
    bool? allowBrandTagging,
    bool? allowPublicPosting,
    String? recipientContentConsent,
    String? campaignId,
    String? campaignName,
    String? campaignType,
    String? campaignTagline,
    double? campaignCompatibilityScore,
    String? campaignMatchSummary,
    String? campaignParticipantId,
    String? giftRequestId,
    String? giftDeliveryId,
    String? linkedGiftDeliveryStatus,
    bool? riderCompletionAccepted,
    bool? deliveryVerificationCompleted,
    bool? deliveryAuditSuccessful,
    bool? activeDeliveryDispute,
    bool? giftStoryAdminOverride,
    String? giftStoryAdminUserId,
    String? giftStoryAdminOverrideReason,
    String? giftStoryAdminOverrideAt,
    String? giftStoryPreviousStatus,
    String? giftStoryOverrideType,
    double? budget,
  }) {
    return GiftJourneyDraft(
      mode: mode,
      recipientName: recipientName ?? this.recipientName,
      relationship: relationship ?? this.relationship,
      occasion: occasion ?? this.occasion,
      recipientPhone: recipientPhone ?? this.recipientPhone,
      recipientEmail: recipientEmail ?? this.recipientEmail,
      notes: notes ?? this.notes,
      deliveryAddress: deliveryAddress ?? this.deliveryAddress,
      deliveryAddressData: deliveryAddressData ?? this.deliveryAddressData,
      deliveryDate: deliveryDate ?? this.deliveryDate,
      deliveryTimeWindow: deliveryTimeWindow ?? this.deliveryTimeWindow,
      flexibleDelivery: flexibleDelivery ?? this.flexibleDelivery,
      personalMessage: personalMessage ?? this.personalMessage,
      interests: interests ?? this.interests,
      customInterest: customInterest ?? this.customInterest,
      giftThemes: giftThemes ?? this.giftThemes,
      voiceNote: clearVoiceNote ? null : voiceNote ?? this.voiceNote,
      irisGiftBrief: irisGiftBrief ?? this.irisGiftBrief,
      clothingSize: clothingSize ?? this.clothingSize,
      shoeSize: shoeSize ?? this.shoeSize,
      ringSize: ringSize ?? this.ringSize,
      favouriteColours: favouriteColours ?? this.favouriteColours,
      likedBrands: likedBrands ?? this.likedBrands,
      preferredStyles: preferredStyles ?? this.preferredStyles,
      foodAllergies: foodAllergies ?? this.foodAllergies,
      medicalAllergies: medicalAllergies ?? this.medicalAllergies,
      dietaryRestrictions: dietaryRestrictions ?? this.dietaryRestrictions,
      culturalConsiderations:
          culturalConsiderations ?? this.culturalConsiderations,
      safetyThingsToAvoid: safetyThingsToAvoid ?? this.safetyThingsToAvoid,
      giftTeamNotes: giftTeamNotes ?? this.giftTeamNotes,
      senderRevealMode: senderRevealMode ?? this.senderRevealMode,
      selfGiftFrequency: selfGiftFrequency ?? this.selfGiftFrequency,
      allowCircumSocialUse: allowCircumSocialUse ?? this.allowCircumSocialUse,
      allowBrandTagging: allowBrandTagging ?? this.allowBrandTagging,
      allowPublicPosting: allowPublicPosting ?? this.allowPublicPosting,
      recipientContentConsent:
          recipientContentConsent ?? this.recipientContentConsent,
      campaignId: campaignId ?? this.campaignId,
      campaignName: campaignName ?? this.campaignName,
      campaignType: campaignType ?? this.campaignType,
      campaignTagline: campaignTagline ?? this.campaignTagline,
      campaignCompatibilityScore:
          campaignCompatibilityScore ?? this.campaignCompatibilityScore,
      campaignMatchSummary: campaignMatchSummary ?? this.campaignMatchSummary,
      campaignParticipantId:
          campaignParticipantId ?? this.campaignParticipantId,
      giftRequestId: giftRequestId ?? this.giftRequestId,
      giftDeliveryId: giftDeliveryId ?? this.giftDeliveryId,
      linkedGiftDeliveryStatus:
          linkedGiftDeliveryStatus ?? this.linkedGiftDeliveryStatus,
      riderCompletionAccepted:
          riderCompletionAccepted ?? this.riderCompletionAccepted,
      deliveryVerificationCompleted:
          deliveryVerificationCompleted ?? this.deliveryVerificationCompleted,
      deliveryAuditSuccessful:
          deliveryAuditSuccessful ?? this.deliveryAuditSuccessful,
      activeDeliveryDispute:
          activeDeliveryDispute ?? this.activeDeliveryDispute,
      giftStoryAdminOverride:
          giftStoryAdminOverride ?? this.giftStoryAdminOverride,
      giftStoryAdminUserId: giftStoryAdminUserId ?? this.giftStoryAdminUserId,
      giftStoryAdminOverrideReason:
          giftStoryAdminOverrideReason ?? this.giftStoryAdminOverrideReason,
      giftStoryAdminOverrideAt:
          giftStoryAdminOverrideAt ?? this.giftStoryAdminOverrideAt,
      giftStoryPreviousStatus:
          giftStoryPreviousStatus ?? this.giftStoryPreviousStatus,
      giftStoryOverrideType:
          giftStoryOverrideType ?? this.giftStoryOverrideType,
      budget: budget ?? this.budget,
    );
  }

  Map<String, Object?> adminReviewPayload({
    required String senderId,
    required String senderEmail,
    String? senderName,
  }) {
    final themes = normalizedGiftThemes;
    final selectedInterests = giftThemeLabels;
    final brief = irisGiftBrief ?? generateIrisBrief();
    final giftType = mode == SenderGiftMode.campaign
        ? GiftSystemPolicy.campaignGiftType
        : GiftSystemPolicy.normalGiftType;
    return {
      'senderId': senderId,
      'senderName': senderName ?? '',
      'senderEmail': senderEmail.toLowerCase(),
      ...GiftSystemPolicy.progressPatch(
        userId: senderId,
        email: senderEmail,
        giftType: giftType,
        flowStatus: 'submitted',
        currentStep: 13,
        completedSteps: const [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
        paymentStatus: 'payment_pending',
        deliveryStatus: linkedGiftDeliveryStatus ?? 'not_started',
        storyStatus: giftStoryStatus,
        updatedAt: DateTime.now().toUtc().toIso8601String(),
      ),
      'recipientName': recipientName?.trim() ?? '',
      'recipientPhone': recipientPhone?.trim() ?? '',
      'recipientEmail': recipientEmail?.trim().toLowerCase() ?? '',
      'recipientContact':
          '${recipientPhone?.trim() ?? ''} · ${recipientEmail?.trim().toLowerCase() ?? ''}',
      'relationship': relationship,
      'occasion': occasion,
      senderGiftModeFieldName: giftModeValue,
      senderGiftAnonymousGiftTypeFieldName: anonymousGiftType,
      senderGiftSenderRevealModeFieldName:
          senderRevealMode ?? 'reveal_immediately',
      'senderRevealConsent':
          giftModeValue == 'anonymous_gift' ? 'not_requested' : 'granted',
      'recipientRevealRequestStatus': 'none',
      senderGiftSelfGiftFrequencyFieldName:
          mode == SenderGiftMode.myself ? selfGiftFrequency : null,
      'deliveryAddress': deliveryAddress?.trim() ?? '',
      'deliveryAddressData': deliveryAddressData == null
          ? null
          : {
              'placeId': deliveryAddressData!.placeId,
              'description': deliveryAddressData!.description,
              'mainText': deliveryAddressData!.mainText,
              'subText': deliveryAddressData!.subText,
              'lat': deliveryAddressData!.lat,
              'lng': deliveryAddressData!.lng,
              'components': deliveryAddressData!.components,
            },
      'deliveryPostcode': deliveryAddressData?.components['postcode'],
      'deliveryCity': deliveryAddressData?.components['city'],
      'deliveryCountry': deliveryAddressData?.components['country'],
      'deliveryDate': deliveryDate,
      'deliveryTimeWindow': deliveryTimeWindow,
      'flexibleDelivery': flexibleDelivery,
      'selectedBudgetGbp': budget,
      'budget': budget,
      'grossBudget': budget,
      'grossGiftBudget': budget,
      'budgetStatus': 'pending_allocation',
      'personalMessage': personalMessage?.trim() ?? '',
      'senderMessageText': personalMessage?.trim() ?? '',
      'interests': selectedInterests,
      'interestTags': selectedInterests,
      'giftThemes': themes.map((theme) => theme.toMap()).toList(),
      'giftThemeLabels': selectedInterests,
      'customInterests': themes
          .where((theme) => theme.source == 'custom')
          .map((theme) => theme.label)
          .toList(),
      'notes': notes?.trim() ?? '',
      'foodAllergies': foodAllergies?.trim() ?? '',
      'medicalAllergies': medicalAllergies?.trim() ?? '',
      'dietaryRestrictions': dietaryRestrictions?.trim() ?? '',
      'religiousOrCulturalConsiderations': culturalConsiderations?.trim() ?? '',
      'safetyThingsToAvoid': safetyThingsToAvoid?.trim() ?? '',
      'giftTeamSafetyNotes': giftTeamNotes?.trim() ?? '',
      'allergySafetyNotes': safetySummary,
      'procurementSafetyNotes': {
        'foodAllergies': foodAllergies?.trim() ?? '',
        'medicalAllergies': medicalAllergies?.trim() ?? '',
        'dietaryRestrictions': dietaryRestrictions?.trim() ?? '',
        'religiousOrCulturalConsiderations':
            culturalConsiderations?.trim() ?? '',
        'thingsToAvoid': safetyThingsToAvoid?.trim() ?? '',
        'anythingElse': giftTeamNotes?.trim() ?? '',
        'summary': safetySummary,
      },
      'voiceNote': voiceNote?.toMap(),
      'irisGiftBrief': brief.toMap(),
      'preferredStyles': preferredStyles,
      'sizesAndPreferences': {
        'clothingSize': clothingSize?.trim() ?? '',
        'shoeSize': shoeSize?.trim() ?? '',
        'ringSize': ringSize?.trim() ?? '',
        'preferredFit': '',
        'height': '',
        'favouriteColours': favouriteColours?.trim() ?? '',
        'brandsLiked': likedBrands?.trim() ?? '',
        'brandsDisliked': '',
        'preferredStyles': preferredStyles,
      },
      'giftType': giftType,
      'paymentStatus': 'payment_pending',
      'source': 'sender_mobile',
      'paymentMethod': 'card',
      'applyRoth': false,
      'rothApplied': 0,
      'cardAmount': budget,
      'walletContributionGbp': 0,
      'remainingStripeAmountGbp': budget,
      'giftStatus': 'draft',
      'status': 'draft',
      'giftStoryEnabled': true,
      'giftStoryApproved': true,
      'giftStoryShareEnabled': true,
      'giftStorySharePrivacy': 'private',
      'storyTheme': 'iridescent',
      'assignedAdminId': null,
      senderGiftIrisSuggestionFieldName: senderGiftPendingIrisSuggestion,
      'adminDecision': '',
      'internalNotes': '',
      'recipientContentConsent': recipientContentConsent ?? 'pending',
      'senderContentConsent': 'pending',
      'allowCircumSocialUse': allowCircumSocialUse,
      'allowBrandTagging': allowBrandTagging,
      'allowPublicPosting': allowPublicPosting,
      'contentUsageScope': 'private',
      'contentStatus': 'not_started',
      senderGiftCampaignIdFieldName: mode == SenderGiftMode.campaign
          ? (campaignId ?? 'bringing-london-closer')
          : null,
      senderGiftCampaignNameFieldName: mode == SenderGiftMode.campaign
          ? (campaignName ?? 'Bringing London Closer')
          : null,
      'campaignTagline': mode == SenderGiftMode.campaign
          ? (campaignTagline ?? '100 Londoners. 100 gifts. 100 stories.')
          : null,
      'campaignType': mode == SenderGiftMode.campaign
          ? (campaignType ?? 'anonymous_gifting')
          : null,
      'campaignCompatibilityScore': campaignCompatibilityScore,
      'campaignMatchSummary': campaignMatchSummary,
      'campaignParticipantId': campaignParticipantId,
      'giftRequestId': giftRequestId,
      'giftDeliveryId': giftDeliveryId,
      'linkedGiftDeliveryStatus': linkedGiftDeliveryStatus,
      'riderCompletionAccepted': riderCompletionAccepted,
      'deliveryVerificationCompleted': deliveryVerificationCompleted,
      'deliveryAuditSuccessful': deliveryAuditSuccessful,
      'activeDeliveryDispute': activeDeliveryDispute,
      'giftStoryStatus': giftStoryStatus,
      'giftStoryAdminOverride': giftStoryAdminOverride,
      'giftStoryAdminUserId': giftStoryAdminUserId,
      'giftStoryAdminOverrideReason': giftStoryAdminOverrideReason,
      'giftStoryAdminOverrideAt': giftStoryAdminOverrideAt,
      'giftStoryPreviousStatus': giftStoryPreviousStatus,
      'giftStoryOverrideType': giftStoryOverrideType,
      'participantConsentRequired': mode == SenderGiftMode.campaign,
      'recordingConsentRequired': mode == SenderGiftMode.campaign,
      'mutualRevealAllowed': mode == SenderGiftMode.campaign,
      'anonymousByDefault':
          mode == SenderGiftMode.anonymous || mode == SenderGiftMode.campaign,
    };
  }
}
