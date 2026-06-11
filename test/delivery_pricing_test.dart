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

    test('express price is always greater than standard', () {
      final economy = DeliveryPricing.calculate(
        const DeliveryPricingInput(
          distanceMiles: 4.8,
          weightKg: 2,
          economy: true,
        ),
      );
      final standard = DeliveryPricing.calculate(
        const DeliveryPricingInput(distanceMiles: 4.8, weightKg: 2),
      );
      final express = DeliveryPricing.calculate(
        const DeliveryPricingInput(
          distanceMiles: 4.8,
          weightKg: 2,
          express: true,
        ),
      );
      final prices = DeliveryPricing.serviceLevelPrices(
        const DeliveryPricingInput(distanceMiles: 4.8, weightKg: 2),
      );

      expect(economy.total, lessThan(standard.total));
      expect(express.total, greaterThan(standard.total));
      expect(prices['economyPrice']!, lessThan(prices['standardPrice']!));
      expect(prices['expressPrice']!, greaterThan(prices['standardPrice']!));
      expect(economy.serviceLevel, 'economy');
      expect(express.serviceLevel, 'express');
      expect(standard.serviceLevel, 'standard');
      expect(express.serviceLevelSurcharge, greaterThan(0));
    });

    test('express jobs rank before standard jobs for rider matching', () {
      expect(
        DeliveryPricing.matchingPriorityRank('express'),
        lessThan(DeliveryPricing.matchingPriorityRank('standard')),
      );
      expect(
        DeliveryPricing.matchingPriorityRank('standard'),
        lessThan(DeliveryPricing.matchingPriorityRank('economy')),
      );
    });

    test('uses a 65/35 rider and platform fare split', () {
      expect(DeliveryPricing.riderDeliveryFareShare, 0.65);
      expect(DeliveryPricing.platformDeliveryFareShare, 0.35);
      expect(DeliveryPricing.riderPayoutFromFare(100), 65);
      expect(DeliveryPricing.platformRevenueFromFare(100), 35);

      final quote = DeliveryPricing.calculate(
        const DeliveryPricingInput(distanceMiles: 4.8, weightKg: 2),
      );

      expect(quote.total, 12.2);
      expect(DeliveryPricing.riderPayoutFromFare(quote.total), 7.93);
      expect(DeliveryPricing.platformRevenueFromFare(quote.total), 4.27);
    });

    test('parses gram entries as kilograms', () {
      expect(DeliveryPricing.parseWeightKg('178g'), closeTo(0.178, 0.0001));
      expect(
          DeliveryPricing.parseWeightKg('178 grams'), closeTo(0.178, 0.0001));
      expect(DeliveryPricing.parseWeightKg('2kg'), 2);
    });

    test('same band with different weights does not create pricing conflict',
        () {
      expect(DeliveryPricing.weightBandFor(0.178).category, 'Small Parcel');
      expect(DeliveryPricing.weightBandFor(2).category, 'Small Parcel');
      expect(DeliveryPricing.weightsCrossPricingBands(0.178, 2), isFalse);
      expect(
        DeliveryPricing.pricingWeightForConfirmedWeights(
          senderWeightKg: 0.178,
          irisWeightKg: 2,
        ),
        2,
      );
    });

    test('different bands create pricing conflict and use higher band weight',
        () {
      expect(DeliveryPricing.weightsCrossPricingBands(4.8, 6.2), isTrue);
      expect(
        DeliveryPricing.pricingWeightForConfirmedWeights(
          senderWeightKg: 4.8,
          irisWeightKg: 6.2,
        ),
        6.2,
      );
    });

    test('piano at 20kg is heavy parcel and cannot use bike', () {
      final quote = DeliveryPricing.calculate(
        const DeliveryPricingInput(
          distanceMiles: 4.8,
          weightKg: 20,
          vehicleType: 'Van',
        ),
      );

      expect(quote.weightCategory, 'Heavy Parcel');
      expect(quote.weightSurcharge, 7);
      expect(DeliveryPricing.recommendedVehicleForWeight(20), 'Van');
      expect(DeliveryPricing.vehicleCanCarryWeight('Bike', 20), isFalse);
      expect(DeliveryPricing.vehicleCanCarryWeight('Van', 20), isTrue);
    });

    test('Iris 2kg and sender 20kg uses sender 20kg', () {
      expect(
        DeliveryPricing.chargeableWeightKg(
          senderWeightKg: 20,
          irisWeightKg: 2,
        ),
        20,
      );
    });

    test('Iris 25kg and sender 20kg uses Iris 25kg', () {
      expect(
        DeliveryPricing.chargeableWeightKg(
          senderWeightKg: 20,
          irisWeightKg: 25,
        ),
        25,
      );
      expect(DeliveryPricing.weightBandFor(25).category, 'Large Item');
    });

    test('missing Iris does not override sender-confirmed higher weight', () {
      expect(
        DeliveryPricing.chargeableWeightKg(
          senderWeightKg: 20,
          irisWeightKg: null,
        ),
        20,
      );
    });

    test('final verified weight uses the highest trusted weight', () {
      expect(
        DeliveryPricing.finalVerifiedWeightKg(
          customerWeightKg: 3,
          irisWeightKg: 8,
          riderVerifiedWeightKg: 6,
        ),
        8,
      );
      expect(
        DeliveryPricing.finalVerifiedWeightKg(
          customerWeightKg: 10,
          irisWeightKg: 7,
          riderVerifiedWeightKg: 15,
        ),
        15,
      );
    });

    test('weight band boundaries are stable', () {
      expect(DeliveryPricing.weightBandFor(0).category, 'Small Parcel');
      expect(DeliveryPricing.weightBandFor(5).category, 'Small Parcel');
      expect(DeliveryPricing.weightBandFor(5.01).category, 'Medium Parcel');
      expect(DeliveryPricing.weightBandFor(10).category, 'Medium Parcel');
      expect(DeliveryPricing.weightBandFor(10.01).category, 'Heavy Parcel');
      expect(DeliveryPricing.weightBandFor(20).category, 'Heavy Parcel');
      expect(DeliveryPricing.weightBandFor(20.01).category, 'Large Item');
      expect(DeliveryPricing.weightBandFor(40).category, 'Large Item');
      expect(DeliveryPricing.weightBandFor(40.01).category, 'Extra Heavy');
    });

    test('piano resolves to extra heavy van classification', () {
      final classification = DeliveryPricing.resolveClassification(
        description: 'Piano',
        userEnteredWeightKg: 25,
        irisEstimateKg: 50,
        historicalVerifiedMinKg: 25,
        historicalVerifiedMaxKg: 50,
        confidence: 'medium',
      );
      final quote = DeliveryPricing.calculate(DeliveryPricingInput(
        distanceMiles: 6.65,
        weightKg: classification.finalWeightKg,
        vehicleType: classification.vehicleType,
      ));

      expect(classification.finalWeightKg, 50);
      expect(classification.finalWeightBand, 'Extra Heavy');
      expect(classification.vehicleType, isNot('Bike'));
      expect(classification.vehicleType, 'Van');
      expect(quote.weightCategory, isNot('Small Parcel'));
      expect(DeliveryPricing.vehicleCanCarryWeight('Bike', 50), isFalse);
      expect(DeliveryPricing.vehicleCanCarryWeight('Van', 50), isTrue);
    });

    test('sofa enforces heavy van classification', () {
      final classification = DeliveryPricing.resolveClassification(
        description: 'Sofa',
        userEnteredWeightKg: 10,
      );

      expect(classification.finalWeightBand, 'Heavy Parcel');
      expect(classification.vehicleType, 'Van');
      expect(DeliveryPricing.vehicleCanCarryWeight('Bike', 12), isFalse);
    });

    test('small envelope remains small and bike compatible', () {
      final classification = DeliveryPricing.resolveClassification(
        description: 'Small envelope',
        userEnteredWeightKg: 1,
      );

      expect(classification.finalWeightKg, 1);
      expect(classification.finalWeightBand, 'Small Parcel');
      expect(classification.vehicleType, 'Bike');
      expect(DeliveryPricing.vehicleCanCarryWeight('Bike', 1), isTrue);
    });

    test('phone remains small and bike compatible when weight is light', () {
      final classification = DeliveryPricing.resolveClassification(
        description: 'iPhone 13',
        userEnteredWeightKg: 0.178,
        irisEstimateKg: 0.174,
        confidence: 'high',
      );

      expect(classification.finalWeightKg, closeTo(0.178, 0.001));
      expect(classification.finalWeightBand, 'Small Parcel');
      expect(classification.vehicleType, 'Bike');
      expect(classification.requiresManualReview, isFalse);
    });

    test('65 inch TV is not bike compatible', () {
      final classification = DeliveryPricing.resolveClassification(
        description: 'TV 65 inch',
        userEnteredWeightKg: 8,
      );

      expect(classification.finalWeightBand, 'Heavy Parcel');
      expect(classification.vehicleType, 'Van');
      expect(DeliveryPricing.vehicleCanCarryWeight('Bike', 12), isFalse);
    });

    test('vehicle suitability considers dimensions and item type', () {
      final microwave = DeliveryPricing.resolveVehicleSuitability(
        weightKg: 12,
        description: 'Microwave',
        itemCategory: 'Kitchen appliance',
        dimensions: const DeliveryItemDimensions(
          lengthCm: 45,
          widthCm: 35,
          heightCm: 28,
        ),
        repositoryVehicleSuitability: 'Car or Van',
        fragile: true,
        stackable: false,
      );
      final suitcase = DeliveryPricing.resolveVehicleSuitability(
        weightKg: 12,
        description: 'Large suitcase',
        itemCategory: 'Luggage',
      );
      final washingMachine = DeliveryPricing.resolveVehicleSuitability(
        weightKg: 12,
        description: 'Washing machine',
        itemCategory: 'Appliance',
      );

      expect(microwave.recommendedVehicle, 'Car');
      expect(DeliveryPricing.vehicleCanCarryDelivery('Car', microwave), isTrue);
      expect(suitcase.recommendedVehicle, 'Car');
      expect(washingMachine.recommendedVehicle, 'Van');
      expect(
        DeliveryPricing.vehicleCanCarryDelivery('Car', washingMachine),
        isFalse,
      );
    });

    test('heavy luggage uses car unless quantity or size requires a van', () {
      final suitcase = DeliveryPricing.resolveVehicleSuitability(
        weightKg: 23,
        description: '23 KG SUITCASE',
        itemCategory: 'Luggage',
        repositoryVehicleSuitability: 'Car',
      );
      final twoSuitcases = DeliveryPricing.resolveVehicleSuitability(
        weightKg: 46,
        description: '2 large suitcases 23kg each',
        itemCategory: 'Luggage',
      );
      final fiveSuitcases = DeliveryPricing.resolveVehicleSuitability(
        weightKg: 115,
        description: '5 large suitcases 23kg each',
        itemCategory: 'Luggage',
      );
      final wardrobe = DeliveryPricing.resolveVehicleSuitability(
        weightKg: 23,
        description: '23kg wardrobe',
      );

      expect(suitcase.recommendedVehicle, 'Car');
      expect(suitcase.handlingNotes, contains('confirm they can lift safely'));
      expect(twoSuitcases.recommendedVehicle, 'Car');
      expect(fiveSuitcases.recommendedVehicle, 'Van');
      expect(wardrobe.recommendedVehicle, 'Van');
    });

    test('sender can upgrade but cannot downgrade the safe vehicle', () {
      final small = DeliveryPricing.resolveVehicleSuitability(
        weightKg: 1,
        description: 'Small envelope',
      );
      final suitcase = DeliveryPricing.resolveVehicleSuitability(
        weightKg: 23,
        description: '23kg suitcase',
      );
      final wardrobe = DeliveryPricing.resolveVehicleSuitability(
        weightKg: 23,
        description: 'Wardrobe',
      );

      expect(small.recommendedVehicle, 'Bike');
      expect(small.allowedVehicles, containsAll(['Bike', 'Car', 'Van']));
      expect(suitcase.recommendedVehicle, 'Car');
      expect(suitcase.allows('Bike'), isFalse);
      expect(suitcase.allows('Car'), isTrue);
      expect(suitcase.allows('Van'), isTrue);
      expect(wardrobe.recommendedVehicle, 'Van');
      expect(wardrobe.allowedVehicles, ['Van']);
      expect(DeliveryPricing.vehicleWasUpgraded('Van', 'Car'), isTrue);
      expect(DeliveryPricing.vehicleWasUpgraded('Bike', 'Car'), isFalse);
      expect(DeliveryPricing.vehicleMeetsMinimum('E-bike', 'Bike'), isTrue);
      expect(DeliveryPricing.vehicleDisabledReason('Bike', small), isNull);
      expect(
        DeliveryPricing.vehicleDisabledReason('Bike', suitcase),
        'Too small for this parcel',
      );
      expect(
        DeliveryPricing.vehicleDisabledReason('Bike', wardrobe),
        'Too small for this parcel',
      );
    });

    test('document deliveries always retain Bike eligibility', () {
      for (final description in [
        'Legal documents',
        'Passport',
        'Signed contract',
        'Government paperwork',
        'Small document folder',
      ]) {
        final suitability = DeliveryPricing.resolveVehicleSuitability(
          weightKg: 1,
          description: description,
          itemCategory: 'Documents',
          repositoryVehicleSuitability: 'Bike',
          fragile: true,
        );
        expect(suitability.recommendedVehicle, 'Bike');
        expect(
            suitability.allowedVehicles, containsAll(['Bike', 'Car', 'Van']));
        expect(DeliveryPricing.vehicleCanCarryDelivery('Bike', suitability),
            isTrue);
      }
    });

    test('small electronics can use Bike but medium parcels cannot', () {
      final phone = DeliveryPricing.resolveVehicleSuitability(
        weightKg: 0.8,
        description: 'Small phone package',
        itemCategory: 'Electronics',
        repositoryVehicleSuitability: 'Bike',
        fragile: true,
      );
      final medium = DeliveryPricing.resolveVehicleSuitability(
        weightKg: 7,
        description: 'Medium parcel',
      );

      expect(phone.allows('Bike'), isTrue);
      expect(medium.allows('Bike'), isFalse);
      expect(medium.recommendedVehicle, 'Car');
    });
  });
}
