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

    test('canonical aliases resolve before semantic repository matching', () {
      expect(IrisItemRepository.resolveAlias('iphone')?.item.canonicalName,
          'Apple iPhone');
      expect(
          IrisItemRepository.resolveAlias('mobile phone')?.item.canonicalName,
          'Apple iPhone');
      expect(IrisItemRepository.resolveAlias('bike')?.item.canonicalName,
          'Bicycle');
      expect(
          IrisItemRepository.resolveAlias('mountain bike')?.item.canonicalName,
          'Bicycle');
      expect(IrisItemRepository.resolveAlias('road bike')?.item.canonicalName,
          'Bicycle');
      expect(IrisItemRepository.resolveAlias('PS5 Slim')?.item.canonicalName,
          'Sony PlayStation 5');
    });

    test('unknown item creates repository candidate without canonical writes',
        () {
      final candidate = IrisItemRepository.createCandidate(
        'unknown photography rig',
        estimatedWeightKg: 8,
      );

      expect(candidate.reviewStatus, 'pending_review');
      expect(candidate.normalizedText, 'unknown photography rig');
      expect(IrisItemRepository.match('unknown photography rig'), isNull);
    });

    test('learning candidates do not overwrite canonical records', () {
      final candidate = IrisItemRepository.createCandidate('PS5 Slim');
      final review = IrisItemRepository.reviewLearningCandidate(
        candidate: candidate,
        action: 'approve_alias',
        canonicalItemId: 'canonical_sony_playstation_5',
        adminUserId: 'admin-1',
        reason: 'Repeated customer wording.',
      );

      expect(review.action, 'approve_alias');
      expect(review.auditEvent['actionType'],
          'iris_repository_candidate_approve_alias');
      expect(IrisItemRepository.resolveAlias('PS5 Slim')?.item.canonicalName,
          'Sony PlayStation 5');
    });

    test('alias deletion and duplicate canonical merge preserve canonical data',
        () {
      final bike = IrisItemRepository.resolveAlias('bike')!.item;
      final mountainBike =
          IrisItemRepository.resolveAlias('mountain bike')!.item;

      expect(bike.id, mountainBike.id);
      expect(IrisItemRepository.items.where((item) => item.id == bike.id),
          hasLength(1));
      expect(bike.active, isTrue);
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

    test('iPhone 13 description returns canonical repository weight', () {
      final estimate =
          IrisWeightEstimator.knownProductEstimate('Apple iPhone 13 in a box');

      expect(estimate, isNotNull);
      expect(estimate!.weightKg, inInclusiveRange(0.3, 0.6));
      expect(estimate.weightBand, 'Small Parcel');
      expect(estimate.weightSource, 'repository_match');
      expect(estimate.confidence, 'high');
    });

    test('iPhone 15 uses canonical repository weight before legacy phone data',
        () {
      final estimate =
          IrisWeightEstimator.knownProductEstimate('iPhone 15 for delivery');

      expect(estimate, isNotNull);
      expect(estimate!.weightKg, inInclusiveRange(0.3, 0.6));
      expect(estimate.weightSource, 'repository_match');
      expect(DeliveryPricing.weightSourceLabel(estimate.weightSource),
          'Repository Match');
      expect(estimate.matchedItemName, 'Apple iPhone');
      expect(estimate.truthBand, 'Repository Match');
      expect(estimate.typicalDimensions?.label, '18 x 11 x 5 cm');
      expect(estimate.vehicleSuitability, 'Bike');
      expect(estimate.fragile, isTrue);
    });

    test('Apple iPhone aliases resolve to one canonical repository object', () {
      const aliases = [
        'iPhone',
        'Apple iPhone',
        'mobile phone',
        'iPhone 13',
        'iPhone 15 Pro',
      ];

      for (final alias in aliases) {
        final repositoryItem = IrisItemRepository.match(alias);
        final estimate = IrisWeightEstimator.knownProductEstimate(alias);

        expect(repositoryItem?.id, 'canonical_apple_iphone', reason: alias);
        expect(estimate, isNotNull, reason: alias);
        expect(estimate!.matchedItemName, 'Apple iPhone', reason: alias);
        expect(estimate.weightSource, 'repository_match', reason: alias);
        expect(estimate.weightKg, inInclusiveRange(0.2, 0.8), reason: alias);
        expect(estimate.weightBand, 'Small Parcel', reason: alias);
        expect(estimate.vehicleSuitability, 'Bike', reason: alias);
      }
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
        inInclusiveRange(0.3, 0.6),
      );
    });

    test('AirPods Pro returns catalogue weight', () {
      final estimate =
          IrisWeightEstimator.knownProductEstimate('AirPods Pro case');

      expect(estimate, isNotNull);
      expect(estimate!.weightKg, closeTo(0.176, 0.001));
      expect(estimate.weightBand, 'Small Parcel');
    });

    test('MacBook aliases resolve through the canonical repository first', () {
      final pro16 = IrisWeightEstimator.knownProductEstimate('MacBook Pro 16');
      final air13 = IrisWeightEstimator.knownProductEstimate('MacBook Air 13');
      final generic = IrisWeightEstimator.knownProductEstimate('MacBook');

      expect(pro16, isNotNull);
      expect(pro16!.matchedItemName, 'Apple MacBook');
      expect(pro16.weightSource, 'repository_match');
      expect(pro16.singleItemWeightKg, closeTo(2.1, 0.001));
      expect(air13, isNotNull);
      expect(air13!.matchedItemName, 'Apple MacBook');
      expect(air13.weightSource, 'repository_match');
      expect(air13.singleItemWeightKg, closeTo(2.1, 0.001));
      expect(generic, isNotNull);
      expect(generic!.matchedItemName, 'Apple MacBook');
      expect(generic.weightSource, 'repository_match');
      expect(generic.singleItemWeightKg, closeTo(2.1, 0.001));
      expect(generic.confidenceScore, closeTo(0.9, 0.001));
    });

    test('TV estimates use screen size before static fallback', () {
      final largeTv = IrisWeightEstimator.knownProductEstimate('65 inch tv');
      final compactTv = IrisWeightEstimator.knownProductEstimate('small tv');
      final unknownTv = IrisWeightEstimator.knownProductEstimate('television');

      expect(largeTv, isNotNull);
      expect(largeTv!.matchedItemName, '65 inch TV');
      expect(largeTv.weightKg, closeTo(27, 0.001));
      expect(largeTv.vehicleSuitability, 'Van');
      expect(largeTv.weightBand, DeliveryPricing.weightBandFor(27).category);
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

    test('canonical repository wins before generic category fallback', () {
      final iphone16 = IrisWeightEstimator.knownProductEstimate('iphone 16');
      final macbookPro16 =
          IrisWeightEstimator.knownProductEstimate('macbook pro 16');

      expect(iphone16, isNotNull);
      expect(iphone16!.matchedItemName, 'Apple iPhone');
      expect(iphone16.weightSource, 'repository_match');
      expect(iphone16.weightKg, closeTo(0.45, 0.001));

      expect(macbookPro16, isNotNull);
      expect(macbookPro16!.matchedItemName, 'Apple MacBook');
      expect(macbookPro16.weightSource, 'repository_match');
      expect(macbookPro16.weightKg, closeTo(2.1, 0.001));
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
        5.2,
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

      expect(decision.pricingWeightKg, inInclusiveRange(0.3, 0.6));
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
      expect(macBooks.singleItemWeightKg, closeTo(2.1, 0.001));
      expect(macBooks.weightKg, closeTo(10.5, 0.001));
      expect(
        macBooks.weightBand,
        DeliveryPricing.weightBandFor(10.5).category,
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
      expect(phone?.matchedItemName, 'Apple iPhone');
      expect(phone?.matchedItemName, isNot(contains('Suitcase')));
      expect(phone?.vehicleSuitability, 'Bike');
      expect(documents?.packageType, 'Documents');
      expect(documents?.vehicleSuitability, 'Bike');
    });

    test('transport-ready phone parcel handles boxed and unboxed language', () {
      final normal = IrisWeightEstimator.knownProductEstimate('iPhone');
      final boxed = IrisWeightEstimator.knownProductEstimate('boxed iPhone');
      final unboxed =
          IrisWeightEstimator.knownProductEstimate('unboxed iPhone');

      expect(normal, isNotNull);
      expect(boxed, isNotNull);
      expect(unboxed, isNotNull);
      expect(normal!.matchedItemName, boxed!.matchedItemName);
      expect(normal.weightKg, inInclusiveRange(0.3, 0.6));
      expect(boxed.weightKg, closeTo(normal.weightKg, 0.001));
      expect(unboxed!.weightKg, lessThan(normal.weightKg));
      expect(normal.vehicleSuitability, 'Bike');
      expect(boxed.vehicleSuitability, 'Bike');
      expect(unboxed.vehicleSuitability, 'Bike');
    });

    test(
        'vehicle recommendation keeps phones bike-minimum and laptops enclosed',
        () {
      final iphone = IrisWeightEstimator.knownProductEstimate('iPhone 16');
      final laptop = IrisWeightEstimator.knownProductEstimate('MacBook Pro 16');
      final genericPhone = IrisWeightEstimator.knownProductEstimate('1 phone');

      expect(iphone?.vehicleSuitability, 'Bike');
      expect(laptop?.vehicleSuitability, 'Car');
      expect(genericPhone?.vehicleSuitability, 'Bike');
    });

    test('vehicle recommendation keeps documents bike eligible', () {
      final documents =
          IrisWeightEstimator.knownProductEstimate('documents for solicitor');
      final passport = DeliveryPricing.resolveVehicleSuitability(
          weightKg: 0.2,
          description: 'passport documents',
          itemCategory: 'Documents');
      final keys = DeliveryPricing.resolveVehicleSuitability(
        weightKg: 0.1,
        description: 'keys and usb drive',
        itemCategory: 'Small accessories',
      );

      expect(documents?.vehicleSuitability, 'Bike');
      expect(passport.recommendedVehicle, 'Bike');
      expect(keys.recommendedVehicle, 'Bike');
    });

    test('vehicle recommendation escalates bulky and appliance items to van',
        () {
      final sofa = IrisWeightEstimator.knownProductEstimate('sofa');
      final appliance = DeliveryPricing.resolveVehicleSuitability(
        weightKg: 70,
        description: 'large appliance washing machine',
        itemCategory: 'Kitchen appliance',
        repositoryVehicleSuitability: 'Van',
      );
      final mattress = DeliveryPricing.resolveVehicleSuitability(
        weightKg: 30,
        description: 'mattress',
        itemCategory: 'Furniture',
      );
      final diningTable = DeliveryPricing.resolveVehicleSuitability(
        weightKg: 35,
        description: 'dining table',
        itemCategory: 'Furniture',
      );
      final bicycle = DeliveryPricing.resolveVehicleSuitability(
        weightKg: 12,
        description: 'bicycle',
        itemCategory: 'Bike',
      );
      final wheelchair = DeliveryPricing.resolveVehicleSuitability(
        weightKg: 28,
        description: 'wheelchair where size requires van handling',
        itemCategory: 'Medical equipment',
      );
      final largeTv = IrisWeightEstimator.knownProductEstimate('65 inch tv');

      expect(sofa?.vehicleSuitability, 'Van');
      expect(appliance.recommendedVehicle, 'Van');
      expect(mattress.recommendedVehicle, 'Van');
      expect(diningTable.recommendedVehicle, 'Van');
      expect(bicycle.recommendedVehicle, 'Van');
      expect(wheelchair.recommendedVehicle, 'Van');
      expect(largeTv?.vehicleSuitability, 'Van');
    });

    test('vehicle recommendation escalates multiple small electronics to car',
        () {
      final bundle = DeliveryPricing.resolveVehicleSuitability(
        weightKg: 8,
        description: 'electronics bundle with multiple small items',
        itemCategory: 'Electronics',
        repositoryVehicleSuitability: 'Bike',
        highValue: true,
        vanguardRequired: true,
        fragile: true,
        quantity: 6,
        singleItemWeightKg: 1.3,
      );

      expect(bundle.recommendedVehicle, 'Car');
      expect(bundle.explanation.toLowerCase(), isNot(contains('bike')));
    });

    test('vehicle recommendation keeps delicate care items in cars', () {
      final flowers = DeliveryPricing.resolveVehicleSuitability(
        weightKg: 2,
        description: 'flowers requiring careful handling',
        itemCategory: 'Flowers',
      );
      final cake = DeliveryPricing.resolveVehicleSuitability(
        weightKg: 3,
        description: 'birthday cake',
        itemCategory: 'Food',
      );
      final medical = DeliveryPricing.resolveVehicleSuitability(
        weightKg: 4,
        description: 'small medical equipment',
        itemCategory: 'Medical equipment',
      );

      expect(flowers.recommendedVehicle, 'Car');
      expect(cake.recommendedVehicle, 'Car');
      expect(medical.recommendedVehicle, 'Car');
    });

    test('vehicle recommendation uses highest requirement for mixed items', () {
      final documentsAndPhone = DeliveryPricing.resolveVehicleSuitability(
        weightKg: 1,
        description: 'documents and iPhone',
        itemCategory: 'Mixed items',
        highValue: true,
        vanguardRequired: true,
      );
      final chairAndDocuments = DeliveryPricing.resolveVehicleSuitability(
        weightKg: 12,
        description: 'chair and documents',
        itemCategory: 'Mixed items',
      );

      expect(documentsAndPhone.recommendedVehicle, 'Bike');
      expect(chairAndDocuments.recommendedVehicle, 'Van');
    });

    test('vehicle reasoning cannot contradict recommendation', () {
      final suitability = DeliveryPricing.resolveVehicleSuitability(
        weightKg: 0.2,
        description: 'iPhone 16',
        itemCategory: 'Electronics',
        repositoryVehicleSuitability: 'Bike',
        highValue: true,
        vanguardRequired: true,
        fragile: true,
      );

      expect(suitability.recommendedVehicle, 'Bike');
      expect(suitability.explanation, contains('Bike recommended'));
    });

    test('bulky known items use realistic weights and quantity', () {
      final piano = IrisWeightEstimator.knownProductEstimate('piano');
      final wardrobes = IrisWeightEstimator.knownProductEstimate('7 wardrobes');

      expect(piano?.weightKg, isNot(20));
      expect(piano?.weightKg, greaterThan(20));
      expect(wardrobes?.quantity, 7);
      expect(wardrobes?.weightKg, 315);
    });

    test('unrelated repository additions cannot win a detected category', () {
      final category = IrisItemRepository.detectCategory('lace front wig');
      final match = IrisItemRepository.match('lace front wig');

      expect(category?.category, 'Wigs & Hair');
      expect(match?.category, 'Wigs & Hair');
      expect(match?.subcategory, 'Wigs');
    });

    test('launch blocker: iPhone never inherits polluted heavy history', () {
      final estimate = IrisWeightEstimator.knownProductEstimate('iPhone');

      expect(estimate, isNotNull);
      expect(estimate!.weightKg, inInclusiveRange(0.2, 0.8));
      expect(estimate.weightBand, 'Small Parcel');
      expect(estimate.matchedItemName.toLowerCase(), contains('iphone'));
      expect(estimate.matchedItemName, isNot(contains('Suitcase')));
      expect(estimate.weightKg, lessThan(2));
    });

    test('iPhone canonical pricing ignores 9kg historical outlier', () {
      final estimate = IrisWeightEstimator.knownProductEstimate('iPhone')!;
      final decision = IrisWeightEstimator.resolveTrustedKnownItemPricing(
        description: 'iPhone',
        quantity: estimate.quantity,
        userWeightKg: 0,
        trustedItemWeightKg: estimate.weightKg,
        historicalMatches: const [9],
        trustedWeightIsTransportReady:
            estimate.weightSource == 'repository_match',
      );

      expect(estimate.weightKg, closeTo(0.45, 0.001));
      expect(decision.pricingWeightKg, closeTo(0.5, 0.001));
      expect(decision.pricingWeightKg, isNot(closeTo(0.6, 0.001)));
      expect(decision.ignoredHistoricalOutliers, contains(9));
    });

    test('phone aliases use repository weight plus only minimum billable floor',
        () {
      const aliases = [
        'iPhone',
        'Apple iPhone',
        'iPhone 13',
        'iPhone 15 Pro',
        'mobile phone',
      ];

      for (final alias in aliases) {
        final estimate = IrisWeightEstimator.knownProductEstimate(alias)!;
        final decision = IrisWeightEstimator.resolveTrustedKnownItemPricing(
          description: alias,
          quantity: estimate.quantity,
          userWeightKg: 0,
          trustedItemWeightKg: estimate.weightKg,
          trustedWeightIsTransportReady:
              estimate.weightSource == 'repository_match',
        );

        expect(estimate.matchedItemName, 'Apple iPhone', reason: alias);
        expect(estimate.weightSource, 'repository_match', reason: alias);
        expect(estimate.weightKg, closeTo(0.45, 0.001), reason: alias);
        expect(decision.pricingWeightKg, closeTo(0.5, 0.001), reason: alias);
        expect(decision.pricingWeightKg, isNot(closeTo(0.6, 0.001)),
            reason: alias);
        expect(decision.explanation, contains('minimum billable'),
            reason: alias);
      }
    });

    test('MacBook estimates ignore historical completed-delivery outliers', () {
      const cases = [
        ('MacBook', 'Apple MacBook', 'repository_match', 2.1),
        ('MacBook Air', 'Apple MacBook', 'repository_match', 2.1),
        ('MacBook Pro 14', 'Apple MacBook', 'repository_match', 2.1),
        ('MacBook Pro 16', 'Apple MacBook', 'repository_match', 2.1),
      ];

      for (final item in cases) {
        final estimate = IrisWeightEstimator.knownProductEstimate(item.$1)!;
        final decision = IrisWeightEstimator.resolveTrustedKnownItemPricing(
          description: item.$1,
          quantity: estimate.quantity,
          userWeightKg: 0,
          trustedItemWeightKg: estimate.weightKg,
          historicalMatches: const [16.4],
          trustedWeightIsTransportReady:
              estimate.weightSource == 'repository_match' ||
                  estimate.weightSource == 'known_product_lookup',
        );

        expect(estimate.matchedItemName, item.$2, reason: item.$1);
        expect(estimate.weightSource, item.$3, reason: item.$1);
        expect(estimate.weightKg, closeTo(item.$4, 0.001), reason: item.$1);
        expect(decision.pricingWeightKg, closeTo(item.$4, 0.001),
            reason: item.$1);
        expect(decision.pricingWeightKg, isNot(closeTo(16.4, 0.001)),
            reason: item.$1);
        expect(decision.ignoredHistoricalOutliers, contains(16.4),
            reason: item.$1);
      }
    });

    test('three iPhones remain a realistic small bundled phone parcel', () {
      final estimate = IrisWeightEstimator.knownProductEstimate('3 iPhones');

      expect(estimate, isNotNull);
      expect(estimate!.matchedItemName, 'Apple iPhone');
      expect(estimate.quantity, 3);
      expect(estimate.weightKg, inInclusiveRange(0.6, 2.4));
      expect(estimate.weightBand, 'Small Parcel');
      expect(estimate.vehicleSuitability, 'Bike');
    });

    test('launch blocker: 5kg rice does not match suitcase luggage', () {
      final estimate = IrisWeightEstimator.knownProductEstimate('5kg rice');

      expect(estimate, isNotNull);
      expect(estimate!.matchedItemName, 'Rice / Grocery bag');
      expect(estimate.packageType, 'Food');
      expect(estimate.matchedItemName, isNot(contains('Suitcase')));
      expect(estimate.weightKg, inInclusiveRange(5, 6));
      expect(estimate.weightBand, 'Medium Parcel');
    });

    test('launch blocker sanity bands stay plausible by category', () {
      final tv = IrisWeightEstimator.knownProductEstimate('65 inch TV');
      final ipad = IrisWeightEstimator.knownProductEstimate('iPad');
      final chair =
          IrisWeightEstimator.knownProductEstimate('office chair boxed');
      final hamper = IrisWeightEstimator.knownProductEstimate('food hamper');

      expect(tv, isNotNull);
      expect(tv!.weightKg, inInclusiveRange(20, 35));
      expect(tv.vehicleSuitability, 'Van');

      expect(ipad, isNotNull);
      expect(ipad!.weightKg, inInclusiveRange(0.5, 1.5));
      expect(ipad.weightBand, 'Small Parcel');

      expect(chair, isNotNull);
      expect(chair!.weightKg, inInclusiveRange(10, 25));
      expect(chair.vehicleSuitability, 'Van');

      expect(hamper, isNotNull);
      expect(hamper!.weightKg, inInclusiveRange(3, 10));
      expect(hamper.weightBand, 'Medium Parcel');
    });

    test('phase 2 confidence handling drives pricing behaviour', () {
      expect(
        IrisWeightEstimator.confidenceHandlingFor(0.96).action,
        'price_immediately',
      );
      expect(
        IrisWeightEstimator.confidenceHandlingFor(0.84).action,
        'price_normally_with_rider_verification',
      );
      expect(
        IrisWeightEstimator.confidenceHandlingFor(0.72).shouldAskClarification,
        isTrue,
      );
      expect(
        IrisWeightEstimator.confidenceHandlingFor(0.45)
            .shouldRequestPhotoOrDimensions,
        isTrue,
      );
    });

    test('phase 2 verified learning only applies clean verified outcomes', () {
      final estimate = IrisWeightEstimator.knownProductEstimate('iPhone')!;
      final clean = IrisWeightEstimator.verifiedLearningDecision(
        estimate: estimate,
        finalVerifiedWeightKg: estimate.weightKg,
        riderVerified: true,
        disputeOccurred: false,
        adminOverrode: false,
      );
      final disputed = IrisWeightEstimator.verifiedLearningDecision(
        estimate: estimate,
        finalVerifiedWeightKg: 9,
        riderVerified: true,
        disputeOccurred: true,
        adminOverrode: false,
      );

      expect(clean.canApplyToRepository, isTrue);
      expect(clean.shouldCreateReviewCandidate, isFalse);
      expect(disputed.canApplyToRepository, isFalse);
      expect(disputed.shouldCreateReviewCandidate, isTrue);
      expect(disputed.reasons, contains('dispute_occurred'));
      expect(
        disputed.reasons,
        contains('verified_weight_outside_expected_range'),
      );
    });

    test('launch regression suite keeps canonical items authoritative', () {
      const cases = [
        _IrisRegressionCase(
          description: 'passport',
          matchedItemName: 'Passport / document envelope',
          category: 'Documents',
          minKg: 0.05,
          maxKg: 1,
          parcelClass: 'Small Parcel',
          minimumVehicle: 'Bike',
          bannedTerms: ['suitcase', 'wardrobe', 'chair'],
        ),
        _IrisRegressionCase(
          description: 'document envelope',
          matchedItemName: 'Passport / document envelope',
          category: 'Documents',
          minKg: 0.05,
          maxKg: 1,
          parcelClass: 'Small Parcel',
          minimumVehicle: 'Bike',
          bannedTerms: ['suitcase', 'wardrobe', 'chair'],
        ),
        _IrisRegressionCase(
          description: 'iPhone',
          matchedItemName: 'Apple iPhone',
          category: 'Electronics',
          minKg: 0.2,
          maxKg: 0.8,
          parcelClass: 'Small Parcel',
          minimumVehicle: 'Bike',
          bannedTerms: ['suitcase', 'wardrobe', 'chair'],
        ),
        _IrisRegressionCase(
          description: 'iPhone 13',
          matchedItemName: 'Apple iPhone',
          category: 'Electronics',
          minKg: 0.2,
          maxKg: 0.8,
          parcelClass: 'Small Parcel',
          minimumVehicle: 'Bike',
          bannedTerms: ['suitcase', 'wardrobe', 'chair'],
        ),
        _IrisRegressionCase(
          description: 'mobile phone',
          matchedItemName: 'Apple iPhone',
          category: 'Electronics',
          minKg: 0.2,
          maxKg: 0.8,
          parcelClass: 'Small Parcel',
          minimumVehicle: 'Bike',
          bannedTerms: ['suitcase', 'wardrobe', 'chair'],
        ),
        _IrisRegressionCase(
          description: 'MacBook',
          matchedItemName: 'Apple MacBook',
          category: 'Electronics',
          minKg: 1.2,
          maxKg: 3.2,
          parcelClass: 'Small Parcel',
          minimumVehicle: 'Car',
          bannedTerms: ['suitcase', 'wardrobe'],
        ),
        _IrisRegressionCase(
          description: 'MacBook Air',
          matchedItemName: 'Apple MacBook',
          category: 'Electronics',
          minKg: 1.2,
          maxKg: 3.2,
          parcelClass: 'Small Parcel',
          minimumVehicle: 'Car',
          bannedTerms: ['suitcase', 'wardrobe'],
        ),
        _IrisRegressionCase(
          description: 'MacBook Pro',
          matchedItemName: 'Apple MacBook',
          category: 'Electronics',
          minKg: 1.2,
          maxKg: 3.2,
          parcelClass: 'Small Parcel',
          minimumVehicle: 'Car',
          bannedTerms: ['suitcase', 'wardrobe'],
        ),
        _IrisRegressionCase(
          description: 'iPad',
          matchedItemName: 'Tablet / iPad',
          category: 'Electronics',
          minKg: 0.5,
          maxKg: 1.5,
          parcelClass: 'Small Parcel',
          minimumVehicle: 'Car',
          bannedTerms: ['suitcase', 'wardrobe'],
        ),
        _IrisRegressionCase(
          description: 'tablet',
          matchedItemName: 'Tablet / iPad',
          category: 'Electronics',
          minKg: 0.5,
          maxKg: 1.5,
          parcelClass: 'Small Parcel',
          minimumVehicle: 'Car',
          bannedTerms: ['suitcase', 'wardrobe'],
        ),
        _IrisRegressionCase(
          description: '65 inch TV',
          matchedItemName: '65 inch TV',
          category: 'Electronics',
          minKg: 20,
          maxKg: 35,
          parcelClass: 'Large Item',
          minimumVehicle: 'Van',
          bannedTerms: ['wardrobe', 'suitcase'],
        ),
        _IrisRegressionCase(
          description: 'bicycle',
          matchedItemName: 'Bicycle',
          category: 'Sports equipment',
          minKg: 10,
          maxKg: 25,
          parcelClass: 'Heavy Parcel',
          minimumVehicle: 'Van',
          bannedTerms: ['iphone', 'television'],
        ),
        _IrisRegressionCase(
          description: 'dining table',
          matchedItemName: 'Dining table',
          category: 'Household',
          minKg: 18,
          maxKg: 60,
          parcelClass: 'Large Item',
          minimumVehicle: 'Van',
          bannedTerms: ['iphone', 'television'],
        ),
        _IrisRegressionCase(
          description: 'mattress',
          matchedItemName: 'Mattress',
          category: 'Household',
          minKg: 15,
          maxKg: 45,
          parcelClass: 'Large Item',
          minimumVehicle: 'Van',
          bannedTerms: ['iphone', 'television'],
        ),
        _IrisRegressionCase(
          description: 'suitcase',
          matchedItemName: 'Suitcase',
          category: 'Luggage',
          minKg: 1,
          maxKg: 32,
          parcelClass: 'Heavy Parcel',
          minimumVehicle: 'Car',
          bannedTerms: ['iphone', 'wardrobe'],
        ),
        _IrisRegressionCase(
          description: 'toolbox',
          matchedItemName: 'Toolbox',
          category: 'Tools',
          minKg: 4,
          maxKg: 25,
          parcelClass: 'Heavy Parcel',
          minimumVehicle: 'Car',
          bannedTerms: ['iphone', 'suitcase'],
        ),
      ];

      for (final item in cases) {
        final estimate =
            IrisWeightEstimator.knownProductEstimate(item.description);
        expect(estimate, isNotNull, reason: item.description);
        final result = estimate!;
        expect(result.matchedItemName, item.matchedItemName,
            reason: item.description);
        expect(result.packageType.toLowerCase(),
            contains(item.category.toLowerCase()),
            reason: item.description);
        expect(result.weightKg, inInclusiveRange(item.minKg, item.maxKg),
            reason: item.description);
        expect(result.weightBand, item.parcelClass, reason: item.description);
        expect(result.vehicleSuitability, item.minimumVehicle,
            reason: item.description);
        expect(
          DeliveryPricing.eligibleVehiclesForMinimum(result.vehicleSuitability),
          item.eligibleVehicles,
          reason: item.description,
        );
        final decision = IrisWeightEstimator.resolveTrustedKnownItemPricing(
          description: item.description,
          quantity: result.quantity,
          userWeightKg: 0,
          trustedItemWeightKg: result.weightKg,
          historicalMatches: const [120],
          trustedWeightIsTransportReady:
              result.weightSource == 'repository_match' ||
                  result.weightSource == 'known_product_lookup',
        );
        expect(
            decision.pricingWeightKg, inInclusiveRange(item.minKg, item.maxKg),
            reason: item.description);
        expect(decision.pricingWeightKg, isNot(closeTo(120, 0.001)),
            reason: item.description);
        expect(decision.ignoredHistoricalOutliers, contains(120),
            reason: item.description);
        expect(['high', 'medium', 'low'], contains(result.confidence),
            reason: item.description);
        expect(
          result.truthBand == 'Exact Match',
          result.confidence == 'high' &&
              result.weightSource == 'known_product_lookup' &&
              result.matchedItemName != 'Apple iPhone' &&
              result.matchedItemName != 'Tablet / iPad',
          reason: item.description,
        );
        for (final banned in item.bannedTerms) {
          expect(result.matchedItemName.toLowerCase(), isNot(contains(banned)),
              reason: item.description);
        }
      }
    });
  });
}

class _IrisRegressionCase {
  final String description;
  final String matchedItemName;
  final String category;
  final double minKg;
  final double maxKg;
  final String parcelClass;
  final String minimumVehicle;
  final List<String> bannedTerms;

  const _IrisRegressionCase({
    required this.description,
    required this.matchedItemName,
    required this.category,
    required this.minKg,
    required this.maxKg,
    required this.parcelClass,
    required this.minimumVehicle,
    required this.bannedTerms,
  });

  List<String> get eligibleVehicles =>
      DeliveryPricing.eligibleVehiclesForMinimum(minimumVehicle);
}
