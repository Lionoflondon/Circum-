import 'dart:convert';
import 'dart:io';

import 'package:circum/pricing/delivery_pricing.dart';
import 'package:circum/pricing/pricing_constants.dart';
import 'package:circum/website/shared/pricing/website_pricing_constants.dart'
    as website;
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

      expect(quote.specialConditions, 9);
      expect(quote.total, 17);
    });

    test('express price is always greater than standard', () {
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

      expect(express.total, greaterThan(standard.total));
      expect(prices['expressPrice']!, greaterThan(prices['standardPrice']!));
      expect(express.serviceLevel, 'express');
      expect(standard.serviceLevel, 'standard');
      expect(express.serviceLevelSurcharge, greaterThan(0));
    });

    test('express jobs rank before standard jobs for rider matching', () {
      expect(
        DeliveryPricing.matchingPriorityRank('express'),
        lessThan(DeliveryPricing.matchingPriorityRank('standard')),
      );
    });

    test('matches canonical backend delivery policy constants', () {
      final policy = jsonDecode(
        File('server/functions/circum-delivery-policy.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final pricing = policy['pricing'] as Map<String, dynamic>;
      final vehicleSurcharges =
          pricing['vehicleSurchargesGbp'] as Map<String, dynamic>;
      final express = pricing['express'] as Map<String, dynamic>;
      final vehiclePolicy = policy['vehiclePolicy'] as Map<String, dynamic>;

      expect(PricingConstants.baseFareGbp, pricing['baseDeliveryGbp']);
      expect(
        PricingConstants.additionalFarePerMileGbp,
        pricing['distancePerMileGbp'],
      );
      expect(
        PricingConstants.includedBaseMiles,
        pricing['includedBaseMiles'],
      );
      expect(
        PricingConstants.shortTripFareFloorMiles,
        pricing['shortTripFareFloorMiles'],
      );
      expect(
        PricingConstants.longDistanceThresholdMiles,
        pricing['longDistanceThresholdMiles'],
      );
      expect(
        PricingConstants.longDistanceMileageMultiplier,
        pricing['longDistanceMileageMultiplier'],
      );
      expect(
        PricingConstants.fixedExpressSurchargeGbp,
        express['minimumSurchargeGbp'],
      );
      expect(
        PricingConstants.expressMultiplier,
        1 + (express['standardSubtotalPercent'] as num),
      );
      expect(
        PricingConstants.twoPersonThresholdKg,
        vehiclePolicy['vanRequiredMinKg'],
      );
      expect(
        PricingConstants.vehicleSurchargesGbp['motorbike'],
        vehicleSurcharges['motorbike'],
      );
      expect(
        PricingConstants.vehicleSurchargesGbp['car'],
        vehicleSurcharges['car'],
      );
      expect(
        PricingConstants.vehicleSurchargesGbp['van'],
        vehicleSurcharges['van'],
      );

      expect(
        website.PricingConstants.fixedExpressSurchargeGbp,
        PricingConstants.fixedExpressSurchargeGbp,
      );
      expect(
        website.PricingConstants.vehicleSurchargesGbp,
        PricingConstants.vehicleSurchargesGbp,
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
      expect(DeliveryPricing.vehicleCanCarryWeight('Motorbike', 20), isFalse);
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
      expect(classification.vehicleType, isNot('Motorbike'));
      expect(classification.vehicleType, 'Van');
      expect(quote.weightCategory, isNot('Small Parcel'));
      expect(DeliveryPricing.vehicleCanCarryWeight('Motorbike', 50), isFalse);
      expect(DeliveryPricing.vehicleCanCarryWeight('Van', 50), isTrue);
    });

    test('sofa enforces heavy van classification', () {
      final classification = DeliveryPricing.resolveClassification(
        description: 'Sofa',
        userEnteredWeightKg: 10,
      );

      expect(classification.finalWeightBand, 'Heavy Parcel');
      expect(classification.vehicleType, 'Van');
      expect(DeliveryPricing.vehicleCanCarryWeight('Motorbike', 12), isFalse);
    });

    test('small envelope remains small and bike compatible', () {
      final classification = DeliveryPricing.resolveClassification(
        description: 'Small envelope',
        userEnteredWeightKg: 1,
      );

      expect(classification.finalWeightKg, 1);
      expect(classification.finalWeightBand, 'Small Parcel');
      expect(classification.vehicleType, 'Motorbike');
      expect(DeliveryPricing.vehicleCanCarryWeight('Motorbike', 1), isTrue);
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
      expect(classification.vehicleType, 'Motorbike');
      expect(classification.requiresManualReview, isFalse);
    });

    test('65 inch TV is not bike compatible', () {
      final classification = DeliveryPricing.resolveClassification(
        description: 'TV 65 inch',
        userEnteredWeightKg: 8,
      );

      expect(classification.finalWeightBand, 'Heavy Parcel');
      expect(classification.vehicleType, 'Van');
      expect(DeliveryPricing.vehicleCanCarryWeight('Motorbike', 12), isFalse);
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

      expect(small.recommendedVehicle, 'Motorbike');
      expect(small.allowedVehicles, containsAll(['Motorbike', 'Car', 'Van']));
      expect(suitcase.recommendedVehicle, 'Car');
      expect(suitcase.allows('Motorbike'), isFalse);
      expect(suitcase.allows('Car'), isTrue);
      expect(suitcase.allows('Van'), isTrue);
      expect(wardrobe.recommendedVehicle, 'Van');
      expect(wardrobe.allowedVehicles, ['Van']);
      expect(DeliveryPricing.vehicleWasUpgraded('Van', 'Car'), isTrue);
      expect(DeliveryPricing.vehicleWasUpgraded('Motorbike', 'Car'), isFalse);
      expect(
          DeliveryPricing.vehicleMeetsMinimum('E-bike', 'Motorbike'), isTrue);
      expect(DeliveryPricing.vehicleDisabledReason('Motorbike', small), isNull);
      expect(
        DeliveryPricing.vehicleDisabledReason('Motorbike', suitcase),
        'Too small for this parcel',
      );
      expect(
        DeliveryPricing.vehicleDisabledReason('Motorbike', wardrobe),
        'Too small for this parcel',
      );
    });

    test('document deliveries always retain Motorbike eligibility', () {
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
          repositoryVehicleSuitability: 'Motorbike',
          fragile: true,
        );
        expect(suitability.recommendedVehicle, 'Motorbike');
        expect(suitability.allowedVehicles,
            containsAll(['Motorbike', 'Car', 'Van']));
        expect(
            DeliveryPricing.vehicleCanCarryDelivery('Motorbike', suitability),
            isTrue);
      }
    });

    test(
        'small electronics and courier-safe parcels up to 10kg can use Motorbike',
        () {
      final phone = DeliveryPricing.resolveVehicleSuitability(
        weightKg: 0.8,
        description: 'Small phone package',
        itemCategory: 'Electronics',
        repositoryVehicleSuitability: 'Motorbike',
        fragile: false,
      );
      final medium = DeliveryPricing.resolveVehicleSuitability(
        weightKg: 7,
        description: 'Medium parcel',
      );

      expect(phone.allows('Motorbike'), isTrue);
      expect(medium.allows('Motorbike'), isTrue);
      expect(medium.recommendedVehicle, 'Motorbike');
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

    test('two compact printers use car below the two-person threshold', () {
      final compactPrinterLoad = DeliveryPricing.resolveVehicleSuitability(
        weightKg: 15,
        description: '2 printers',
        itemCategory: 'Business equipment',
        fragile: true,
        quantity: 2,
        repositoryVehicleSuitability: 'Van',
      );
      final heavyPrinterLoad = DeliveryPricing.resolveVehicleSuitability(
        weightKg: 40,
        description: '2 printers',
        itemCategory: 'Business equipment',
        fragile: true,
        quantity: 2,
        repositoryVehicleSuitability: 'Van',
      );

      expect(compactPrinterLoad.recommendedVehicle, 'Car');
      expect(compactPrinterLoad.allowedVehicles, containsAll(['Car', 'Van']));
      expect(heavyPrinterLoad.recommendedVehicle, 'Van');
    });

    test('fragile or Vanguard small items are not Motorbike eligible', () {
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

      expect(fragile.allows('Motorbike'), isFalse);
      expect(vanguard.allows('Motorbike'), isFalse);
    });

    test('compact footwear uses car when high value and Vanguard protected',
        () {
      final shoes = DeliveryPricing.resolveVehicleSuitability(
        weightKg: 1.2,
        description: 'Nike shoes',
        itemCategory: 'Fashion',
        repositoryVehicleSuitability: 'Motorbike',
        fragile: true,
        highValue: true,
        vanguardRequired: true,
        dimensions: const DeliveryItemDimensions(
          lengthCm: 25,
          widthCm: 18,
          heightCm: 8,
        ),
      );

      expect(shoes.recommendedVehicle, 'Car');
      expect(shoes.allowedVehicles, containsAll(['Car', 'Van']));
      expect(
          DeliveryPricing.vehicleCanCarryDelivery('Motorbike', shoes), isFalse);
    });

    test('vehicle surcharge follows the selected vehicle', () {
      expect(DeliveryPricing.calculateVehicleSurcharge('Motorbike'), 0);
      expect(DeliveryPricing.calculateVehicleSurcharge('Car'), 2);
      expect(DeliveryPricing.calculateVehicleSurcharge('Van'), 10);
    });
  });
}
