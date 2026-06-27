import 'package:circum/app/iris/iris_item_repository.dart';
import 'package:circum/app/iris/iris_weight_estimator.dart';
import 'package:circum/pricing/delivery_pricing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('IrisWeightEstimator', () {
    test('repository contains the core catalogue and curated expansions', () {
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
            (item.subcategory.isNotEmpty ||
                !item.id.startsWith('beauty_fashion_')) &&
            item.weightClass.isNotEmpty &&
            item.sizeClass.isNotEmpty),
        isTrue,
      );
    });

    test('beauty and fashion expansion is complete and non-duplicated', () {
      final expanded = IrisItemRepository.items
          .where((item) => item.id.startsWith('beauty_fashion_'))
          .toList();

      expect(expanded.length, irisBeautyFashionItemCount);
      expect(expanded.map((item) => item.itemName).toSet().length,
          irisBeautyFashionItemCount);
      expect(
        expanded.every((item) =>
            item.subcategory.isNotEmpty &&
            item.estimatedWeightKg > 0 &&
            item.minimumWeightKg > 0 &&
            item.maximumWeightKg >= item.estimatedWeightKg &&
            item.aliases.isNotEmpty &&
            item.weightClass.isNotEmpty &&
            item.sizeClass.isNotEmpty),
        isTrue,
      );
    });

    test('beauty aliases resolve to realistic repository items', () {
      expect(IrisItemRepository.match('nail varnish')?.itemName, 'Nail Polish');
      expect(IrisItemRepository.match('brazilian hair')?.itemName,
          'Brazilian Human Hair Wig');
      expect(
          IrisItemRepository.match('spa gift hamper')?.itemName, 'Spa Hamper');
    });

    test('Vanguard and review flags distinguish normal and luxury items', () {
      final synthetic = IrisItemRepository.match('synthetic wig')!;
      final luxuryWig = IrisItemRepository.match('luxury wig over £500')!;
      final jewellery = IrisItemRepository.match('gold necklace')!;
      final watch = IrisItemRepository.match('luxury watch')!;
      final handbag = IrisItemRepository.match('designer handbag')!;
      final perfume = IrisItemRepository.match('perfume 50ml')!;
      final dress = IrisItemRepository.match("women's dress")!;

      expect(synthetic.requiresVanguard, isFalse);
      expect(luxuryWig.requiresVanguard, isTrue);
      expect(luxuryWig.requiresIRISReview, isTrue);
      expect(jewellery.requiresVanguard, isTrue);
      expect(watch.requiresVanguard, isTrue);
      expect(handbag.requiresVanguard, isTrue);
      expect(perfume.fragile, isTrue);
      expect(dress.fragile, isFalse);
    });

    test('high value beauty and fashion items remain car-suitable', () {
      for (final description in [
        'Designer Handbag',
        'Luxury Watch',
        'Luxury Human Hair Wig',
      ]) {
        final item = IrisItemRepository.items
            .singleWhere((item) => item.itemName == description);
        expect(item.highValue, isTrue);
        expect(item.vehicleSuitability, 'Car');
      }
      expect(
        IrisItemRepository.items
            .singleWhere((item) => item.itemName == 'Gift Hamper')
            .requiresIRISReview,
        isTrue,
      );
    });

    test('gift intelligence tags expose beauty fashion and hair context', () {
      expect(IrisItemRepository.match('lipstick')!.giftSignals,
          contains('beautyInterest'));
      expect(IrisItemRepository.match('designer heels')!.giftSignals,
          containsAll(['fashionInterest', 'footwearInterest']));
      expect(IrisItemRepository.match('hd lace')!.giftSignals,
          contains('hairInterest'));
      expect(IrisItemRepository.match('abaya')!.giftSignals,
          contains('modestFashionInterest'));
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

    test('MacBook matching prefers specific models before catch-all', () {
      final pro16 = IrisWeightEstimator.knownProductEstimate('MacBook Pro 16');
      final air13 = IrisWeightEstimator.knownProductEstimate('MacBook Air 13');
      final generic = IrisWeightEstimator.knownProductEstimate('MacBook');

      expect(pro16, isNotNull);
      expect(pro16!.matchedItemName, 'MacBook Pro 16');
      expect(pro16.singleItemWeightKg, closeTo(2.15, 0.001));
      expect(air13, isNotNull);
      expect(air13!.matchedItemName, 'MacBook Air 13');
      expect(air13.singleItemWeightKg, closeTo(1.24, 0.001));
      expect(generic, isNotNull);
      expect(generic!.matchedItemName, 'MacBook (unspecified model)');
      expect(generic.singleItemWeightKg, closeTo(1.51, 0.001));
      expect(generic.confidenceScore, closeTo(0.68, 0.001));
    });

    test('TV estimates use screen size before static fallback', () {
      final largeTv = IrisWeightEstimator.knownProductEstimate('65 inch tv');
      final compactTv = IrisWeightEstimator.knownProductEstimate('small tv');
      final unknownTv = IrisWeightEstimator.knownProductEstimate('television');

      expect(largeTv, isNotNull);
      expect(largeTv!.matchedItemName, '65" Television');
      expect(largeTv.weightKg, closeTo(25, 0.001));
      expect(largeTv.vehicleSuitability, 'Van');
      expect(largeTv.weightBand, DeliveryPricing.weightBandFor(25).category);
      expect(largeTv.requiresVehicleReview, isTrue);
      expect(compactTv, isNotNull);
      expect(compactTv!.matchedItemName, '32" Television');
      expect(compactTv.weightKg, closeTo(5, 0.001));
      expect(compactTv.vehicleSuitability, 'Car');
      expect(unknownTv, isNotNull);
      expect(unknownTv!.matchedItemName, 'Television (size unknown)');
      expect(unknownTv.confidenceScore, closeTo(0.45, 0.001));
    });

    test('category fallback estimates common non-repository items', () {
      final bible = IrisWeightEstimator.knownProductEstimate('1 bible');
      final tenBibles = IrisWeightEstimator.knownProductEstimate('10 bible');
      final guitar = IrisWeightEstimator.knownProductEstimate('1 guitar');
      final tumbler = IrisWeightEstimator.knownProductEstimate('1 stanley cup');
      final phone = IrisWeightEstimator.knownProductEstimate('1 phone');

      expect(bible, isNotNull);
      expect(bible!.matchedItemName, 'Book / Bible');
      expect(bible.weightKg, closeTo(0.8, 0.001));
      expect(bible.weightSource, 'category_estimate');
      expect(bible.truthBand, 'Category Estimate');
      expect(DeliveryPricing.weightSourceLabel(bible.weightSource),
          'Category Estimate');

      expect(tenBibles, isNotNull);
      expect(tenBibles!.weightKg, closeTo(8, 0.001));
      expect(tenBibles.quantity, 10);

      expect(guitar, isNotNull);
      expect(guitar!.matchedItemName, 'Guitar');
      expect(guitar.weightKg, closeTo(4, 0.001));
      expect(guitar.vehicleSuitability, 'Car');
      expect(guitar.fragile, isTrue);
      expect(guitar.stackable, isFalse);

      expect(tumbler, isNotNull);
      expect(tumbler!.matchedItemName, 'Tumbler / Bottle');
      expect(tumbler.weightKg, closeTo(0.7, 0.001));

      expect(phone, isNotNull);
      expect(phone!.matchedItemName, 'Mobile phone');
      expect(phone.weightKg, closeTo(0.25, 0.001));
      expect(phone.vanguardRecommended, isTrue);
      expect(phone.valueSensitive, isTrue);
    });

    test('specific products still win before generic category fallback', () {
      final iphone16 = IrisWeightEstimator.knownProductEstimate('iphone 16');
      final macbookPro16 =
          IrisWeightEstimator.knownProductEstimate('macbook pro 16');

      expect(iphone16, isNotNull);
      expect(iphone16!.matchedItemName, 'Apple iPhone 16');
      expect(iphone16.weightSource, 'known_product_lookup');
      expect(iphone16.weightKg, closeTo(0.199, 0.001));

      expect(macbookPro16, isNotNull);
      expect(macbookPro16!.matchedItemName, 'MacBook Pro 16');
      expect(macbookPro16.weightSource, 'known_product_lookup');
      expect(macbookPro16.weightKg, closeTo(2.15, 0.001));
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
      expect(macBooks.singleItemWeightKg, closeTo(1.51, 0.001));
      expect(macBooks.weightKg, closeTo(7.55, 0.001));
      expect(
        macBooks.weightBand,
        DeliveryPricing.weightBandFor(7.55).category,
      );
    });

    test('category-first matching prevents wig and luggage drift', () {
      final category = IrisItemRepository.detectCategory('wigs');
      final match = IrisItemRepository.match('wigs');
      final estimate = IrisWeightEstimator.knownProductEstimate('wigs');

      expect(category?.category, 'Wigs & Hair');
      expect(category?.subcategory, 'Wigs');
      expect(match?.itemName, 'Wig');
      expect(match?.itemName, isNot(contains('Suitcase')));
      expect(estimate?.packageType, 'Wigs & Hair');
      expect(estimate?.weightKg, inInclusiveRange(0.3, 1.5));
      expect(estimate?.vehicleSuitability, isNot('Van'));
    });

    test('wig quantity scales within the hair category', () {
      final estimate = IrisWeightEstimator.knownProductEstimate('5 wigs');

      expect(estimate, isNotNull);
      expect(estimate!.matchedItemName, 'Wig');
      expect(estimate.quantity, 5);
      expect(estimate.weightKg, closeTo(3.5, 0.001));
      expect(estimate.packageType, 'Wigs & Hair');
    });

    test('beauty electronics and documents remain category-safe', () {
      final makeup = IrisWeightEstimator.knownProductEstimate('makeup kit');
      final phone = IrisWeightEstimator.knownProductEstimate('iPhone 13');
      final documents =
          IrisWeightEstimator.knownProductEstimate('documents for solicitor');

      expect(makeup?.packageType, 'Beauty');
      expect(makeup?.matchedItemName, 'Makeup Kit');
      expect(phone?.matchedItemName, 'Apple iPhone 13');
      expect(phone?.matchedItemName, isNot(contains('Suitcase')));
      expect(documents?.packageType, 'Documents');
      expect(documents?.vehicleSuitability, 'Bike');
    });

    test('bulky known items use realistic weights and quantity', () {
      final piano = IrisWeightEstimator.knownProductEstimate('piano');
      final wardrobes = IrisWeightEstimator.knownProductEstimate('7 wardrobes');

      expect(piano?.weightKg, isNot(20));
      expect(piano?.weightKg, greaterThan(20));
      expect(wardrobes?.quantity, 7);
      expect(wardrobes?.weightKg, 280);
    });

    test('unrelated repository additions cannot win a detected category', () {
      final category = IrisItemRepository.detectCategory('lace front wig');
      final match = IrisItemRepository.match('lace front wig');

      expect(category?.category, 'Wigs & Hair');
      expect(match?.category, 'Wigs & Hair');
      expect(match?.subcategory, 'Wigs');
    });
  });
}
