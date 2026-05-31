import 'package:circum/pricing/delivery_pricing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DeliveryPricing', () {
    test(
        'preserves the current base plus per-mile formula for standard parcels',
        () {
      final quote = DeliveryPricing.calculate(
        const DeliveryPricingInput(distanceMiles: 4.8, weightKg: 2),
      );

      expect(quote.baseFare, 6);
      expect(quote.distanceFare, 3.8);
      expect(quote.weightSurcharge, 0);
      expect(quote.total, 9.8);
      expect(quote.weightCategory, 'Small Parcel');
    });

    test('adds the medium parcel surcharge above 5kg up to 10kg', () {
      final quote = DeliveryPricing.calculate(
        const DeliveryPricingInput(distanceMiles: 4.8, weightKg: 7),
      );

      expect(quote.weightCategory, 'Medium Parcel');
      expect(quote.weightSurcharge, 3);
      expect(quote.total, 12.8);
    });

    test('adds higher surcharges for heavy and large parcels', () {
      final heavy = DeliveryPricing.calculate(
        const DeliveryPricingInput(distanceMiles: 4.8, weightKg: 12),
      );
      final large = DeliveryPricing.calculate(
        const DeliveryPricingInput(distanceMiles: 4.8, weightKg: 23),
      );

      expect(heavy.weightCategory, 'Heavy Parcel');
      expect(heavy.weightSurcharge, 7);
      expect(large.weightCategory, 'Large Item');
      expect(large.weightSurcharge, 15);
    });

    test('flags parcels above 40kg for manual quote', () {
      final quote = DeliveryPricing.calculate(
        const DeliveryPricingInput(distanceMiles: 4.8, weightKg: 41),
      );

      expect(quote.weightCategory, 'Extra Heavy');
      expect(quote.requiresManualQuote, isTrue);
      expect(quote.total, 0);
    });
  });
}
