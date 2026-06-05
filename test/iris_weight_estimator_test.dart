import 'package:circum/app/iris/iris_weight_estimator.dart';
import 'package:circum/pricing/delivery_pricing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('IrisWeightEstimator', () {
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
      expect(DeliveryPricing.weightSourceLabel(classification.selectedWeightSource),
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
      expect(DeliveryPricing.weightSourceLabel(classification.selectedWeightSource),
          'Rider Verified');
    });
  });
}
