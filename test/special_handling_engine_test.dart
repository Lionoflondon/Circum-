import 'package:circum/pricing/delivery_pricing.dart';
import 'package:circum/pricing/special_handling_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SpecialHandlingEngine', () {
    const base = DeliveryPricingBreakdown(
      baseFare: 5,
      distanceFare: 45,
      weightSurcharge: 0,
      vehicleSurcharge: 0,
      specialConditions: 0,
      serviceLevelSurcharge: 0,
      serviceLevel: 'standard',
      surgeMultiplier: 1,
      total: 50,
      weightCategory: 'Small Parcel',
    );

    test('normal electronics, suitcases and bulk phones have no labour fee',
        () {
      for (final item in [
        'MacBook Air x6',
        '100 iPhones',
        '4 suitcases',
      ]) {
        final result = SpecialHandlingEngine.evaluate(description: item);
        expect(result.handlingClass, SpecialHandlingClass.none);
        expect(result.labourPremium, 0);
      }
    });

    test('deep freezer adds heavy duty and stairs add two person', () {
      final ground = SpecialHandlingEngine.evaluate(
        description: 'Deep freezer',
      );
      final stairs = SpecialHandlingEngine.evaluate(
        description: 'Deep freezer',
        dropoffAccess: DeliveryAccess.stairs,
      );

      expect(ground.heavyDutyFee, 30);
      expect(ground.twoPersonFee, 0);
      expect(stairs.heavyDutyFee, 30);
      expect(stairs.twoPersonFee, 50);
    });

    test('piano always adds heavy duty and two person', () {
      final result = SpecialHandlingEngine.evaluate(
        description: 'Upright piano',
      );
      final quote = result.applyTo(base);

      expect(result.heavyDutyFee, 30);
      expect(result.twoPersonFee, 50);
      expect(quote.total, 130);
      expect(quote.riderBaseShare, 32.5);
      expect(quote.riderLabourShare, 64);
      expect(quote.totalRiderEarnings, 96.5);
      expect(quote.totalCircumRevenue, 33.5);
    });

    test('office setup receives assisted delivery only', () {
      final result = SpecialHandlingEngine.evaluate(
        description: 'Office chair, monitor setup and desktop PC plus boxes',
      );

      expect(result.handlingClass, SpecialHandlingClass.assisted);
      expect(result.assistedFee, 15);
      expect(result.heavyDutyFee, 0);
      expect(result.twoPersonFee, 0);
    });
  });
}
