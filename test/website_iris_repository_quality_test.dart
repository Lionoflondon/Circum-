import 'package:circum/website/shared/iris/iris_item_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Website IRIS repository quality', () {
    test('packaging adjectives do not resolve as item identities', () {
      for (final description in [
        'boxed',
        'fragile',
        'small',
        'large',
        'sealed',
        'return',
        'premium',
        'gift wrapped',
      ]) {
        expect(
          IrisItemRepository.match(description),
          isNull,
          reason: '"$description" is a modifier, not an item identity',
        );
      }
    });

    test('generic suitcase uses a conservative range and requires review', () {
      final suitcase = IrisItemRepository.match('suitcase');

      expect(suitcase, isNotNull);
      expect(suitcase!.estimatedWeightKg, 8);
      expect(suitcase.minimumWeightKg, 1);
      expect(suitcase.maximumWeightKg, 32);
      expect(suitcase.requiresIRISReview, isTrue);
    });
  });
}
