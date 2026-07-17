class GiftsSocialPolicy {
  static const campaignBudgetIndependenceRule =
      'Campaign matching is budget-independent. Budget must not be used to calculate compatibility score, rank matches, approve matches, or explain matches. Budget is private payment/procurement data only.';
  static const campaignSafetyFilteringRule =
      'Campaign matching is separate from gift selection. Allergies, dietary requirements, medical restrictions, age restrictions and similar constraints must only filter IRIS gift recommendations, not participant compatibility. Progression should stop only when no safe gifts remain after filtering.';

  static bool canPostPublicly(Map<String, dynamic> gift) {
    return gift['recipientContentConsent'] == 'granted' &&
        gift['allowCircumSocialUse'] == true &&
        gift['allowPublicPosting'] == true;
  }

  static bool canApproveBrandTags(Map<String, dynamic> gift) {
    return canPostPublicly(gift) && gift['allowBrandTagging'] == true;
  }

  static bool canRevealSender(Map<String, dynamic> gift) {
    final mode = '${gift['senderRevealMode'] ?? 'anonymous_forever'}';
    if (mode == 'reveal_immediately') return true;
    if (mode == 'reveal_after_delivery' && gift['status'] == 'delivered') {
      return true;
    }
    return gift['senderRevealConsent'] == 'granted' &&
        gift['recipientRevealRequestStatus'] == 'approved';
  }

  static Map<String, dynamic> recipientSafeView(Map<String, dynamic> gift) {
    final safe = Map<String, dynamic>.from(gift)
      ..remove('internalNotes')
      ..remove('adminDecision')
      ..remove('manualGiftPlan')
      ..remove('brandNotes')
      ..remove('budget')
      ..remove('budgetPrivacyNote')
      ..remove('grossBudget')
      ..remove('grossGiftBudget')
      ..remove('giftCampaignTotal')
      ..remove('selectedBudgetGbp')
      ..remove('paymentMethod')
      ..remove('rothApplied')
      ..remove('cardAmount')
      ..remove('remainingCardAmount')
      ..remove('remainingStripeAmountGbp')
      ..remove('stripeCheckoutSessionId')
      ..remove('paymentDraftId');
    if (!canRevealSender(gift)) {
      safe
        ..remove('senderId')
        ..remove('senderName')
        ..remove('senderEmail');
    }
    return safe;
  }

  static ({double score, String reason}) scoreMatch(
    Map<String, dynamic> first,
    Map<String, dynamic> second,
  ) {
    if (first['matchConsent'] != true || second['matchConsent'] != true) {
      return (score: 0, reason: 'Both participants must consent to matching.');
    }
    if (first['matchStatus'] == 'withdrawn' ||
        second['matchStatus'] == 'withdrawn' ||
        first['blockedUserIds'] is List &&
            (first['blockedUserIds'] as List).contains(second['userId']) ||
        second['blockedUserIds'] is List &&
            (second['blockedUserIds'] as List).contains(first['userId'])) {
      return (
        score: 0,
        reason: 'This match is not eligible for safety reasons.'
      );
    }
    final firstTerms = _terms(first);
    final secondTerms = _terms(second);
    final overlap = firstTerms.intersection(secondTerms).toList()..sort();
    final score = overlap.isEmpty
        ? 25.0
        : (45 + overlap.length * 12).clamp(0, 100).toDouble();
    final reason = overlap.isEmpty
        ? 'A broad campaign match with no obvious preference conflict.'
        : 'Matched because both selected ${overlap.take(3).join(', ')}.';
    return (score: score, reason: reason);
  }

  static Set<String> _terms(Map<String, dynamic> participant) {
    final values = <dynamic>[
      ...?participant['interests'] as List?,
      ...?participant['hobbies'] as List?,
      ...?participant['preferredGiftCategories'] as List?,
      ...?participant['favouriteFoodsDrinks'] as List?,
      ...?participant['musicTaste'] as List?,
      ...?participant['booksFilms'] as List?,
      ...?participant['lifestyle'] as List?,
      participant['customInspiration'],
    ];
    return values
        .map((value) => '$value'.trim().toLowerCase())
        .where((value) => value.isNotEmpty)
        .toSet();
  }
}
