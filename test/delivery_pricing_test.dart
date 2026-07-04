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

    test('prices parcels above 40kg with Heavy Duty handling', () {
      final quote = DeliveryPricing.calculate(
        const DeliveryPricingInput(
          distanceMiles: 4.8,
          weightKg: 41,
          vehicleType: 'Van',
        ),
      );

      expect(quote.weightCategory, 'Extra Heavy');
      expect(quote.weightSurcharge, 25);
      expect(quote.specialConditions, 25);
      expect(quote.vehicleSurcharge, 10);
      expect(quote.total, 72.2);
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

    test('adds heavy handling surcharge at configured boundaries', () {
      expect(DeliveryPricing.heavyHandlingFor(50).surchargeGbp, 0);
      expect(DeliveryPricing.heavyHandlingFor(50.01).surchargeGbp, 5);
      expect(DeliveryPricing.heavyHandlingFor(150).surchargeGbp, 5);
      expect(DeliveryPricing.heavyHandlingFor(150.01).surchargeGbp, 10);
      expect(DeliveryPricing.heavyHandlingFor(300).surchargeGbp, 10);
      expect(DeliveryPricing.heavyHandlingFor(300.01).surchargeGbp, 20);
      expect(DeliveryPricing.heavyHandlingFor(500).surchargeGbp, 20);
      expect(DeliveryPricing.heavyHandlingFor(500.01).surchargeGbp, 40);
      expect(
        DeliveryPricing.heavyHandlingFor(1000).adminReviewRequired,
        isTrue,
      );
    });

    test('adds operational flags without changing vehicle logic', () {
      final recommended = DeliveryPricing.heavyHandlingFor(151);
      final required = DeliveryPricing.heavyHandlingFor(301);
      final multiTrip = DeliveryPricing.heavyHandlingFor(751);

      expect(recommended.twoPersonRecommended, isTrue);
      expect(recommended.twoPersonRequired, isFalse);
      expect(required.twoPersonRequired, isTrue);
      expect(multiTrip.multiTripReviewRequired, isTrue);

      final quote = DeliveryPricing.calculate(
        const DeliveryPricingInput(distanceMiles: 4.8, weightKg: 151),
      );
      expect(quote.heavyHandlingSurcharge, 10);
      expect(quote.twoPersonRecommended, isTrue);
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

    test('checkout pricing weight uses each source once', () {
      expect(
        DeliveryPricing.checkoutPricingWeightKg(
          userEnteredWeightKg: 0.7,
          irisEstimatedWeightKg: 0.7,
          matchedCatalogueWeightKg: 0.7,
        ),
        0.7,
      );
      expect(
        DeliveryPricing.checkoutPricingWeightKg(
          userEnteredWeightKg: 1.2,
          irisEstimatedWeightKg: 1.64,
          matchedCatalogueWeightKg: 1.24,
        ),
        1.64,
      );
      expect(
        DeliveryPricing.checkoutPricingWeightKg(
          userEnteredWeightKg: 1.2,
          irisEstimatedWeightKg: 6.2,
          matchedCatalogueWeightKg: 6.2,
        ),
        6.2,
      );
      expect(
        DeliveryPricing.checkoutPricingWeightKg(
          userEnteredWeightKg: 23,
          irisEstimatedWeightKg: 18,
          matchedCatalogueWeightKg: 20,
        ),
        23,
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

    test('phone remains small but requires car handling', () {
      final suitability = DeliveryPricing.resolveVehicleSuitability(
        weightKg: 0.5,
        description: 'iPhone 13',
        itemCategory: 'Electronics',
        repositoryVehicleSuitability: 'Bike',
        fragile: true,
        highValue: true,
      );
      final classification = DeliveryPricing.resolveClassification(
        description: 'iPhone 13',
        userEnteredWeightKg: 0.5,
        irisEstimateKg: 0.321,
        vehicleSuitability: suitability,
        confidence: 'high',
      );

      expect(classification.finalWeightKg, closeTo(0.5, 0.001));
      expect(classification.finalWeightBand, 'Small Parcel');
      expect(classification.vehicleType, 'Car');
      expect(suitability.recommendedVehicle, 'Car');
      expect(suitability.allows('Bike'), isFalse);
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

    test('four stackable suitcases remain a car delivery', () {
      final suitability = DeliveryPricing.resolveVehicleSuitability(
        weightKg: 92,
        description: '4 medium suitcases 23kg each',
        itemCategory: 'Luggage',
        dimensions: const DeliveryItemDimensions(
          lengthCm: 65,
          widthCm: 40,
          heightCm: 25,
        ),
        repositoryVehicleSuitability: 'Car or Van',
        stackable: true,
        quantity: 4,
        singleItemWeightKg: 23,
      );
      final quote = DeliveryPricing.calculate(
        const DeliveryPricingInput(
          distanceMiles: 4.8,
          weightKg: 92,
          vehicleType: 'Car',
          quantity: 4,
          singleItemWeightKg: 23,
          stackable: true,
        ),
      );

      expect(suitability.recommendedVehicle, 'Car');
      expect(suitability.allows('Car'), isTrue);
      expect(quote.vehicleSurcharge, 2);
      expect(quote.weightSurcharge, 0);
      expect(quote.specialConditions, 0);
      expect(quote.total, greaterThan(0));
    });

    test('stackable laptops remain car eligible when aggregate volume fits',
        () {
      final suitability = DeliveryPricing.resolveVehicleSuitability(
        weightKg: 30,
        description: '20 laptops',
        itemCategory: 'Electronics',
        dimensions: const DeliveryItemDimensions(
          lengthCm: 35,
          widthCm: 25,
          heightCm: 3,
        ),
        repositoryVehicleSuitability: 'Van',
        stackable: true,
        quantity: 20,
        singleItemWeightKg: 1.5,
      );

      expect(suitability.recommendedVehicle, 'Car');
      expect(suitability.allows('Car'), isTrue);
    });

    test('bulky single items retain van handling', () {
      final sofa = DeliveryPricing.resolveVehicleSuitability(
        weightKg: 25,
        description: 'Sofa',
        stackable: false,
        quantity: 1,
        singleItemWeightKg: 25,
      );
      final washingMachine = DeliveryPricing.resolveVehicleSuitability(
        weightKg: 70,
        description: 'Washing machine',
        stackable: false,
        quantity: 1,
        singleItemWeightKg: 70,
      );
      final washingMachineQuote = DeliveryPricing.calculate(
        const DeliveryPricingInput(
          distanceMiles: 4.8,
          weightKg: 70,
          vehicleType: 'Van',
          quantity: 1,
          singleItemWeightKg: 70,
          stackable: false,
        ),
      );

      expect(sofa.recommendedVehicle, 'Van');
      expect(washingMachine.recommendedVehicle, 'Van');
      expect(washingMachineQuote.specialConditions, 25);
      expect(washingMachineQuote.total, greaterThan(0));
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
        'Emergency passport delivery',
        'Visa documents',
        'Signed contract',
        'Certificates',
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
        expect(DeliveryPricing.vehicleCanCarryDelivery('Car', suitability),
            isTrue);
        expect(DeliveryPricing.vehicleCanCarryDelivery('Van', suitability),
            isTrue);
      }
    });

    test('large document boxes can override Bike document eligibility', () {
      final box = DeliveryPricing.resolveVehicleSuitability(
        weightKg: 14,
        description: 'Large archive document box',
        itemCategory: 'Documents',
        repositoryVehicleSuitability: 'Bike',
      );

      expect(box.recommendedVehicle, isNot('Bike'));
      expect(box.allows('Bike'), isFalse);
      expect(box.allows('Car') || box.allows('Van'), isTrue);
    });

    test('minimum vehicle keeps larger verified vehicles eligible', () {
      final bikeMinimum = DeliveryPricing.eligibleVehiclesForMinimum('Bike');
      final carMinimum = DeliveryPricing.eligibleVehiclesForMinimum('Car');
      final vanMinimum = DeliveryPricing.eligibleVehiclesForMinimum('Van');

      expect(bikeMinimum, ['Bike', 'Car', 'Van']);
      expect(carMinimum, ['Car', 'Van']);
      expect(vanMinimum, ['Van']);
    });

    test('Express bike-eligible jobs broadcast Bike before larger vehicles',
        () {
      expect(
        DeliveryPricing.broadcastVehicleOrder(
          minimumVehicle: 'Bike',
          express: true,
        ),
        ['Bike', 'Car', 'Van'],
      );
      expect(
        DeliveryPricing.broadcastVehicleOrder(
          minimumVehicle: 'Van',
          express: true,
        ),
        ['Van'],
      );
    });

    test('larger vehicle accepting smaller job does not change base quote', () {
      final bikeQuote = DeliveryPricing.calculate(
        const DeliveryPricingInput(
          distanceMiles: 3,
          weightKg: 0.5,
          vehicleType: 'Bike',
        ),
      );
      final customerSelectedBikeQuote = DeliveryPricing.calculate(
        const DeliveryPricingInput(
          distanceMiles: 3,
          weightKg: 0.5,
          vehicleType: 'Bike',
        ),
      );

      expect(customerSelectedBikeQuote.total, bikeQuote.total);
    });

    test('small electronics use car while courier-safe parcels can use Bike',
        () {
      final phone = DeliveryPricing.resolveVehicleSuitability(
        weightKg: 0.8,
        description: 'Small phone package',
        itemCategory: 'Electronics',
        repositoryVehicleSuitability: 'Bike',
        fragile: false,
      );
      final medium = DeliveryPricing.resolveVehicleSuitability(
        weightKg: 7,
        description: 'Medium parcel',
      );

      expect(phone.recommendedVehicle, 'Car');
      expect(phone.allows('Bike'), isFalse);
      expect(medium.allows('Bike'), isTrue);
      expect(medium.recommendedVehicle, 'Bike');
    });

    test('printer uses car unless dimensions require a van', () {
      final printer = DeliveryPricing.resolveVehicleSuitability(
        weightKg: 9,
        description: 'Printer',
        itemCategory: 'Business equipment',
        fragile: true,
        repositoryVehicleSuitability: 'Van',
      );
      final bulkyPrinter = DeliveryPricing.resolveVehicleSuitability(
        weightKg: 9,
        description: 'Printer',
        itemCategory: 'Business equipment',
        fragile: true,
        dimensions: const DeliveryItemDimensions(
          lengthCm: 130,
          widthCm: 70,
          heightCm: 60,
        ),
      );

      expect(printer.recommendedVehicle, 'Car');
      expect(printer.allowedVehicles, containsAll(['Car', 'Van']));
      expect(bulkyPrinter.recommendedVehicle, 'Van');
    });

    test('fragile or Vanguard small items are not Bike eligible', () {
      final fragile = DeliveryPricing.resolveVehicleSuitability(
        weightKg: 1,
        description: 'Glass ornament',
        fragile: true,
      );
      final vanguard = DeliveryPricing.resolveVehicleSuitability(
        weightKg: 1,
        description: 'High value watch',
        highValue: true,
        vanguardRequired: true,
      );

      expect(fragile.allows('Bike'), isFalse);
      expect(vanguard.allows('Bike'), isFalse);
    });

    test('vehicle surcharge follows the selected vehicle', () {
      expect(DeliveryPricing.calculateVehicleSurcharge('Bike'), 0);
      expect(DeliveryPricing.calculateVehicleSurcharge('Car'), 2);
      expect(DeliveryPricing.calculateVehicleSurcharge('Van'), 10);
    });

    test('canonical delivery decision carries one confirmed weight and quote',
        () {
      final suitability = DeliveryPricing.resolveVehicleSuitability(
        weightKg: 0.5,
        description: 'iPhone',
        itemCategory: 'Electronics',
        highValue: true,
      );
      final quote = DeliveryPricing.calculate(
        const DeliveryPricingInput(
          distanceMiles: 3,
          weightKg: 0.5,
          vehicleType: 'Car',
        ),
      );
      final decision = CanonicalDeliveryDecision(
        itemName: 'iPhone',
        canonicalItemType: 'Electronics',
        quantity: 1,
        userDeclaredWeightKg: 0.2,
        irisEstimatedWeightKg: 0.3,
        confirmedWeightKg: 0.5,
        minimumBillableWeightKg: DeliveryPricing.minimumBillableWeightKg,
        finalPricingWeightKg: 0.5,
        parcelClass: DeliveryPricing.weightBandFor(0.5).category,
        recommendedVehicle: suitability.recommendedVehicle,
        allowedVehicles: suitability.allowedVehicles,
        disallowedVehicles: const ['Bike'],
        vehicleReason: suitability.explanation,
        fragile: false,
        highValue: true,
        vanguardRequired: false,
        labourRequired: false,
        twoPersonRequired: false,
        confidenceScore: 92,
        confidenceBand: 'high',
        source: 'iris_confirmed',
        pricingBreakdown: quote,
        explanation:
            'IRIS estimated this transport-ready parcel and selected Car.',
        riderVerificationRequired: false,
      );

      expect(decision.finalPricingWeightKg, 0.5);
      expect(decision.pricingBreakdown.weightCategory, decision.parcelClass);
      expect(decision.recommendedVehicle, 'Car');
      expect(decision.allowedVehicles, contains('Car'));
      expect(decision.disallowedVehicles, contains('Bike'));
      expect(decision.toJson()['finalPricingWeightKg'], 0.5);
    });

    test('canonical vehicle result is consistent across common scenarios', () {
      final iphone = DeliveryPricing.resolveVehicleSuitability(
        weightKg: 0.5,
        description: 'iPhone',
        itemCategory: 'Electronics',
        highValue: true,
      );
      final documents = DeliveryPricing.resolveVehicleSuitability(
        weightKg: 0.5,
        description: 'Passport documents',
        itemCategory: 'Documents',
      );
      final sofa = DeliveryPricing.resolveVehicleSuitability(
        weightKg: 20,
        description: 'Sofa',
        itemCategory: 'Furniture',
      );

      expect(iphone.recommendedVehicle, 'Car');
      expect(iphone.explanation.toLowerCase(), isNot(contains('bike')));
      expect(iphone.allows('Bike'), isFalse);
      expect(documents.recommendedVehicle, 'Bike');
      expect(documents.allows('Bike'), isTrue);
      expect(sofa.recommendedVehicle, 'Van');
      expect(sofa.allows('Bike'), isFalse);
    });

    test('changed item, weight, or quantity creates a distinct decision', () {
      CanonicalDeliveryDecision decisionFor({
        required String itemName,
        required String itemType,
        required int quantity,
        required double confirmedWeightKg,
      }) {
        final suitability = DeliveryPricing.resolveVehicleSuitability(
          weightKg: confirmedWeightKg,
          description: itemName,
          itemCategory: itemType,
          highValue: itemType == 'Electronics',
          quantity: quantity,
        );
        final quote = DeliveryPricing.calculate(
          DeliveryPricingInput(
            distanceMiles: 3,
            weightKg: confirmedWeightKg,
            vehicleType: suitability.recommendedVehicle,
            quantity: quantity,
          ),
        );
        return CanonicalDeliveryDecision(
          itemName: itemName,
          canonicalItemType: itemType,
          quantity: quantity,
          userDeclaredWeightKg: confirmedWeightKg,
          irisEstimatedWeightKg: confirmedWeightKg,
          confirmedWeightKg: confirmedWeightKg,
          minimumBillableWeightKg: DeliveryPricing.minimumBillableWeightKg,
          finalPricingWeightKg: confirmedWeightKg,
          parcelClass:
              DeliveryPricing.weightBandFor(confirmedWeightKg).category,
          recommendedVehicle: suitability.recommendedVehicle,
          allowedVehicles: suitability.allowedVehicles,
          disallowedVehicles: const [],
          vehicleReason: suitability.explanation,
          fragile: false,
          highValue: itemType == 'Electronics',
          vanguardRequired: false,
          labourRequired: false,
          twoPersonRequired: false,
          confidenceScore: 80,
          confidenceBand: 'high',
          source: 'test',
          pricingBreakdown: quote,
          explanation: suitability.explanation,
          riderVerificationRequired: false,
        );
      }

      final phone = decisionFor(
        itemName: 'iPhone',
        itemType: 'Electronics',
        quantity: 1,
        confirmedWeightKg: 0.5,
      );
      final laptop = decisionFor(
        itemName: 'MacBook',
        itemType: 'Electronics',
        quantity: 1,
        confirmedWeightKg: 2.5,
      );
      final threeLaptops = decisionFor(
        itemName: 'MacBook',
        itemType: 'Electronics',
        quantity: 3,
        confirmedWeightKg: 7.5,
      );

      expect(laptop.itemName, isNot(phone.itemName));
      expect(laptop.finalPricingWeightKg, isNot(phone.finalPricingWeightKg));
      expect(threeLaptops.quantity, isNot(laptop.quantity));
      expect(threeLaptops.pricingBreakdown.total,
          greaterThan(laptop.pricingBreakdown.total));
    });

    test('canonical decision preview scenarios resolve one vehicle answer', () {
      const scenarios =
          <({String item, String category, double weight, String vehicle})>[
        (item: 'iPhone', category: 'Electronics', weight: 0.5, vehicle: 'Car'),
        (item: 'MacBook', category: 'Electronics', weight: 2.5, vehicle: 'Car'),
        (item: 'iPad', category: 'Electronics', weight: 1.0, vehicle: 'Car'),
        (
          item: '65 inch TV',
          category: 'Electronics',
          weight: 18,
          vehicle: 'Van'
        ),
        (item: 'Passport', category: 'Documents', weight: 0.5, vehicle: 'Bike'),
        (item: 'Contract', category: 'Documents', weight: 0.5, vehicle: 'Bike'),
        (item: 'Envelope', category: 'Documents', weight: 0.5, vehicle: 'Bike'),
        (
          item: 'Dining table',
          category: 'Furniture',
          weight: 25,
          vehicle: 'Van'
        ),
        (
          item: 'Office chair',
          category: 'Furniture',
          weight: 12,
          vehicle: 'Van'
        ),
        (item: 'Mattress', category: 'Furniture', weight: 18, vehicle: 'Van'),
        (item: 'Sofa', category: 'Furniture', weight: 20, vehicle: 'Van'),
        (
          item: 'Washing machine',
          category: 'Appliance',
          weight: 35,
          vehicle: 'Van'
        ),
        (item: 'Fridge', category: 'Appliance', weight: 35, vehicle: 'Van'),
        (item: 'Bicycle', category: 'Large item', weight: 14, vehicle: 'Van'),
        (item: 'Cake', category: 'Gift', weight: 1.5, vehicle: 'Car'),
        (item: 'Flowers', category: 'Gift', weight: 1.0, vehicle: 'Car'),
        (item: 'Artwork', category: 'Fragile', weight: 3.0, vehicle: 'Car'),
      ];

      for (final scenario in scenarios) {
        final suitability = DeliveryPricing.resolveVehicleSuitability(
          weightKg: scenario.weight,
          description: scenario.item,
          itemCategory: scenario.category,
          fragile: scenario.category == 'Fragile',
          highValue: scenario.category == 'Electronics',
        );
        final quote = DeliveryPricing.calculate(
          DeliveryPricingInput(
            distanceMiles: 3,
            weightKg: scenario.weight,
            vehicleType: suitability.recommendedVehicle,
          ),
        );
        final decision = CanonicalDeliveryDecision(
          itemName: scenario.item,
          canonicalItemType: scenario.category,
          quantity: 1,
          userDeclaredWeightKg: scenario.weight,
          irisEstimatedWeightKg: scenario.weight,
          confirmedWeightKg: scenario.weight,
          minimumBillableWeightKg: DeliveryPricing.minimumBillableWeightKg,
          finalPricingWeightKg: scenario.weight,
          parcelClass: DeliveryPricing.weightBandFor(scenario.weight).category,
          recommendedVehicle: suitability.recommendedVehicle,
          allowedVehicles: suitability.allowedVehicles,
          disallowedVehicles: const [],
          vehicleReason: suitability.explanation,
          fragile: scenario.category == 'Fragile',
          highValue: scenario.category == 'Electronics',
          vanguardRequired: false,
          labourRequired: false,
          twoPersonRequired: scenario.vehicle == 'Van',
          confidenceScore: 80,
          confidenceBand: 'high',
          source: 'preview_scenario',
          pricingBreakdown: quote,
          explanation: suitability.explanation,
          riderVerificationRequired: false,
        );

        expect(
          decision.recommendedVehicle,
          scenario.vehicle,
          reason: scenario.item,
        );
        final reason = decision.vehicleReason.toLowerCase();
        for (final otherVehicle in const ['bike', 'car', 'van']) {
          if (otherVehicle == scenario.vehicle.toLowerCase()) continue;
          expect(reason, isNot(contains('$otherVehicle recommended')));
        }
      }
    });
  });
}
