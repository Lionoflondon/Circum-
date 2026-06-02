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
  });
}
