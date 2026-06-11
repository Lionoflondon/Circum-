import 'package:circum/app/iris/iris_item_repository.dart';
import 'package:circum/app/iris/iris_weight_estimator.dart';
import 'package:circum/pricing/delivery_pricing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('IrisWeightEstimator', () {
    test('repository contains exactly 1000 structured items', () {
      expect(IrisItemRepository.items.length,
          IrisItemRepository.expectedItemCount);
      expect(
        IrisItemRepository.items.map((item) => item.itemName).toSet().length,
        IrisItemRepository.expectedItemCount,
      );
      expect(
        IrisItemRepository.items.every((item) =>
            item.estimatedWeightKg > 0 &&
            item.minimumWeightKg > 0 &&
            item.maximumWeightKg >= item.estimatedWeightKg &&
            item.aliases.isNotEmpty &&
            item.category.isNotEmpty &&
            item.weightClass.isNotEmpty &&
            item.sizeClass.isNotEmpty),
        isTrue,
      );
    });

    test('iPhone 13 description returns known product weight', () {
      final estimate =
          IrisWeightEstimator.knownProductEstimate('Apple iPhone 13 in a box');

      expect(estimate, isNotNull);
      expect(estimate!.weightKg, closeTo(0.174, 0.001));
      expect(estimate.weightBand, 'Small Parcel');
      expect(estimate.weightSource, 'known_product_lookup');
      expect(estimate.confidence, 'high');
    });

    test('iPhone 15 uses catalogue weight instead of generic phone fallback',
        () {
      final estimate =
          IrisWeightEstimator.knownProductEstimate('iPhone 15 for delivery');

      expect(estimate, isNotNull);
      expect(estimate!.weightKg, closeTo(0.171, 0.001));
      expect(estimate.weightSource, 'known_product_lookup');
      expect(DeliveryPricing.weightSourceLabel(estimate.weightSource),
          'Repository Match');
      expect(estimate.matchedItemName, 'Apple iPhone 15');
      expect(estimate.truthBand, 'Exact Match');
      expect(estimate.typicalDimensions?.label, '15 x 8 x 2 cm');
      expect(estimate.vehicleSuitability, 'Bike');
      expect(estimate.fragile, isTrue);
    });

    test('iPhone 15 with heavier declared weight charges declared weight', () {
      final estimate =
          IrisWeightEstimator.knownProductEstimate('Apple iPhone 15');

      expect(estimate, isNotNull);
      expect(
        DeliveryPricing.chargeableWeightKg(
          senderWeightKg: 0.197,
          irisWeightKg: estimate!.weightKg,
        ),
        closeTo(0.197, 0.001),
      );
    });

    test('AirPods Pro returns catalogue weight', () {
      final estimate =
          IrisWeightEstimator.knownProductEstimate('AirPods Pro case');

      expect(estimate, isNotNull);
      expect(estimate!.weightKg, closeTo(0.056, 0.001));
      expect(estimate.weightBand, 'Small Parcel');
    });

    test('final chargeable weight still uses higher customer or Iris weight',
        () {
      final estimate =
          IrisWeightEstimator.knownProductEstimate('PlayStation 5 console');

      expect(estimate, isNotNull);
      expect(
        DeliveryPricing.chargeableWeightKg(
          senderWeightKg: 2,
          irisWeightKg: estimate!.weightKg,
        ),
        4.5,
      );
      expect(
        DeliveryPricing.chargeableWeightKg(
          senderWeightKg: 8,
          irisWeightKg: estimate.weightKg,
        ),
        8,
      );
    });

    test('unknown item falls back to customer declared source', () {
      final estimate = IrisWeightEstimator.knownProductEstimate('mystery item');
      final classification = DeliveryPricing.resolveClassification(
        description: 'mystery item',
        userEnteredWeightKg: 3,
      );

      expect(estimate, isNull);
      expect(classification.selectedWeightSource, 'customer_declared');
      expect(
          DeliveryPricing.weightSourceLabel(
              classification.selectedWeightSource),
          'Customer Declared');
    });

    test('heavy mismatch triggers manual review warning', () {
      expect(
        IrisWeightEstimator.potentialMismatchDetected(
          description: 'small iPhone parcel',
          customerDeclaredWeightKg: 15,
          irisEstimatedWeightKg: 0.171,
        ),
        isTrue,
      );
    });

    test('rider verified weight overrides Iris and customer weight', () {
      final classification = DeliveryPricing.resolveClassification(
        description: 'Apple iPhone 15',
        userEnteredWeightKg: 0.197,
        irisEstimateKg: 0.171,
        driverVerifiedWeightKg: 1.2,
        confidence: 'high',
      );

      expect(classification.finalWeightKg, 1.2);
      expect(classification.selectedWeightSource, 'driver_verified');
      expect(
          DeliveryPricing.weightSourceLabel(
              classification.selectedWeightSource),
          'Rider Verified');
    });

    test('expanded repository matches common non-curated items', () {
      final suitcase =
          IrisWeightEstimator.knownProductEstimate('large Heathrow suitcase');

      expect(suitcase, isNotNull);
      expect(suitcase!.weightSource, 'repository_match');
      expect(suitcase.weightKg, greaterThan(5));
      expect(suitcase.packageType, 'Airport');
      expect(suitcase.vehicleSuitability, isNotEmpty);
    });

    test('generic luggage uses a neutral repository match', () {
      final suitcase = IrisWeightEstimator.knownProductEstimate(
        '23 KG SUITCASE',
      );

      expect(suitcase, isNotNull);
      expect(suitcase!.matchedItemName, 'Suitcase');
      expect(suitcase.packageType, 'Luggage');
      expect(suitcase.vehicleSuitability, 'Car');
    });

    test('known item discrepancies use expected weight and metadata', () {
      final iphoneNine = IrisWeightEstimator.resolveKnownItemWeight(
        description: 'iPhone 15',
        senderWeightKg: 9,
      );
      final iphoneThree = IrisWeightEstimator.resolveKnownItemWeight(
        description: 'iPhone',
        senderWeightKg: 3,
      );
      final boxedPhone = IrisWeightEstimator.resolveKnownItemWeight(
        description: 'boxed iPhone',
        senderWeightKg: 0.8,
      );
      final macBook = IrisWeightEstimator.resolveKnownItemWeight(
        description: 'MacBook',
        senderWeightKg: 3,
      );
      final heavyMacBook = IrisWeightEstimator.resolveKnownItemWeight(
        description: 'MacBook',
        senderWeightKg: 20,
      );

      expect(iphoneNine.unusual, isTrue);
      expect(iphoneNine.pricingWeightKg, lessThan(2));
      expect(iphoneNine.warning, contains('Weight looks unusual'));
      expect(iphoneThree.unusual, isTrue);
      expect(boxedPhone.unusual, isFalse);
      expect(boxedPhone.pricingWeightKg, 0.8);
      expect(macBook.unusual, isFalse);
      expect(macBook.category, 'Electronics');
      expect(macBook.fragile, isTrue);
      expect(macBook.valueSensitive, isTrue);
      expect(macBook.vanguardRecommended, isTrue);
      expect(heavyMacBook.unusual, isTrue);
    });

    test('generic parcels are not overridden and bulky lows are flagged', () {
      final generic = IrisWeightEstimator.resolveKnownItemWeight(
        description: 'generic parcel box',
        senderWeightKg: 9,
      );
      final washingMachine = IrisWeightEstimator.resolveKnownItemWeight(
        description: 'washing machine',
        senderWeightKg: 5,
      );

      expect(generic.unusual, isFalse);
      expect(generic.pricingWeightKg, 9);
      expect(washingMachine.unusual, isTrue);
      expect(washingMachine.vanOnly, isTrue);
    });

    test('iPhone 16 ignores extreme historical matches for final pricing', () {
      final estimate = IrisWeightEstimator.knownProductEstimate('iPhone 16');
      expect(estimate, isNotNull);

      final decision = IrisWeightEstimator.resolveTrustedKnownItemPricing(
        description: 'iPhone 16',
        quantity: 1,
        userWeightKg: 0.2,
        trustedItemWeightKg: estimate!.weightKg,
        historicalMatches: const [0.2, 0.5, 9],
      );

      expect(decision.pricingWeightKg, inInclusiveRange(0.2, 0.6));
      expect(
        DeliveryPricing.weightBandFor(decision.pricingWeightKg).category,
        'Small Parcel',
      );
      expect(decision.ignoredHistoricalOutliers, contains(9));
      expect(decision.explanation, contains('ignored unusually high'));
    });

    test('quantity parser supports common sender formats and safe defaults',
        () {
      expect(IrisWeightEstimator.extractQuantity('Sofa'), 1);
      expect(IrisWeightEstimator.extractQuantity('1 Sofa'), 1);
      expect(IrisWeightEstimator.extractQuantity('3 Sofas'), 3);
      expect(IrisWeightEstimator.extractQuantity('5 MacBooks'), 5);
      expect(IrisWeightEstimator.extractQuantity('MacBook x5'), 5);
      expect(IrisWeightEstimator.extractQuantity('5 x MacBook'), 5);
      expect(IrisWeightEstimator.extractQuantity('12 boxes of books'), 12);
      expect(IrisWeightEstimator.extractQuantity('iPhone 15'), 1);
      expect(IrisWeightEstimator.extractQuantity('15 iPhones'), 15);
      expect(IrisWeightEstimator.extractQuantity('0 Sofas'), 1);
      expect(IrisWeightEstimator.extractQuantity(''), 1);
    });

    test('repository weight is multiplied by detected quantity', () {
      final sofas = IrisWeightEstimator.knownProductEstimate('3 Sofas');
      final macBooks = IrisWeightEstimator.knownProductEstimate('MacBook x5');

      expect(sofas, isNotNull);
      expect(sofas!.quantity, 3);
      expect(sofas.singleItemWeightKg, 12);
      expect(sofas.weightKg, 36);
      expect(
        sofas.weightBand,
        DeliveryPricing.weightBandFor(36).category,
      );

      expect(macBooks, isNotNull);
      expect(macBooks!.quantity, 5);
      expect(macBooks.singleItemWeightKg, closeTo(1.24, 0.001));
      expect(macBooks.weightKg, closeTo(6.2, 0.001));
      expect(
        macBooks.weightBand,
        DeliveryPricing.weightBandFor(6.2).category,
      );
    });
  });
}
