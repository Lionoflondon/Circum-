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

      expect(quote.baseFare, 5);
      expect(quote.distanceFare, 7.2);
      expect(quote.weightSurcharge, 0);
      expect(quote.total, 12.2);
      expect(quote.weightCategory, 'Small Parcel');
    });

    test('adds the medium parcel surcharge above 5kg up to 10kg', () {
      final quote = DeliveryPricing.calculate(
        const DeliveryPricingInput(distanceMiles: 4.8, weightKg: 7),
      );

      expect(quote.weightCategory, 'Medium Parcel');
      expect(quote.weightSurcharge, 3);
      expect(quote.total, 15.2);
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

    test('uses config-driven special condition fees', () {
      final quote = DeliveryPricing.calculate(
        const DeliveryPricingInput(
          distanceMiles: 8,
          weightKg: 23,
          oversized: true,
          fragile: true,
          stairsFloors: 3,
        ),
      );

      expect(quote.baseFare, 5);
      expect(quote.distanceFare, 12);
      expect(quote.weightSurcharge, 15);
      expect(quote.specialConditions, 22);
      expect(quote.total, 54);
    });

    test('applies express and waiting-time fees from config', () {
      final quote = DeliveryPricing.calculate(
        const DeliveryPricingInput(
          distanceMiles: 2,
          weightKg: 2,
          express: true,
          waitingMinutes: 17,
        ),
      );

      expect(quote.specialConditions, 14);
      expect(quote.total, 22);
    });
  });
}
