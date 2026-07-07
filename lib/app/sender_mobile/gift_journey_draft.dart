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
    final selectedInterests = {
      ...interests,
      if ((customInterest ?? '').trim().isNotEmpty) customInterest!.trim(),
    }.toList();
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
      'budget': budget,
      'grossBudget': budget,
      'grossGiftBudget': budget,
      'budgetStatus': 'pending_allocation',
      'personalMessage': personalMessage?.trim() ?? '',
      'senderMessageText': personalMessage?.trim() ?? '',
      'interests': selectedInterests,
      'interestTags': selectedInterests,
      'notes': notes?.trim() ?? '',
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
