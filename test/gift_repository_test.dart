import 'package:circum/app/gifts/gift_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('internal Gifts repository contains exactly 1000 active internal items',
      () {
    expect(internalGiftRepository, hasLength(1000));
    expect(internalGiftRepository.every((item) => item.active), isTrue);
    expect(internalGiftRepository.every((item) => item.internalOnly), isTrue);
    expect(internalGiftRepository.every((item) => item.estimatedPriceMin > 0),
        isTrue);
    expect(
      internalGiftRepository.every(
        (item) => item.estimatedPriceMax >= item.estimatedPriceMin,
      ),
      isTrue,
    );
  });

  test(
      'expanded interests preserve existing interests and add dining/travel/business tags',
      () {
    expect(giftsExpandedInterests.containsAll(giftsExistingInterests), isTrue);
    expect(giftsExpandedInterests, contains('Restaurants'));
    expect(giftsExpandedInterests, contains('Fine Dining'));
    expect(giftsExpandedInterests, contains('Michelin Dining'));
    expect(giftsExpandedInterests, contains('Craft Beverages'));
    expect(giftsExpandedInterests, contains('Entrepreneurship'));
  });

  test('repository item interests use the allowed interest taxonomy', () {
    final invalid = internalGiftRepository
        .expand((item) => item.interests)
        .where((interest) => !giftsExpandedInterests.contains(interest))
        .toSet();
    expect(invalid, isEmpty);
  });

  test(
      'restaurants, fine dining and michelin dining are first-class categories',
      () {
    final categories =
        internalGiftRepository.map((item) => item.category).toSet();
    expect(categories, contains('Restaurants'));
    expect(categories, contains('Fine dining'));
    expect(categories, contains('Michelin dining'));
  });

  test(
      'recommendation engine returns top ten internal candidates and budget notes',
      () {
    final result = const GiftsRecommendationEngine().recommend(
      budget: 500,
      relationship: 'Partner',
      occasion: 'Anniversary',
      interests: const ['Fine Dining', 'Luxury Travel', 'Books'],
      notes: 'No allergies.',
    );
    expect(result.topCandidates, hasLength(10));
    expect(result.experienceSummary, contains('Recommended Experience'));
    expect(result.budgetAllocation.keys, contains('giftProcurement'));
    expect(result.procurementNotes.join(' '), contains('Do not reveal'));
  });

  test('medical and religious safety risks are surfaced for admin review', () {
    final result = const GiftsRecommendationEngine().recommend(
      budget: 250,
      relationship: 'Friend',
      occasion: 'Birthday',
      interests: const ['Wine Appreciation', 'Food', 'Muslim'],
      notes: 'Recipient is diabetic and needs halal options.',
    );
    final warnings = result.riskWarnings.join(' ').toLowerCase();
    expect(warnings, contains('sugary'));
    expect(warnings, contains('halal'));
    expect(warnings, contains('alcohol'));
  });
}
