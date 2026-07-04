import 'package:circum/app/iris/iris_item_repository.dart';
import 'package:circum/app/iris/iris_weight_estimator.dart';
import 'package:circum/pricing/delivery_pricing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Protected IRIS baseline', () {
    const baseline = [
      _BaselineCase(
        description: 'passport',
        canonicalName: 'Passport / document envelope',
        weightKg: 0.2,
        minKg: 0.03,
        maxKg: 1,
        parcelClass: 'Small Parcel',
        minimumVehicle: 'Bike',
        eligibleVehicles: ['Bike', 'Car', 'Van'],
        highValue: false,
        vanguardRequired: false,
      ),
      _BaselineCase(
        description: 'driving licence',
        canonicalName: 'single Driving licence',
        weightKg: 0.03,
        minKg: 0.01,
        maxKg: 0.05,
        parcelClass: 'Small Parcel',
        minimumVehicle: 'Bike',
        eligibleVehicles: ['Bike', 'Car', 'Van'],
        highValue: false,
        vanguardRequired: true,
      ),
      _BaselineCase(
        description: 'document envelope',
        canonicalName: 'Passport / document envelope',
        weightKg: 0.2,
        minKg: 0.03,
        maxKg: 1,
        parcelClass: 'Small Parcel',
        minimumVehicle: 'Bike',
        eligibleVehicles: ['Bike', 'Car', 'Van'],
        highValue: false,
        vanguardRequired: false,
      ),
      _BaselineCase(
        description: 'iPhone',
        canonicalName: 'Apple iPhone',
        weightKg: 0.45,
        minKg: 0.2,
        maxKg: 0.8,
        parcelClass: 'Small Parcel',
        minimumVehicle: 'Bike',
        eligibleVehicles: ['Bike', 'Car', 'Van'],
        highValue: true,
        vanguardRequired: true,
      ),
      _BaselineCase(
        description: 'Apple iPhone',
        canonicalName: 'Apple iPhone',
        weightKg: 0.45,
        minKg: 0.2,
        maxKg: 0.8,
        parcelClass: 'Small Parcel',
        minimumVehicle: 'Bike',
        eligibleVehicles: ['Bike', 'Car', 'Van'],
        highValue: true,
        vanguardRequired: true,
      ),
      _BaselineCase(
        description: 'iPhone 13',
        canonicalName: 'Apple iPhone',
        weightKg: 0.45,
        minKg: 0.2,
        maxKg: 0.8,
        parcelClass: 'Small Parcel',
        minimumVehicle: 'Bike',
        eligibleVehicles: ['Bike', 'Car', 'Van'],
        highValue: true,
        vanguardRequired: true,
      ),
      _BaselineCase(
        description: 'mobile phone',
        canonicalName: 'Apple iPhone',
        weightKg: 0.45,
        minKg: 0.2,
        maxKg: 0.8,
        parcelClass: 'Small Parcel',
        minimumVehicle: 'Bike',
        eligibleVehicles: ['Bike', 'Car', 'Van'],
        highValue: true,
        vanguardRequired: true,
      ),
      _BaselineCase(
        description: 'MacBook',
        canonicalName: 'Apple MacBook',
        weightKg: 2.1,
        minKg: 1.2,
        maxKg: 3.2,
        parcelClass: 'Small Parcel',
        minimumVehicle: 'Car',
        eligibleVehicles: ['Car', 'Van'],
        highValue: true,
        vanguardRequired: true,
      ),
      _BaselineCase(
        description: 'MacBook Air',
        canonicalName: 'Apple MacBook',
        weightKg: 2.1,
        minKg: 1.2,
        maxKg: 3.2,
        parcelClass: 'Small Parcel',
        minimumVehicle: 'Car',
        eligibleVehicles: ['Car', 'Van'],
        highValue: true,
        vanguardRequired: true,
      ),
      _BaselineCase(
        description: 'MacBook Pro',
        canonicalName: 'Apple MacBook',
        weightKg: 2.1,
        minKg: 1.2,
        maxKg: 3.2,
        parcelClass: 'Small Parcel',
        minimumVehicle: 'Car',
        eligibleVehicles: ['Car', 'Van'],
        highValue: true,
        vanguardRequired: true,
      ),
    ];

    for (final item in baseline) {
      test('${item.description} remains canonical and protected', () {
        final repositoryItem = IrisItemRepository.match(item.description);
        final estimate =
            IrisWeightEstimator.knownProductEstimate(item.description);

        expect(repositoryItem, isNotNull);
        expect(repositoryItem!.canonicalName, item.canonicalName);
        expect(repositoryItem.highValue, item.highValue);
        expect(repositoryItem.requiresVanguard, item.vanguardRequired);

        expect(estimate, isNotNull);
        expect(estimate!.matchedItemName, item.canonicalName);
        expect(estimate.weightSource, 'repository_match');
        expect(['Repository Match', 'Medium Confidence'],
            contains(estimate.truthBand));
        expect(estimate.weightKg, inInclusiveRange(item.minKg, item.maxKg));
        if (item.weightKg != null) {
          expect(estimate.weightKg, closeTo(item.weightKg!, 0.001));
        }
        expect(estimate.weightBand, item.parcelClass);
        expect(estimate.vehicleSuitability, item.minimumVehicle);
        expect(
          DeliveryPricing.eligibleVehiclesForMinimum(
            estimate.vehicleSuitability,
          ),
          item.eligibleVehicles,
        );
        expect(estimate.valueSensitive, item.highValue);
        expect(estimate.vanguardRecommended, item.vanguardRequired);

        final decision = IrisWeightEstimator.resolveTrustedKnownItemPricing(
          description: item.description,
          quantity: estimate.quantity,
          userWeightKg: 0,
          trustedItemWeightKg: estimate.weightKg,
          historicalMatches: const [9, 16.4, 120],
          trustedWeightIsTransportReady: true,
        );

        expect(decision.pricingWeightKg,
            inInclusiveRange(item.pricingMinKg, item.pricingMaxKg));
        expect(decision.pricingWeightKg, isNot(closeTo(9, 0.001)));
        expect(decision.pricingWeightKg, isNot(closeTo(16.4, 0.001)));
        expect(decision.pricingWeightKg, isNot(closeTo(120, 0.001)));
      });
    }

    test('Food Basket is canonical repository data only', () {
      const aliases = [
        'food basket',
        'food hamper',
        'grocery basket',
        'grocery hamper',
        'fruit basket',
        'snack basket',
        'gift basket',
        'picnic basket',
        'hamper',
      ];

      for (final alias in aliases) {
        final repositoryItem = IrisItemRepository.match(alias);
        final estimate = IrisWeightEstimator.knownProductEstimate(alias);

        expect(repositoryItem?.id, 'canonical_food_hamper', reason: alias);
        expect(repositoryItem?.canonicalName, 'Food Basket / Food Hamper',
            reason: alias);
        expect(estimate?.matchedItemName, 'Food Basket / Food Hamper',
            reason: alias);
        expect(estimate?.weightSource, 'repository_match', reason: alias);
        expect(estimate?.weightKg, closeTo(4, 0.001), reason: alias);
        expect(estimate?.weightKg, inInclusiveRange(1, 15), reason: alias);
        expect(estimate?.vehicleSuitability, 'Bike', reason: alias);
        expect(estimate?.valueSensitive, isFalse, reason: alias);
        expect(estimate?.vanguardRecommended, isFalse, reason: alias);
      }
    });
  });
}

class _BaselineCase {
  final String description;
  final String canonicalName;
  final double? weightKg;
  final double minKg;
  final double maxKg;
  final String parcelClass;
  final String minimumVehicle;
  final List<String> eligibleVehicles;
  final bool highValue;
  final bool vanguardRequired;

  const _BaselineCase({
    required this.description,
    required this.canonicalName,
    this.weightKg,
    required this.minKg,
    required this.maxKg,
    required this.parcelClass,
    required this.minimumVehicle,
    required this.eligibleVehicles,
    required this.highValue,
    required this.vanguardRequired,
  });

  double get pricingMinKg => DeliveryPricing.minimumBillableWeightKg > minKg
      ? DeliveryPricing.minimumBillableWeightKg
      : minKg;

  double get pricingMaxKg => DeliveryPricing.minimumBillableWeightKg > maxKg
      ? DeliveryPricing.minimumBillableWeightKg
      : maxKg;
}
