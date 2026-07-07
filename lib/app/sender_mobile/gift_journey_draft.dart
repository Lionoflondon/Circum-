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
  final String? localPath;
  final String? storagePath;
  final String? downloadUrl;
  final DateTime createdAt;
  final String? transcript;
  final String? language;

  const SenderGiftVoiceNote({
    required this.hasVoiceNote,
    required this.durationSeconds,
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
        'localPath': localPath,
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
  final String? senderRevealMode;
  final String? selfGiftFrequency;
  final bool allowCircumSocialUse;
  final bool allowBrandTagging;
  final bool allowPublicPosting;
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
    this.senderRevealMode,
    this.selfGiftFrequency,
    this.allowCircumSocialUse = false,
    this.allowBrandTagging = false,
    this.allowPublicPosting = false,
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

  SenderGiftIrisBrief generateIrisBrief() {
    final themes = normalizedGiftThemes;
    final labels = themes.map((theme) => theme.label).toList();
    final signals = senderGiftIrisSignalsForThemes(labels);
    final unsupported = themes
        .where((theme) => !theme.knownToIris)
        .map((theme) => theme.label)
        .toList();
    final hasNotes = (notes ?? '').trim().isNotEmpty;
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
            ((favouriteColours ?? '').trim().isNotEmpty ? 3 : 0))
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
      thingsToAvoid: unsupported.isEmpty
          ? 'Avoid product assumptions until the Gifts Team reviews the request.'
          : 'Do not treat ${unsupported.join(', ')} as catalogue-backed interests.',
      catalogueCoverage: signals,
      confidence: confidence,
      personalisationScore: score,
      allergySafetyNotes:
          'No allergy or medical restriction fields were supplied in this mobile flow.',
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
    String? senderRevealMode,
    String? selfGiftFrequency,
    bool? allowCircumSocialUse,
    bool? allowBrandTagging,
    bool? allowPublicPosting,
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
      senderRevealMode: senderRevealMode ?? this.senderRevealMode,
      selfGiftFrequency: selfGiftFrequency ?? this.selfGiftFrequency,
      allowCircumSocialUse: allowCircumSocialUse ?? this.allowCircumSocialUse,
      allowBrandTagging: allowBrandTagging ?? this.allowBrandTagging,
      allowPublicPosting: allowPublicPosting ?? this.allowPublicPosting,
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
    return {
      'senderId': senderId,
      'senderName': senderName ?? '',
      'senderEmail': senderEmail.toLowerCase(),
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
      'voiceNote': voiceNote?.toMap(),
      'irisGiftBrief': brief.toMap(),
      'sizesAndPreferences': {
        'clothingSize': clothingSize?.trim() ?? '',
        'shoeSize': shoeSize?.trim() ?? '',
        'ringSize': ringSize?.trim() ?? '',
        'preferredFit': '',
        'height': '',
        'favouriteColours': favouriteColours?.trim() ?? '',
        'brandsLiked': likedBrands?.trim() ?? '',
        'brandsDisliked': '',
      },
      'giftType': mode == SenderGiftMode.campaign ? 'campaign' : 'standard',
      'paymentStatus': 'payment_pending',
      'source': 'sender_mobile',
      'applyRoth': false,
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
      'recipientContentConsent': 'pending',
      'senderContentConsent': 'pending',
      'allowCircumSocialUse': allowCircumSocialUse,
      'allowBrandTagging': allowBrandTagging,
      'allowPublicPosting': allowPublicPosting,
      'contentUsageScope': 'private',
      'contentStatus': 'not_started',
      senderGiftCampaignIdFieldName:
          mode == SenderGiftMode.campaign ? 'bringing-london-closer' : null,
      senderGiftCampaignNameFieldName:
          mode == SenderGiftMode.campaign ? 'Bringing London Closer' : null,
      'campaignTagline': mode == SenderGiftMode.campaign
          ? '100 Londoners. 100 gifts. 100 stories.'
          : null,
      'campaignType':
          mode == SenderGiftMode.campaign ? 'anonymous_gifting' : null,
      'participantConsentRequired': mode == SenderGiftMode.campaign,
      'recordingConsentRequired': mode == SenderGiftMode.campaign,
      'mutualRevealAllowed': mode == SenderGiftMode.campaign,
      'anonymousByDefault':
          mode == SenderGiftMode.anonymous || mode == SenderGiftMode.campaign,
    };
  }
}
