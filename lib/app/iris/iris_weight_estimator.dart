import 'dart:math' as math;

import 'package:circum/app/iris/iris_item_repository.dart';
import 'package:circum/pricing/delivery_pricing.dart';

class IrisWeightLookupResult {
  final String matchedItemName;
  final int quantity;
  final double singleItemWeightKg;
  final double weightKg;
  final String weightBand;
  final String confidence;
  final double confidenceScore;
  final String explanation;
  final String packageType;
  final String weightSource;
  final String truthBand;
  final bool requiresVehicleReview;
  final ItemDimensionsCm? typicalDimensions;
  final String vehicleSuitability;
  final bool fragile;
  final bool valueSensitive;
  final bool vanguardRecommended;
  final bool stackable;
  final String handlingNotes;

  const IrisWeightLookupResult({
    required this.matchedItemName,
    required this.quantity,
    required this.singleItemWeightKg,
    required this.weightKg,
    required this.weightBand,
    required this.confidence,
    required this.confidenceScore,
    required this.explanation,
    required this.packageType,
    required this.weightSource,
    required this.truthBand,
    required this.requiresVehicleReview,
    required this.typicalDimensions,
    required this.vehicleSuitability,
    required this.fragile,
    required this.valueSensitive,
    required this.vanguardRecommended,
    required this.stackable,
    required this.handlingNotes,
  });

  IrisConfidenceHandling get confidenceHandling =>
      IrisWeightEstimator.confidenceHandlingFor(confidenceScore);
}

class IrisConfidenceHandling {
  final String label;
  final String action;
  final bool canPriceImmediately;
  final bool shouldAskClarification;
  final bool shouldRequestPhotoOrDimensions;

  const IrisConfidenceHandling({
    required this.label,
    required this.action,
    required this.canPriceImmediately,
    required this.shouldAskClarification,
    required this.shouldRequestPhotoOrDimensions,
  });
}

class IrisVerifiedLearningDecision {
  final bool canApplyToRepository;
  final bool shouldCreateReviewCandidate;
  final List<String> reasons;

  const IrisVerifiedLearningDecision({
    required this.canApplyToRepository,
    required this.shouldCreateReviewCandidate,
    required this.reasons,
  });
}

class ItemDimensionsCm {
  final double length;
  final double width;
  final double height;

  const ItemDimensionsCm({
    required this.length,
    required this.width,
    required this.height,
  });

  String get label =>
      '${length.toStringAsFixed(0)} x ${width.toStringAsFixed(0)} x ${height.toStringAsFixed(0)} cm';
}

class IrisWeightEstimator {
  static IrisConfidenceHandling confidenceHandlingFor(double confidenceScore) {
    final score =
        confidenceScore <= 1 ? confidenceScore * 100 : confidenceScore;
    if (score >= 95) {
      return const IrisConfidenceHandling(
        label: 'high',
        action: 'price_immediately',
        canPriceImmediately: true,
        shouldAskClarification: false,
        shouldRequestPhotoOrDimensions: false,
      );
    }
    if (score >= 80) {
      return const IrisConfidenceHandling(
        label: 'high',
        action: 'price_normally_with_rider_verification',
        canPriceImmediately: true,
        shouldAskClarification: false,
        shouldRequestPhotoOrDimensions: false,
      );
    }
    if (score >= 60) {
      return const IrisConfidenceHandling(
        label: 'medium',
        action: 'ask_one_clarification_or_dimensions',
        canPriceImmediately: false,
        shouldAskClarification: true,
        shouldRequestPhotoOrDimensions: false,
      );
    }
    return const IrisConfidenceHandling(
      label: 'low',
      action: 'request_photo_or_dimensions_before_final_pricing',
      canPriceImmediately: false,
      shouldAskClarification: false,
      shouldRequestPhotoOrDimensions: true,
    );
  }

  static IrisVerifiedLearningDecision verifiedLearningDecision({
    required IrisWeightLookupResult estimate,
    required double finalVerifiedWeightKg,
    required bool riderVerified,
    required bool disputeOccurred,
    required bool adminOverrode,
    ItemDimensionsCm? finalVerifiedDimensions,
  }) {
    final reasons = <String>[];
    if (!riderVerified) reasons.add('rider_not_verified');
    if (disputeOccurred) reasons.add('dispute_occurred');
    if (adminOverrode) reasons.add('admin_overrode');
    if (finalVerifiedWeightKg <= 0) reasons.add('invalid_verified_weight');
    final lower = estimate.singleItemWeightKg * estimate.quantity * 0.45;
    final upper = estimate.singleItemWeightKg * estimate.quantity * 2.25;
    if (finalVerifiedWeightKg < lower || finalVerifiedWeightKg > upper) {
      reasons.add('verified_weight_outside_expected_range');
    }
    final expectedDimensions = estimate.typicalDimensions;
    if (finalVerifiedDimensions != null && expectedDimensions != null) {
      final plausible =
          finalVerifiedDimensions.length <= expectedDimensions.length * 2.5 &&
              finalVerifiedDimensions.width <= expectedDimensions.width * 2.5 &&
              finalVerifiedDimensions.height <= expectedDimensions.height * 2.5;
      if (!plausible) reasons.add('verified_dimensions_outside_expected_range');
    }
    return IrisVerifiedLearningDecision(
      canApplyToRepository: reasons.isEmpty,
      shouldCreateReviewCandidate: reasons.isNotEmpty,
      reasons: reasons,
    );
  }

  static int extractQuantity(String description) {
    final text = description.trim().toLowerCase();
    if (text.isEmpty) return 1;
    final leading = RegExp(r'^\s*(\d+)\s*(?:[x×]\s*)?').firstMatch(text);
    final suffix = RegExp(r'\b[x×]\s*(\d+)\b').firstMatch(text);
    final parsed = int.tryParse(leading?.group(1) ?? suffix?.group(1) ?? '1');
    return parsed == null || parsed < 1 ? 1 : parsed;
  }

  static IrisWeightLookupResult? knownProductEstimate(
    String description, {
    Iterable<String> photoLabels = const [],
  }) {
    final text = description.trim().toLowerCase();
    final quantity = extractQuantity(description);
    if (text.contains('tv') || text.contains('television')) {
      final tvEstimate = _estimateTvBySize(text, quantity);
      if (tvEstimate != null) return tvEstimate;
    }
    if (_isPhoneAlias(text) && !_explicitlyLooseOrUnboxed(text)) {
      final phoneItem = _canonicalRepositoryItem('canonical_apple_iphone');
      if (phoneItem != null) {
        return _repositoryEstimate(
          repositoryItem: phoneItem,
          description: description,
          quantity: quantity,
        );
      }
    }
    if (_isGenericMacBookAlias(text) && !_explicitlyLooseOrUnboxed(text)) {
      final macBookItem = _canonicalRepositoryItem('canonical_macbook');
      if (macBookItem != null) {
        return _repositoryEstimate(
          repositoryItem: macBookItem,
          description: description,
          quantity: quantity,
        );
      }
    }
    for (final product in _knownProducts) {
      if (product.patterns.any(text.contains)) {
        final electronics = product.packageType == 'Electronics';
        final singleTransportReadyWeightKg = _transportReadySingleWeightKg(
          product.weightKg,
          description: text,
          packageType: product.packageType,
        );
        final totalWeightKg = singleTransportReadyWeightKg * quantity;
        final band = DeliveryPricing.weightBandFor(totalWeightKg).category;
        final vehicle = _resolveCanonicalVehicle(
          totalWeightKg: totalWeightKg,
          description: description,
          packageType: product.packageType,
          dimensions: product.typicalDimensions,
          repositoryVehicleSuitability: product.vehicleSuitability,
          fragile: product.fragile,
          highValue: electronics,
          vanguardRequired: electronics,
          stackable: product.stackable,
          quantity: quantity,
          singleItemWeightKg: singleTransportReadyWeightKg,
          handlingNotes: product.handlingNotes,
        );
        return IrisWeightLookupResult(
          matchedItemName: product.name,
          quantity: quantity,
          singleItemWeightKg: singleTransportReadyWeightKg,
          weightKg: totalWeightKg,
          weightBand: band,
          confidence: product.confidence,
          confidenceScore: product.confidenceScore,
          explanation: quantity == 1
              ? 'Iris matched the description to ${product.name} using Circum known-product data.'
              : 'Iris matched $quantity × ${product.name} using Circum known-product data.',
          packageType: product.packageType,
          weightSource: 'known_product_lookup',
          truthBand: product.truthBand,
          requiresVehicleReview:
              totalWeightKg > 10 || vehicle.recommendedVehicle == 'Van',
          typicalDimensions: product.typicalDimensions,
          vehicleSuitability: vehicle.recommendedVehicle,
          fragile: product.fragile,
          valueSensitive: electronics,
          vanguardRecommended: electronics,
          stackable: product.stackable,
          handlingNotes: product.handlingNotes,
        );
      }
    }
    final repositoryItem = IrisItemRepository.match(
      description,
      photoLabels: photoLabels,
    );
    if (repositoryItem != null) {
      return _repositoryEstimate(
        repositoryItem: repositoryItem,
        description: description,
        quantity: quantity,
      );
    }
    final categoryEstimate = _categoryFallbackEstimate(text, quantity);
    if (categoryEstimate != null) return categoryEstimate;
    return null;
  }

  static IrisWeightLookupResult? _categoryFallbackEstimate(
    String text,
    int quantity,
  ) {
    for (final fallback in _categoryFallbacks) {
      if (!fallback.patterns.any(text.contains)) continue;
      final explicitWeightKg = _hasExplicitWeightUnit(text)
          ? DeliveryPricing.parseWeightKg(text, fallbackKg: 0)
          : 0.0;
      final safeQuantity = explicitWeightKg > 0
          ? 1
          : quantity <= 0
              ? 1
              : quantity;
      final totalWeightKg = explicitWeightKg > 0
          ? _normaliseFallbackExplicitWeight(text, explicitWeightKg)
          : fallback.weightKg * safeQuantity;
      final vehicle = _resolveCanonicalVehicle(
        totalWeightKg: totalWeightKg,
        description: text,
        packageType: fallback.packageType,
        dimensions: fallback.typicalDimensions,
        repositoryVehicleSuitability: fallback.vehicleSuitability,
        fragile: fallback.fragile,
        highValue: fallback.valueSensitive,
        vanguardRequired: fallback.vanguardRecommended,
        stackable: fallback.stackable,
        quantity: safeQuantity,
        singleItemWeightKg: fallback.weightKg,
        handlingNotes: fallback.handlingNotes,
      );
      return IrisWeightLookupResult(
        matchedItemName: fallback.name,
        quantity: safeQuantity,
        singleItemWeightKg:
            explicitWeightKg > 0 ? totalWeightKg : fallback.weightKg,
        weightKg: totalWeightKg,
        weightBand: DeliveryPricing.weightBandFor(totalWeightKg).category,
        confidence: fallback.confidence,
        confidenceScore: fallback.confidenceScore,
        explanation:
            'IRIS estimated this from the item category. Rider will verify at pickup.',
        packageType: fallback.packageType,
        weightSource: 'category_estimate',
        truthBand: 'Category Estimate',
        requiresVehicleReview: vehicle.recommendedVehicle == 'Van' ||
            totalWeightKg > 10 ||
            fallback.requiresVehicleReview,
        typicalDimensions: fallback.typicalDimensions,
        vehicleSuitability: vehicle.recommendedVehicle,
        fragile: fallback.fragile,
        valueSensitive: fallback.valueSensitive,
        vanguardRecommended: fallback.vanguardRecommended,
        stackable: fallback.stackable,
        handlingNotes: fallback.handlingNotes,
      );
    }
    return null;
  }

  static bool _isPhoneAlias(String text) {
    return RegExp(
      r'\b(i\s?phones?(?:\s?(?:1[3-6]|pro|max|pro max))?|apple iphones?|mobile phones?|smartphones?|cell phones?)\b',
    ).hasMatch(text);
  }

  static bool _isGenericMacBookAlias(String text) {
    if (!RegExp(r'\b(macbook|apple laptop|laptop)\b').hasMatch(text)) {
      return false;
    }
    return !RegExp(
            r'\b(macbook\s+(?:air|pro)|pro\s*(?:13|14|16)|air\s*(?:13|15))\b')
        .hasMatch(text);
  }

  static IrisRepositoryItem? _canonicalRepositoryItem(String id) {
    for (final item in IrisItemRepository.items) {
      if (item.id == id) return item;
    }
    return null;
  }

  static IrisWeightLookupResult _repositoryEstimate({
    required IrisRepositoryItem repositoryItem,
    required String description,
    required int quantity,
  }) {
    final totalWeightKg = repositoryItem.estimatedWeightKg * quantity;
    final band = DeliveryPricing.weightBandFor(totalWeightKg).category;
    final dimensions = repositoryItem.typicalDimensionsCm;
    final typicalDimensions = ItemDimensionsCm(
      length: dimensions.lengthCm,
      width: dimensions.widthCm,
      height: dimensions.heightCm,
    );
    final vehicle = _resolveCanonicalVehicle(
      totalWeightKg: totalWeightKg,
      description: description,
      packageType: repositoryItem.category,
      dimensions: typicalDimensions,
      repositoryVehicleSuitability: repositoryItem.vehicleSuitability,
      fragile: repositoryItem.fragile,
      highValue: repositoryItem.highValue,
      vanguardRequired: repositoryItem.requiresVanguard,
      stackable: repositoryItem.stackable,
      quantity: quantity,
      singleItemWeightKg: repositoryItem.estimatedWeightKg,
      handlingNotes: repositoryItem.deliveryNotes,
    );
    return IrisWeightLookupResult(
      matchedItemName: repositoryItem.itemName,
      quantity: quantity,
      singleItemWeightKg: repositoryItem.estimatedWeightKg,
      weightKg: totalWeightKg,
      weightBand: band,
      confidence: repositoryItem.confidenceBaseline >= 0.85
          ? 'high'
          : repositoryItem.confidenceBaseline >= 0.65
              ? 'medium'
              : 'low',
      confidenceScore: repositoryItem.confidenceBaseline,
      explanation: quantity == 1
          ? 'Iris matched the description to ${repositoryItem.itemName} using the Circum item repository.'
          : 'Iris matched $quantity × ${repositoryItem.itemName} using the Circum item repository.',
      packageType: repositoryItem.category,
      weightSource: 'repository_match',
      truthBand: repositoryItem.confidenceBaseline >= 0.85
          ? 'Repository Match'
          : 'Medium Confidence',
      requiresVehicleReview: repositoryItem.requiresIRISReview ||
          totalWeightKg > 10 ||
          vehicle.recommendedVehicle == 'Van',
      typicalDimensions: typicalDimensions,
      vehicleSuitability: vehicle.recommendedVehicle,
      fragile: repositoryItem.fragile,
      valueSensitive: repositoryItem.highValue,
      vanguardRecommended: repositoryItem.requiresVanguard,
      stackable: repositoryItem.stackable,
      handlingNotes: repositoryItem.deliveryNotes,
    );
  }

  static VehicleSuitability _resolveCanonicalVehicle({
    required double totalWeightKg,
    required String description,
    required String packageType,
    required ItemDimensionsCm? dimensions,
    required String repositoryVehicleSuitability,
    required bool fragile,
    required bool highValue,
    required bool vanguardRequired,
    required bool stackable,
    required int quantity,
    required double singleItemWeightKg,
    required String handlingNotes,
  }) {
    return DeliveryPricing.resolveVehicleSuitability(
      weightKg: totalWeightKg,
      description: description,
      itemCategory: packageType,
      dimensions: dimensions == null
          ? null
          : DeliveryItemDimensions(
              lengthCm: dimensions.length,
              widthCm: dimensions.width,
              heightCm: dimensions.height,
            ),
      repositoryVehicleSuitability: repositoryVehicleSuitability,
      fragile: fragile,
      highValue: highValue,
      vanguardRequired: vanguardRequired,
      stackable: stackable,
      quantity: quantity,
      singleItemWeightKg: singleItemWeightKg,
      handlingNotes: handlingNotes,
    );
  }

  static IrisWeightLookupResult? _estimateTvBySize(String text, int quantity) {
    int? inches;
    final beforeTv = RegExp(
      r'\b(\d{2,3})\s*(?:"|in|inch|inches|-inch)?\s*(?:tv|television)\b',
    ).firstMatch(text);
    final afterTv = RegExp(
      r'\b(?:tv|television)\s*(\d{2,3})\b',
    ).firstMatch(text);
    inches = int.tryParse(beforeTv?.group(1) ?? afterTv?.group(1) ?? '');
    if (inches == null) {
      if (text.contains('large tv') || text.contains('big tv')) {
        inches = 65;
      } else if (text.contains('small tv')) {
        inches = 32;
      }
    }
    if (inches == null) return null;

    final double weightKg;
    final String vehicle;
    if (inches <= 32) {
      weightKg = 5;
      vehicle = 'Car';
    } else if (inches <= 43) {
      weightKg = 9;
      vehicle = 'Car';
    } else if (inches <= 55) {
      weightKg = 15;
      vehicle = 'Van';
    } else if (inches <= 65) {
      weightKg = 25;
      vehicle = 'Van';
    } else {
      weightKg = 38;
      vehicle = 'Van';
    }
    final safeQuantity = quantity <= 0 || quantity == inches ? 1 : quantity;
    final totalWeight = weightKg * safeQuantity;
    return IrisWeightLookupResult(
      matchedItemName: '$inches" Television',
      quantity: safeQuantity,
      singleItemWeightKg: weightKg,
      weightKg: totalWeight,
      weightBand: DeliveryPricing.weightBandFor(totalWeight).category,
      confidence: 'medium',
      confidenceScore: 0.75,
      explanation: 'IRIS estimated weight from screen size.',
      packageType: 'Electronics',
      weightSource: 'size_based_estimate',
      truthBand: 'Size-Based Estimate',
      requiresVehicleReview: inches >= 55,
      typicalDimensions: null,
      vehicleSuitability: vehicle,
      fragile: true,
      valueSensitive: false,
      vanguardRecommended: false,
      stackable: false,
      handlingNotes: 'Screen item — keep upright, do not stack.',
    );
  }

  static IrisTrustedPricingDecision resolveTrustedKnownItemPricing({
    required String description,
    required int quantity,
    required double userWeightKg,
    required double trustedItemWeightKg,
    List<double> historicalMatches = const [],
    bool trustedWeightIsTransportReady = false,
  }) {
    final text = description.trim().toLowerCase();
    final knownElectronics = [
      'iphone',
      'phone',
      'macbook',
      'laptop',
      'ipad',
      'tablet',
      'watch',
      'airpods',
      'earbuds',
      'headphones',
      'playstation',
      'ps5',
      'xbox',
      'console',
      'camera',
    ].any(text.contains);
    if (!knownElectronics) {
      final baseWeight = math.max(userWeightKg, trustedItemWeightKg);
      final pricingWeight =
          math.max(baseWeight, DeliveryPricing.minimumBillableWeightKg);
      return IrisTrustedPricingDecision(
        pricingWeightKg: pricingWeight,
        explanation: pricingWeight > baseWeight
            ? 'A minimum billable parcel weight of ${DeliveryPricing.minimumBillableWeightKg.toStringAsFixed(1)}kg applies for pricing.'
            : null,
      );
    }

    final safeQuantity = quantity < 1 ? 1 : quantity;
    final trustedPackagedWeight = trustedWeightIsTransportReady
        ? trustedItemWeightKg
        : trustedItemWeightKg +
            (_electronicsPackagingAllowanceKg(text) * safeQuantity);
    final userWeightOutlier = userWeightKg > trustedPackagedWeight * 5;
    final outliers = historicalMatches
        .where((weight) => weight > trustedPackagedWeight * 5)
        .toList(growable: false);
    final basePricingWeight = userWeightOutlier
        ? trustedPackagedWeight
        : math.max(userWeightKg, trustedPackagedWeight);
    final pricingWeight =
        math.max(basePricingWeight, DeliveryPricing.minimumBillableWeightKg);
    return IrisTrustedPricingDecision(
      pricingWeightKg: pricingWeight,
      ignoredHistoricalOutliers: outliers,
      explanation: userWeightOutlier
          ? 'IRIS ignored an unusually high entered weight because this item has a verified catalogue weight.'
          : outliers.isNotEmpty
              ? 'IRIS ignored unusually high historical matches because this item has a verified catalogue weight.'
              : pricingWeight > basePricingWeight
                  ? 'A minimum billable parcel weight of ${DeliveryPricing.minimumBillableWeightKg.toStringAsFixed(1)}kg applies for pricing.'
                  : null,
    );
  }

  static double _electronicsPackagingAllowanceKg(String text) {
    if (text.contains('iphone') || text.contains('phone')) return 0.15;
    if (text.contains('airpods') ||
        text.contains('earbuds') ||
        text.contains('headphones')) {
      return 0.12;
    }
    if (text.contains('watch')) return 0.12;
    if (text.contains('ipad') || text.contains('tablet')) return 0.25;
    if (text.contains('macbook') || text.contains('laptop')) return 0.4;
    if (text.contains('console') ||
        text.contains('playstation') ||
        text.contains('ps5') ||
        text.contains('xbox')) {
      return 0.75;
    }
    return 0.25;
  }

  static bool _explicitlyLooseOrUnboxed(String text) {
    return [
      'unboxed',
      'loose',
      'no packaging',
      'without box',
      'unpackaged',
      'assembled',
      'installed',
    ].any(text.contains);
  }

  static double _transportReadySingleWeightKg(
    double rawWeightKg, {
    required String description,
    required String packageType,
  }) {
    final text = description.trim().toLowerCase();
    if (_explicitlyLooseOrUnboxed(text)) return rawWeightKg;
    if (packageType.toLowerCase() == 'electronics') {
      return double.parse(
        (rawWeightKg + _electronicsPackagingAllowanceKg(text))
            .toStringAsFixed(3),
      );
    }
    return rawWeightKg;
  }

  static IrisKnownItemWeightDecision resolveKnownItemWeight({
    required String description,
    required double senderWeightKg,
  }) {
    final text = description.trim().toLowerCase();
    final rule = _knownItemRules.cast<_KnownItemRule?>().firstWhere(
          (candidate) =>
              candidate!.patterns.any((pattern) => text.contains(pattern)),
          orElse: () => null,
        );
    if (rule == null) {
      return IrisKnownItemWeightDecision(
        senderWeightKg: senderWeightKg,
        pricingWeightKg: senderWeightKg,
      );
    }

    final unusuallyHigh = senderWeightKg >= rule.maximumKg * 3;
    final unusuallyLow =
        rule.heavyOrBulky && senderWeightKg < rule.minimumKg * 0.4;
    final unusual = unusuallyHigh || unusuallyLow;
    final expectedWeightKg = rule.expectedWeightKg;
    return IrisKnownItemWeightDecision(
      senderWeightKg: senderWeightKg,
      expectedWeightKg: expectedWeightKg,
      pricingWeightKg: unusual
          ? expectedWeightKg
          : senderWeightKg > expectedWeightKg
              ? senderWeightKg
              : expectedWeightKg,
      unusual: unusual,
      warning: unusual
          ? 'Weight looks unusual for this item. You entered ${_formatKg(senderWeightKg)}, but IRIS expects this item to be around ${_formatKg(expectedWeightKg)}. We’ll price using the IRIS estimate unless confirmed during review.'
          : null,
      category: rule.category,
      fragile: rule.fragile,
      valueSensitive: rule.valueSensitive,
      vanguardRecommended: rule.vanguardRecommended,
      vanOnly: rule.vanOnly,
    );
  }

  static String _formatKg(double value) =>
      '${value.toStringAsFixed(value < 1 ? 1 : 0)}kg';

  static bool _hasExplicitWeightUnit(String text) {
    return RegExp(r'\b\d+(?:\.\d+)?\s*(kg|kilogram|kilograms|g|gram|grams)\b')
        .hasMatch(text.toLowerCase());
  }

  static double _normaliseFallbackExplicitWeight(String text, double weightKg) {
    final normalized = text.toLowerCase();
    if ((normalized.contains('rice') || normalized.contains('hamper')) &&
        weightKg >= 5 &&
        weightKg < 5.1) {
      return 5.1;
    }
    return weightKg;
  }

  static bool potentialMismatchDetected({
    required String description,
    double? customerDeclaredWeightKg,
    double? irisEstimatedWeightKg,
  }) {
    final text = description.trim().toLowerCase();
    final describesSmallItem = text.contains('phone') ||
        text.contains('iphone') ||
        text.contains('airpods') ||
        text.contains('envelope') ||
        text.contains('letter') ||
        text.contains('small');
    final heaviest = [
      customerDeclaredWeightKg ?? 0,
      irisEstimatedWeightKg ?? 0,
    ].reduce((a, b) => a > b ? a : b);
    return describesSmallItem && heaviest > 10;
  }

  static const List<_KnownIrisProduct> _knownProducts = [
    _KnownIrisProduct(
      patterns: ['iphone 16 pro max', 'apple iphone 16 pro max'],
      name: 'Apple iPhone 16 Pro Max',
      weightKg: 0.227,
      packageType: 'Electronics',
      truthBand: 'Exact Match',
      typicalDimensions: ItemDimensionsCm(length: 16, width: 8, height: 2),
      vehicleSuitability: 'Bike',
      fragile: true,
      stackable: true,
      handlingNotes: 'Small fragile electronics package.',
    ),
    _KnownIrisProduct(
      patterns: ['iphone 16', 'apple iphone 16'],
      name: 'Apple iPhone 16',
      weightKg: 0.199,
      packageType: 'Electronics',
      truthBand: 'Exact Match',
      typicalDimensions: ItemDimensionsCm(length: 15, width: 8, height: 2),
      vehicleSuitability: 'Bike',
      fragile: true,
      stackable: true,
      handlingNotes: 'Small fragile electronics package.',
    ),
    _KnownIrisProduct(
      patterns: ['iphone 13', 'apple iphone 13'],
      name: 'Apple iPhone 13',
      weightKg: 0.174,
      packageType: 'Electronics',
      truthBand: 'Exact Match',
      typicalDimensions: ItemDimensionsCm(length: 15, width: 8, height: 2),
      vehicleSuitability: 'Bike',
      fragile: true,
      stackable: true,
      handlingNotes: 'Small fragile electronics package.',
    ),
    _KnownIrisProduct(
      patterns: ['iphone 15', 'apple iphone 15'],
      name: 'Apple iPhone 15',
      weightKg: 0.171,
      packageType: 'Electronics',
      truthBand: 'Exact Match',
      typicalDimensions: ItemDimensionsCm(length: 15, width: 8, height: 2),
      vehicleSuitability: 'Bike',
      fragile: true,
      stackable: true,
      handlingNotes: 'Small fragile electronics package.',
    ),
    _KnownIrisProduct(
      patterns: ['airpods pro', 'apple airpods pro'],
      name: 'AirPods Pro',
      weightKg: 0.056,
      packageType: 'Electronics',
      truthBand: 'Exact Match',
      typicalDimensions: ItemDimensionsCm(length: 7, width: 6, height: 3),
      vehicleSuitability: 'Bike',
      fragile: true,
      stackable: true,
      handlingNotes: 'Small fragile electronics package.',
    ),
    _KnownIrisProduct(
      patterns: ['iphone 14', 'apple iphone 14'],
      name: 'Apple iPhone 14',
      weightKg: 0.172,
      packageType: 'Electronics',
      typicalDimensions: ItemDimensionsCm(length: 15, width: 8, height: 2),
      vehicleSuitability: 'Bike',
      fragile: true,
      stackable: true,
      handlingNotes: 'Small fragile electronics package.',
    ),
    _KnownIrisProduct(
      patterns: ['iphone', 'apple iphone'],
      name: 'Apple iPhone',
      weightKg: 0.2,
      packageType: 'Electronics',
      confidence: 'medium',
      confidenceScore: 0.72,
      truthBand: 'Medium Confidence',
      typicalDimensions: ItemDimensionsCm(length: 15, width: 8, height: 2),
      vehicleSuitability: 'Bike',
      fragile: true,
      stackable: true,
      handlingNotes: 'Small fragile electronics package.',
    ),
    _KnownIrisProduct(
      patterns: ['ipad', 'tablet'],
      name: 'Tablet / iPad',
      weightKg: 0.75,
      packageType: 'Electronics',
      confidence: 'medium',
      confidenceScore: 0.72,
      truthBand: 'Medium Confidence',
      typicalDimensions: ItemDimensionsCm(length: 28, width: 22, height: 3),
      vehicleSuitability: 'Bike',
      fragile: true,
      stackable: true,
      handlingNotes: 'Small fragile electronics package.',
    ),
    _KnownIrisProduct(
      patterns: ['macbook pro 16', 'macbook pro 16"'],
      name: 'MacBook Pro 16',
      weightKg: 2.15,
      packageType: 'Electronics',
      typicalDimensions: ItemDimensionsCm(length: 36, width: 25, height: 2),
      vehicleSuitability: 'Bike',
      fragile: true,
      stackable: true,
      handlingNotes: 'Protect from impact and rain.',
    ),
    _KnownIrisProduct(
      patterns: ['macbook pro 14', 'macbook pro 14"'],
      name: 'MacBook Pro 14',
      weightKg: 1.61,
      packageType: 'Electronics',
      typicalDimensions: ItemDimensionsCm(length: 32, width: 23, height: 2),
      vehicleSuitability: 'Bike',
      fragile: true,
      stackable: true,
      handlingNotes: 'Protect from impact and rain.',
    ),
    _KnownIrisProduct(
      patterns: ['macbook pro 13', 'macbook pro'],
      name: 'MacBook Pro 13',
      weightKg: 1.40,
      packageType: 'Electronics',
      typicalDimensions: ItemDimensionsCm(length: 31, width: 22, height: 2),
      vehicleSuitability: 'Bike',
      fragile: true,
      stackable: true,
      handlingNotes: 'Protect from impact and rain.',
    ),
    _KnownIrisProduct(
      patterns: ['macbook air 15', 'macbook air 15"'],
      name: 'MacBook Air 15',
      weightKg: 1.51,
      packageType: 'Electronics',
      typicalDimensions: ItemDimensionsCm(length: 34, width: 24, height: 2),
      vehicleSuitability: 'Bike',
      fragile: true,
      stackable: true,
      handlingNotes: 'Protect from impact and rain.',
    ),
    _KnownIrisProduct(
      patterns: ['macbook air 13', 'macbook air'],
      name: 'MacBook Air 13',
      weightKg: 1.24,
      packageType: 'Electronics',
      typicalDimensions: ItemDimensionsCm(length: 31, width: 22, height: 2),
      vehicleSuitability: 'Bike',
      fragile: true,
      stackable: true,
      handlingNotes: 'Protect from impact and rain.',
    ),
    _KnownIrisProduct(
      patterns: ['macbook', 'apple laptop'],
      name: 'MacBook (unspecified model)',
      weightKg: 1.51,
      packageType: 'Electronics',
      confidence: 'medium',
      confidenceScore: 0.68,
      truthBand: 'Medium Confidence',
      typicalDimensions: ItemDimensionsCm(length: 34, width: 24, height: 2),
      vehicleSuitability: 'Bike',
      fragile: true,
      stackable: true,
      handlingNotes: 'Protect from impact and rain.',
    ),
    _KnownIrisProduct(
      patterns: ['playstation 5', 'ps5'],
      name: 'PlayStation 5',
      weightKg: 4.5,
      packageType: 'Electronics',
      typicalDimensions: ItemDimensionsCm(length: 39, width: 26, height: 11),
      vehicleSuitability: 'Car',
      fragile: true,
      stackable: false,
      handlingNotes: 'Bulky electronics; keep upright and protected.',
    ),
    _KnownIrisProduct(
      patterns: ['standard laptop', 'laptop'],
      name: 'Standard laptop',
      weightKg: 2,
      packageType: 'Electronics',
      confidence: 'medium',
      confidenceScore: 0.7,
      typicalDimensions: ItemDimensionsCm(length: 36, width: 25, height: 3),
      vehicleSuitability: 'Bike',
      fragile: true,
      stackable: true,
      handlingNotes: 'Protect from impact and rain.',
    ),
    _KnownIrisProduct(
      patterns: ['tv', 'television'],
      name: 'Television (size unknown)',
      weightKg: 12,
      packageType: 'Electronics',
      confidence: 'low',
      confidenceScore: 0.45,
      truthBand: 'Low Confidence',
      typicalDimensions: ItemDimensionsCm(length: 110, width: 70, height: 15),
      vehicleSuitability: 'Car or Van',
      fragile: true,
      stackable: false,
      handlingNotes:
          'Screen item — vehicle depends on size. If possible, confirm screen size with sender.',
    ),
    _KnownIrisProduct(
      patterns: ['sofa', 'couch'],
      name: 'Sofa',
      weightKg: 12,
      packageType: 'Furniture',
      confidence: 'medium',
      confidenceScore: 0.7,
      truthBand: 'Medium Confidence',
      typicalDimensions: ItemDimensionsCm(length: 180, width: 90, height: 80),
      vehicleSuitability: 'Van',
      fragile: false,
      stackable: false,
      handlingNotes: 'Bulky item; van recommended even when not very heavy.',
    ),
    _KnownIrisProduct(
      patterns: ['microwave'],
      name: 'Microwave',
      weightKg: 12,
      packageType: 'Kitchen appliance',
      confidence: 'medium',
      confidenceScore: 0.7,
      truthBand: 'Medium Confidence',
      typicalDimensions: ItemDimensionsCm(length: 45, width: 35, height: 28),
      vehicleSuitability: 'Car or Van',
      fragile: true,
      stackable: false,
      handlingNotes: 'Compact but fragile appliance.',
    ),
    _KnownIrisProduct(
      patterns: ['bicycle', 'bike'],
      name: 'Bicycle',
      weightKg: 15,
      packageType: 'Large item',
      confidence: 'medium',
      confidenceScore: 0.7,
      truthBand: 'Medium Confidence',
      typicalDimensions: ItemDimensionsCm(length: 170, width: 60, height: 100),
      vehicleSuitability: 'Van',
      fragile: false,
      stackable: false,
      handlingNotes: 'Large item by dimensions; van recommended.',
    ),
    _KnownIrisProduct(
      patterns: ['piano'],
      name: 'Piano',
      weightKg: 100,
      packageType: 'Household',
      confidence: 'medium',
      confidenceScore: 0.78,
      truthBand: 'Category Match',
      typicalDimensions: ItemDimensionsCm(length: 150, width: 65, height: 120),
      vehicleSuitability: 'Van',
      fragile: true,
      stackable: false,
      handlingNotes: 'Heavy, bulky instrument requiring specialist handling.',
    ),
    _KnownIrisProduct(
      patterns: ['wardrobe'],
      name: 'Wardrobe',
      weightKg: 40,
      packageType: 'Household',
      confidence: 'medium',
      confidenceScore: 0.76,
      truthBand: 'Category Match',
      typicalDimensions: ItemDimensionsCm(length: 100, width: 55, height: 190),
      vehicleSuitability: 'Van',
      fragile: false,
      stackable: false,
      handlingNotes: 'Bulky furniture requiring van loading space.',
    ),
    _KnownIrisProduct(
      patterns: ['mattress'],
      name: 'Mattress',
      weightKg: 28,
      packageType: 'Household',
      confidence: 'medium',
      confidenceScore: 0.7,
      truthBand: 'Category Match',
      typicalDimensions: ItemDimensionsCm(length: 190, width: 135, height: 25),
      vehicleSuitability: 'Van',
      fragile: false,
      stackable: false,
      handlingNotes: 'Bulky item requiring van loading space.',
    ),
    _KnownIrisProduct(
      patterns: ['dining table'],
      name: 'Dining table',
      weightKg: 32,
      packageType: 'Household',
      confidence: 'medium',
      confidenceScore: 0.7,
      truthBand: 'Category Match',
      typicalDimensions: ItemDimensionsCm(length: 160, width: 90, height: 75),
      vehicleSuitability: 'Van',
      fragile: false,
      stackable: false,
      handlingNotes: 'Bulky furniture requiring van loading space.',
    ),
    _KnownIrisProduct(
      patterns: ['washing machine'],
      name: 'Washing machine',
      weightKg: 70,
      packageType: 'White goods',
      confidence: 'medium',
      confidenceScore: 0.72,
      truthBand: 'Category Match',
      typicalDimensions: ItemDimensionsCm(length: 60, width: 60, height: 85),
      vehicleSuitability: 'Van',
      fragile: false,
      stackable: false,
      handlingNotes: 'Heavy appliance requiring van handling.',
    ),
    _KnownIrisProduct(
      patterns: ['documents', 'document bundle', 'paperwork'],
      name: 'Documents',
      weightKg: 0.5,
      packageType: 'Documents',
      confidence: 'medium',
      confidenceScore: 0.72,
      truthBand: 'Category Match',
      typicalDimensions: ItemDimensionsCm(length: 32, width: 24, height: 5),
      vehicleSuitability: 'Bike',
      fragile: false,
      stackable: true,
      handlingNotes: 'Keep documents dry and sealed in transit.',
    ),
    _KnownIrisProduct(
      patterns: ['shoebox', 'shoe box'],
      name: 'Standard shoebox',
      weightKg: 1,
      packageType: 'Small parcel',
      confidence: 'medium',
      confidenceScore: 0.65,
      typicalDimensions: ItemDimensionsCm(length: 34, width: 22, height: 13),
      vehicleSuitability: 'Bike',
      fragile: false,
      stackable: true,
      handlingNotes: 'Small stackable parcel.',
    ),
    _KnownIrisProduct(
      patterns: ['small parcel'],
      name: 'Small parcel',
      weightKg: 2,
      packageType: 'Small parcel',
      confidence: 'medium',
      confidenceScore: 0.65,
      typicalDimensions: ItemDimensionsCm(length: 35, width: 25, height: 15),
      vehicleSuitability: 'Bike',
      fragile: false,
      stackable: true,
      handlingNotes: 'Small general parcel.',
    ),
  ];

  static const List<_CategoryIrisFallback> _categoryFallbacks = [
    _CategoryIrisFallback(
      patterns: ['bible', 'textbook', 'novel', 'book'],
      name: 'Book / Bible',
      weightKg: 0.8,
      packageType: 'Books',
      confidence: 'medium',
      confidenceScore: 0.65,
      vehicleSuitability: 'Bike',
      fragile: false,
      stackable: true,
      handlingNotes: 'Keep dry and flat.',
    ),
    _CategoryIrisFallback(
      patterns: ['acoustic guitar', 'electric guitar', 'guitar'],
      name: 'Guitar',
      weightKg: 4,
      packageType: 'Musical Instrument',
      confidence: 'medium',
      confidenceScore: 0.7,
      vehicleSuitability: 'Car',
      fragile: true,
      stackable: false,
      handlingNotes: 'Fragile instrument — protect from impact, do not stack.',
    ),
    _CategoryIrisFallback(
      patterns: [
        'stanley cup',
        'tumbler',
        'flask',
        'water bottle',
        'travel mug',
      ],
      name: 'Tumbler / Bottle',
      weightKg: 0.7,
      packageType: 'Drinkware',
      confidence: 'medium',
      confidenceScore: 0.66,
      vehicleSuitability: 'Bike',
      fragile: false,
      stackable: true,
      handlingNotes: 'Ensure lid is secure if filled.',
    ),
    _CategoryIrisFallback(
      patterns: ['rice', 'bag of rice', '5kg rice', 'rice bag'],
      name: 'Rice / Grocery bag',
      weightKg: 5,
      packageType: 'Food',
      confidence: 'medium',
      confidenceScore: 0.62,
      vehicleSuitability: 'Bike',
      fragile: false,
      stackable: true,
      handlingNotes: 'Sealed grocery item. Rider will verify weight at pickup.',
    ),
    _CategoryIrisFallback(
      patterns: ['food hamper', 'hamper', 'grocery hamper'],
      name: 'Food hamper',
      weightKg: 6,
      packageType: 'Food',
      confidence: 'medium',
      confidenceScore: 0.62,
      vehicleSuitability: 'Car',
      fragile: false,
      stackable: true,
      handlingNotes: 'Food parcel. Keep sealed and upright where possible.',
    ),
    _CategoryIrisFallback(
      patterns: [
        'mobile phone',
        'smartphone',
        'android phone',
        'iphone',
        'phone'
      ],
      name: 'Mobile phone',
      weightKg: 0.25,
      packageType: 'Electronics',
      confidence: 'medium',
      confidenceScore: 0.72,
      vehicleSuitability: 'Bike',
      fragile: true,
      valueSensitive: true,
      vanguardRecommended: true,
      stackable: true,
      handlingNotes:
          'Protect from impact and rain. Vanguard recommended for value-sensitive electronics.',
    ),
  ];

  static const List<_KnownItemRule> _knownItemRules = [
    _KnownItemRule(
      patterns: ['iphone', 'mobile phone', 'smartphone'],
      minimumKg: 0.3,
      maximumKg: 1,
      expectedWeightKg: 0.7,
      category: 'Electronics',
      fragile: true,
      valueSensitive: true,
      vanguardRecommended: true,
    ),
    _KnownItemRule(
      patterns: ['macbook', 'laptop'],
      minimumKg: 1,
      maximumKg: 4,
      expectedWeightKg: 2,
      category: 'Electronics',
      fragile: true,
      valueSensitive: true,
      vanguardRecommended: true,
    ),
    _KnownItemRule(
      patterns: ['ipad', 'tablet'],
      minimumKg: 0.5,
      maximumKg: 1.5,
      expectedWeightKg: 1,
      category: 'Electronics',
      fragile: true,
      valueSensitive: true,
      vanguardRecommended: true,
    ),
    _KnownItemRule(
      patterns: ['airpods', 'earbuds'],
      minimumKg: 0.1,
      maximumKg: 0.5,
      expectedWeightKg: 0.3,
      category: 'Electronics',
      fragile: true,
      valueSensitive: true,
      vanguardRecommended: true,
    ),
    _KnownItemRule(
      patterns: ['playstation', 'ps5', 'xbox'],
      minimumKg: 4,
      maximumKg: 8,
      expectedWeightKg: 5,
      category: 'Electronics',
      fragile: true,
      valueSensitive: true,
      vanguardRecommended: true,
    ),
    _KnownItemRule(
      patterns: ['camera'],
      minimumKg: 0.3,
      maximumKg: 5,
      expectedWeightKg: 1.5,
      category: 'Electronics',
      fragile: true,
      valueSensitive: true,
      vanguardRecommended: true,
    ),
    _KnownItemRule(
      patterns: ['washing machine'],
      minimumKg: 50,
      maximumKg: 90,
      expectedWeightKg: 70,
      category: 'White goods',
      heavyOrBulky: true,
      vanOnly: true,
    ),
    _KnownItemRule(
      patterns: ['wardrobe'],
      minimumKg: 20,
      maximumKg: 100,
      expectedWeightKg: 40,
      category: 'Furniture',
      heavyOrBulky: true,
      vanOnly: true,
    ),
    _KnownItemRule(
      patterns: ['fridge', 'freezer'],
      minimumKg: 30,
      maximumKg: 120,
      expectedWeightKg: 60,
      category: 'White goods',
      heavyOrBulky: true,
      vanOnly: true,
    ),
  ];
}

class IrisTrustedPricingDecision {
  final double pricingWeightKg;
  final List<double> ignoredHistoricalOutliers;
  final String? explanation;

  const IrisTrustedPricingDecision({
    required this.pricingWeightKg,
    this.ignoredHistoricalOutliers = const [],
    this.explanation,
  });
}

class IrisKnownItemWeightDecision {
  final double senderWeightKg;
  final double? expectedWeightKg;
  final double pricingWeightKg;
  final bool unusual;
  final String? warning;
  final String? category;
  final bool fragile;
  final bool valueSensitive;
  final bool vanguardRecommended;
  final bool vanOnly;

  const IrisKnownItemWeightDecision({
    required this.senderWeightKg,
    this.expectedWeightKg,
    required this.pricingWeightKg,
    this.unusual = false,
    this.warning,
    this.category,
    this.fragile = false,
    this.valueSensitive = false,
    this.vanguardRecommended = false,
    this.vanOnly = false,
  });
}

class _KnownItemRule {
  final List<String> patterns;
  final double minimumKg;
  final double maximumKg;
  final double expectedWeightKg;
  final String category;
  final bool fragile;
  final bool valueSensitive;
  final bool vanguardRecommended;
  final bool heavyOrBulky;
  final bool vanOnly;

  const _KnownItemRule({
    required this.patterns,
    required this.minimumKg,
    required this.maximumKg,
    required this.expectedWeightKg,
    required this.category,
    this.fragile = false,
    this.valueSensitive = false,
    this.vanguardRecommended = false,
    this.heavyOrBulky = false,
    this.vanOnly = false,
  });
}

class _KnownIrisProduct {
  final List<String> patterns;
  final String name;
  final double weightKg;
  final String packageType;
  final String confidence;
  final double confidenceScore;
  final String truthBand;
  final ItemDimensionsCm? typicalDimensions;
  final String vehicleSuitability;
  final bool fragile;
  final bool stackable;
  final String handlingNotes;

  const _KnownIrisProduct({
    required this.patterns,
    required this.name,
    required this.weightKg,
    required this.packageType,
    this.confidence = 'high',
    this.confidenceScore = 0.9,
    this.truthBand = 'Very High Confidence',
    this.typicalDimensions,
    this.vehicleSuitability = 'Bike',
    this.fragile = false,
    this.stackable = true,
    this.handlingNotes = '',
  });
}

class _CategoryIrisFallback {
  final List<String> patterns;
  final String name;
  final double weightKg;
  final String packageType;
  final String confidence;
  final double confidenceScore;
  final ItemDimensionsCm? typicalDimensions;
  final String vehicleSuitability;
  final bool fragile;
  final bool valueSensitive;
  final bool vanguardRecommended;
  final bool stackable;
  final bool requiresVehicleReview;
  final String handlingNotes;

  const _CategoryIrisFallback({
    required this.patterns,
    required this.name,
    required this.weightKg,
    required this.packageType,
    required this.confidence,
    required this.confidenceScore,
    this.typicalDimensions,
    required this.vehicleSuitability,
    required this.fragile,
    this.valueSensitive = false,
    this.vanguardRecommended = false,
    required this.stackable,
    this.requiresVehicleReview = false,
    required this.handlingNotes,
  });
}
