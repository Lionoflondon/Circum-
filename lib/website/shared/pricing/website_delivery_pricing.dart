import 'dart:math';

import 'website_pricing_constants.dart';

class DeliveryPricingInput {
  final double distanceMiles;
  final double weightKg;
  final String? vehicleType;
  final bool oversized;
  final bool fragile;
  final bool twoPersonHandling;
  final int stairsFloors;
  final bool noLift;
  final bool priority;
  final bool express;
  final int quantity;
  final double? singleItemWeightKg;
  final bool stackable;
  final int waitingMinutes;
  final double surgeMultiplier;

  const DeliveryPricingInput({
    required this.distanceMiles,
    required this.weightKg,
    this.vehicleType,
    this.oversized = false,
    this.fragile = false,
    this.twoPersonHandling = false,
    this.stairsFloors = 0,
    this.noLift = false,
    this.priority = false,
    this.express = false,
    this.quantity = 1,
    this.singleItemWeightKg,
    this.stackable = false,
    this.waitingMinutes = 0,
    this.surgeMultiplier = 1,
  });
}

class DeliveryPricingBreakdown {
  final double baseFare;
  final double distanceFare;
  final double weightSurcharge;
  final double vehicleSurcharge;
  final double specialConditions;
  final double serviceLevelSurcharge;
  final String serviceLevel;
  final double surgeMultiplier;
  final double total;
  final String weightCategory;
  final double assistedFee;
  final double heavyDutyFee;
  final double twoPersonFee;
  final double heavyHandlingSurcharge;
  final bool twoPersonRecommended;
  final bool twoPersonRequiredByWeight;
  final bool multiTripReviewRequired;
  final bool heavyHandlingAdminReviewRequired;
  final double riderBaseShare;
  final double riderLabourShare;
  final double circumBaseShare;
  final double circumLabourShare;
  final double totalRiderEarnings;
  final double totalCircumRevenue;

  const DeliveryPricingBreakdown({
    required this.baseFare,
    required this.distanceFare,
    required this.weightSurcharge,
    required this.vehicleSurcharge,
    required this.specialConditions,
    required this.serviceLevelSurcharge,
    required this.serviceLevel,
    required this.surgeMultiplier,
    required this.total,
    required this.weightCategory,
    this.assistedFee = 0,
    this.heavyDutyFee = 0,
    this.twoPersonFee = 0,
    this.heavyHandlingSurcharge = 0,
    this.twoPersonRecommended = false,
    this.twoPersonRequiredByWeight = false,
    this.multiTripReviewRequired = false,
    this.heavyHandlingAdminReviewRequired = false,
    this.riderBaseShare = 0,
    this.riderLabourShare = 0,
    this.circumBaseShare = 0,
    this.circumLabourShare = 0,
    this.totalRiderEarnings = 0,
    this.totalCircumRevenue = 0,
  });

  Map<String, dynamic> toJson() => {
        'baseFare': baseFare,
        'distanceFare': distanceFare,
        'weightSurcharge': weightSurcharge,
        'vehicleSurcharge': vehicleSurcharge,
        'specialConditions': specialConditions,
        'serviceLevelSurcharge': serviceLevelSurcharge,
        'serviceLevel': serviceLevel,
        'finalCustomerPrice': total,
        'surgeMultiplier': surgeMultiplier,
        'total': total,
        'weightCategory': weightCategory,
        'assistedFee': assistedFee,
        'heavyDutyFee': heavyDutyFee,
        'twoPersonFee': twoPersonFee,
        'heavyHandlingSurcharge': heavyHandlingSurcharge,
        'twoPersonRecommended': twoPersonRecommended,
        'twoPersonRequiredByWeight': twoPersonRequiredByWeight,
        'multiTripReviewRequired': multiTripReviewRequired,
        'heavyHandlingAdminReviewRequired': heavyHandlingAdminReviewRequired,
        'riderBaseShare': riderBaseShare,
        'riderLabourShare': riderLabourShare,
        'circumBaseShare': circumBaseShare,
        'circumLabourShare': circumLabourShare,
        'totalRiderEarnings': totalRiderEarnings,
        'totalCircumRevenue': totalCircumRevenue,
      };
}

class DeliveryClassification {
  final double finalWeightKg;
  final String finalWeightBand;
  final double? irisEstimateKg;
  final double? userEnteredWeightKg;
  final String confidence;
  final String resolutionReason;
  final bool requiresManualReview;
  final String vehicleType;
  final String selectedWeightSource;

  const DeliveryClassification({
    required this.finalWeightKg,
    required this.finalWeightBand,
    required this.irisEstimateKg,
    required this.userEnteredWeightKg,
    required this.confidence,
    required this.resolutionReason,
    required this.requiresManualReview,
    required this.vehicleType,
    required this.selectedWeightSource,
  });

  Map<String, dynamic> toJson() => {
        'finalWeightKg': finalWeightKg,
        'finalWeightBand': finalWeightBand,
        'irisEstimateKg': irisEstimateKg,
        'userEnteredWeightKg': userEnteredWeightKg,
        'confidence': confidence,
        'resolutionReason': resolutionReason,
        'requiresManualReview': requiresManualReview,
        'vehicleType': vehicleType,
        'selectedWeightSource': selectedWeightSource,
      };
}

class DeliveryItemDimensions {
  final double lengthCm;
  final double widthCm;
  final double heightCm;

  const DeliveryItemDimensions({
    required this.lengthCm,
    required this.widthCm,
    required this.heightCm,
  });

  double get longestSideCm => max(lengthCm, max(widthCm, heightCm));
  double get volumeCm3 => lengthCm * widthCm * heightCm;

  String get label =>
      '${lengthCm.toStringAsFixed(0)} x ${widthCm.toStringAsFixed(0)} x ${heightCm.toStringAsFixed(0)} cm';
}

class VehicleSuitability {
  final String recommendedVehicle;
  final List<String> allowedVehicles;
  final int score;
  final List<String> factors;
  final String explanation;
  final String handlingNotes;
  final bool fragile;
  final bool stackable;

  const VehicleSuitability({
    required this.recommendedVehicle,
    required this.allowedVehicles,
    required this.score,
    required this.factors,
    required this.explanation,
    required this.handlingNotes,
    required this.fragile,
    required this.stackable,
  });

  bool allows(String? vehicleType) {
    final normalized = _normalizePricingVehicle(vehicleType);
    return allowedVehicles
        .any((vehicle) => _normalizePricingVehicle(vehicle) == normalized);
  }
}

class HeavyHandlingAssessment {
  final double surchargeGbp;
  final bool twoPersonRecommended;
  final bool twoPersonRequired;
  final bool multiTripReviewRequired;
  final bool adminReviewRequired;

  const HeavyHandlingAssessment({
    required this.surchargeGbp,
    required this.twoPersonRecommended,
    required this.twoPersonRequired,
    required this.multiTripReviewRequired,
    required this.adminReviewRequired,
  });
}

class DeliveryPricing {
  static const double riderDeliveryFareShare = 0.65;
  static const double platformDeliveryFareShare = 0.35;

  static const Map<String, double> heavyKeywordMinimumWeightsKg = {
    'piano': 50,
    'fridge': 25,
    'freezer': 25,
    'washing machine': 25,
    'tumble dryer': 25,
    'sofa': 12,
    'wardrobe': 20.01,
    'mattress': 12,
    'bed frame': 12,
    'dresser': 12,
    'chest of drawers': 20.01,
    'treadmill': 20.01,
    'exercise bike': 20.01,
    'large tv': 12,
    'tv 65': 12,
    '65 inch': 12,
    '65 tv': 12,
    '75 tv': 20.01,
    '75 inch': 20.01,
    'table': 12,
    'cabinet': 12,
  };

  static DeliveryPricingBreakdown calculate(DeliveryPricingInput input) {
    final weightBand = weightBandFor(input.weightKg);
    final distributedStackableLoad = input.quantity > 1 &&
        input.stackable &&
        (input.singleItemWeightKg ?? input.weightKg) <=
            PricingConstants.twoPersonThresholdKg;
    final weightSurcharge =
        distributedStackableLoad && weightBand.category == 'Extra Heavy'
            ? 0.0
            : weightBand.surchargeGbp;
    final distanceFare = calculateDistanceFare(input.distanceMiles);
    final vehicleSurcharge = calculateVehicleSurcharge(input.vehicleType);
    final baseSpecialConditions = calculateSpecialConditions(
      oversized: input.oversized,
      fragile: input.fragile,
      twoPersonHandling: input.twoPersonHandling ||
          (!distributedStackableLoad &&
              (input.singleItemWeightKg ?? input.weightKg) >
                  PricingConstants.twoPersonThresholdKg),
      stairsFloors: input.stairsFloors,
      noLift: input.noLift,
      waitingMinutes: input.waitingMinutes,
    );
    final preServiceSubtotal = PricingConstants.baseFareGbp +
        distanceFare +
        weightSurcharge +
        vehicleSurcharge +
        baseSpecialConditions;
    final serviceLevelSurcharge = calculateServiceLevelSurcharge(
      preServiceSubtotal,
      express: input.express,
      priority: input.priority,
    );
    final specialConditions = _roundMoney(
      baseSpecialConditions + serviceLevelSurcharge,
    );
    final subtotal = PricingConstants.baseFareGbp +
        distanceFare +
        weightSurcharge +
        vehicleSurcharge +
        specialConditions;
    final surgeMultiplier = max(input.surgeMultiplier, 1.0).toDouble();
    final existingTotal = _roundMoney(subtotal * surgeMultiplier);
    final heavyHandling = heavyHandlingFor(input.weightKg);
    final total = _roundMoney(existingTotal + heavyHandling.surchargeGbp);

    return DeliveryPricingBreakdown(
      baseFare: PricingConstants.baseFareGbp,
      distanceFare: _roundMoney(distanceFare),
      weightSurcharge: weightSurcharge,
      vehicleSurcharge: vehicleSurcharge,
      specialConditions: specialConditions,
      serviceLevelSurcharge: serviceLevelSurcharge,
      serviceLevel: input.express
          ? 'express'
          : 'standard',
      surgeMultiplier: surgeMultiplier,
      total: total,
      weightCategory: weightBand.category,
      heavyHandlingSurcharge: heavyHandling.surchargeGbp,
      twoPersonRecommended: heavyHandling.twoPersonRecommended,
      twoPersonRequiredByWeight: heavyHandling.twoPersonRequired,
      multiTripReviewRequired: heavyHandling.multiTripReviewRequired,
      heavyHandlingAdminReviewRequired: heavyHandling.adminReviewRequired,
    );
  }

  static HeavyHandlingAssessment heavyHandlingFor(double weightKg) {
    final weight = max(0.0, weightKg);
    final surcharge = weight <= 50
        ? 0.0
        : weight <= 150
            ? 5.0
            : weight <= 300
                ? 10.0
                : weight <= 500
                    ? 20.0
                    : 40.0;
    return HeavyHandlingAssessment(
      surchargeGbp: surcharge,
      twoPersonRecommended: weight > 150,
      twoPersonRequired: weight > 300,
      multiTripReviewRequired: weight > 750,
      adminReviewRequired: weight >= 1000,
    );
  }

  static double calculateDistanceFare(double distanceMiles) {
    if (distanceMiles < PricingConstants.shortTripFareFloorMiles) {
      return 0;
    }

    final billableMiles =
        max(0.0, distanceMiles - PricingConstants.includedBaseMiles);
    final multiplier =
        distanceMiles > PricingConstants.longDistanceThresholdMiles
            ? PricingConstants.longDistanceMileageMultiplier
            : 1.0;

    return billableMiles *
        PricingConstants.additionalFarePerMileGbp *
        multiplier;
  }

  static WeightBand weightBandFor(double weightKg) {
    final normalizedWeight = max(0.0, weightKg);
    return PricingConstants.weightBands.firstWhere(
      (band) => band.contains(normalizedWeight),
      orElse: () => PricingConstants.weightBands.last,
    );
  }

  static bool weightsCrossPricingBands(double firstKg, double secondKg) {
    return weightBandFor(firstKg).category != weightBandFor(secondKg).category;
  }

  static double pricingWeightForConfirmedWeights({
    required double senderWeightKg,
    required double irisWeightKg,
  }) {
    return chargeableWeightKg(
      senderWeightKg: senderWeightKg,
      irisWeightKg: irisWeightKg,
    );
  }

  /// Checkout uses one weight resolved from raw sender, IRIS, and catalogue
  /// totals. Each source must already include quantity exactly once.
  static double checkoutPricingWeightKg({
    double? userEnteredWeightKg,
    double? irisEstimatedWeightKg,
    double? matchedCatalogueWeightKg,
  }) {
    return [
      userEnteredWeightKg ?? 0,
      irisEstimatedWeightKg ?? 0,
      matchedCatalogueWeightKg ?? 0,
    ].reduce(max);
  }

  static double chargeableWeightKg({
    required double senderWeightKg,
    double? irisWeightKg,
  }) {
    if (irisWeightKg == null || irisWeightKg <= 0) return senderWeightKg;
    return max(senderWeightKg, irisWeightKg);
  }

  static double finalVerifiedWeightKg({
    required double customerWeightKg,
    double? irisWeightKg,
    double? riderVerifiedWeightKg,
  }) {
    return [
      customerWeightKg,
      irisWeightKg ?? 0,
      riderVerifiedWeightKg ?? 0,
    ].reduce(max);
  }

  static DeliveryClassification resolveClassification({
    required String description,
    double? userEnteredWeightKg,
    double? irisEstimateKg,
    double? historicalVerifiedMinKg,
    double? historicalVerifiedMaxKg,
    double? driverVerifiedWeightKg,
    String confidence = 'unknown',
  }) {
    final candidates = <String, double>{};
    if (userEnteredWeightKg != null && userEnteredWeightKg > 0) {
      candidates['customer_declared'] = userEnteredWeightKg;
    }
    if (irisEstimateKg != null && irisEstimateKg > 0) {
      candidates['iris_estimate'] = irisEstimateKg;
    }
    if (historicalVerifiedMaxKg != null && historicalVerifiedMaxKg > 0) {
      candidates['historical_verified'] = historicalVerifiedMaxKg;
    }
    if (driverVerifiedWeightKg != null && driverVerifiedWeightKg > 0) {
      candidates['driver_verified'] = driverVerifiedWeightKg;
    }

    final keywordWeight = keywordMinimumWeightKg(description);
    if (keywordWeight != null) {
      candidates['keyword_override'] = keywordWeight;
    }

    if (candidates.isEmpty) {
      candidates['minimum_valid_weight'] = 0.1;
    }

    var selectedSource = candidates.keys.first;
    var finalWeight = candidates[selectedSource]!;
    for (final entry in candidates.entries) {
      if (entry.value > finalWeight) {
        selectedSource = entry.key;
        finalWeight = entry.value;
      }
    }

    final band = weightBandFor(finalWeight);
    final manualReview = selectedSource == 'keyword_override' &&
            finalWeight >= PricingConstants.twoPersonThresholdKg ||
        confidence.toLowerCase() == 'low' ||
        (historicalVerifiedMinKg != null &&
            historicalVerifiedMaxKg != null &&
            historicalVerifiedMaxKg > historicalVerifiedMinKg);

    return DeliveryClassification(
      finalWeightKg: finalWeight,
      finalWeightBand: band.category,
      irisEstimateKg: irisEstimateKg,
      userEnteredWeightKg: userEnteredWeightKg,
      confidence: confidence,
      resolutionReason: _classificationReason(selectedSource, band.category),
      requiresManualReview: manualReview,
      vehicleType: recommendedVehicleForWeight(finalWeight),
      selectedWeightSource: selectedSource,
    );
  }

  static double? keywordMinimumWeightKg(String description) {
    final normalized = description.toLowerCase();
    for (final entry in heavyKeywordMinimumWeightsKg.entries) {
      if (normalized.contains(entry.key)) return entry.value;
    }
    return null;
  }

  static String _classificationReason(String source, String band) {
    return switch (source) {
      'keyword_override' => 'Item type requires at least $band handling.',
      'driver_verified' => 'Rider verified weight is the highest source.',
      'historical_verified' =>
        'Similar completed parcels indicate a higher $band classification.',
      'iris_estimate' => 'IRIS selected the final billing weight.',
      'customer_declared' =>
        'IRIS selected the sender supplied weight as the final billing weight.',
      _ => 'Minimum valid parcel weight applied.',
    };
  }

  static String weightSourceLabel(String? source) {
    return switch (source) {
      'repository_match' ||
      'catalogue_match' ||
      'known_product_lookup' =>
        'Repository Match',
      'photo_match' || 'iris_confirmed' || 'visual_estimate' => 'Photo Match',
      'rider_verified' || 'driver_verified' => 'Rider Verified',
      'admin_verified' => 'Admin Verified',
      'customer_declared' || 'manual' => 'Customer Declared',
      'verified_parcel_history' => 'Past Verified Parcels',
      'keyword_override' => 'Item Type Rule',
      _ => 'Not confirmed',
    };
  }

  static String recommendedVehicleForWeight(double weightKg) {
    if (weightKg > 10) return 'Van';
    if (weightKg > 5) return 'Car';
    return 'Motorbike';
  }

  static VehicleSuitability resolveVehicleSuitability({
    required double weightKg,
    required String description,
    String? itemCategory,
    DeliveryItemDimensions? dimensions,
    String? repositoryVehicleSuitability,
    bool fragile = false,
    bool highValue = false,
    bool vanguardRequired = false,
    bool stackable = true,
    int? quantity,
    double? singleItemWeightKg,
    String? handlingNotes,
  }) {
    final text = description.toLowerCase();
    final categoryText = itemCategory?.toLowerCase().trim() ?? '';
    final factors = <String>['Weight'];
    if (dimensions != null) factors.add('Dimensions');
    if ((itemCategory ?? '').trim().isNotEmpty) factors.add('Item type');
    if ((repositoryVehicleSuitability ?? '').trim().isNotEmpty) {
      factors.add('Repository metadata');
    }

    final bulkyByKeyword = [
      'washing machine',
      'tumble dryer',
      'fridge',
      'freezer',
      'sofa',
      'wardrobe',
      'mattress',
      'bicycle',
      'bike',
      'piano',
      'multi-box',
      'multiple boxes',
      'liquid',
    ].any(text.contains);
    final compactByType = [
      'microwave',
      'suitcase',
      'luggage',
      'laptop',
      'phone',
      'shoebox',
      'small parcel',
    ].any(text.contains);
    final compactLuggage = [
      'suitcase',
      'luggage',
      'travel bag',
    ].any(text.contains);
    final documentDelivery = categoryText.contains('document') ||
        [
          'document',
          'letter',
          'contract',
          'legal paper',
          'passport',
          'certificate',
          'envelope',
          'document folder',
          'government paperwork',
        ].any(text.contains);
    final compactMotorbikeItem = [
      'keys',
      'key set',
      'phone',
      'iphone',
      'small electronics',
      'lightweight gift',
    ].any(text.contains);
    final compactFootwear = categoryText.contains('fashion') &&
        [
          'shoe',
          'shoes',
          'trainer',
          'trainers',
          'sneaker',
          'sneakers',
          'shoebox',
          'shoe box',
        ].any(text.contains);
    final resolvedQuantity = max(1, quantity ?? _quantityFromDescription(text));
    final largestItemWeightKg = singleItemWeightKg ??
        (resolvedQuantity > 1 ? weightKg / resolvedQuantity : weightKg);
    final flatPacked = text.contains('flat pack') || text.contains('flat-pack');
    final oversizedDimensions = dimensions != null &&
        (dimensions.longestSideCm > 110 || dimensions.volumeCm3 > 250000);
    final bikeSafeDimensions = dimensions == null ||
        (dimensions.longestSideCm <= 60 && dimensions.volumeCm3 <= 45000);
    final normalPrinter = text.contains('printer') &&
        resolvedQuantity == 1 &&
        weightKg <= 15 &&
        !oversizedDimensions;
    final luggageFitsCar = compactLuggage &&
        resolvedQuantity <= 4 &&
        largestItemWeightKg <= 25 &&
        !oversizedDimensions;
    final aggregateVolumeCm3 =
        dimensions == null ? null : dimensions.volumeCm3 * resolvedQuantity;
    final compactStackableLoad = stackable &&
        resolvedQuantity > 1 &&
        !bulkyByKeyword &&
        !oversizedDimensions &&
        largestItemWeightKg <= 25 &&
        (!compactLuggage || resolvedQuantity <= 4) &&
        (aggregateVolumeCm3 == null || aggregateVolumeCm3 <= 800000) &&
        (compactLuggage ||
            categoryText.contains('electronics') ||
            text.contains('laptop') ||
            text.contains('macbook'));

    // The recommendation is the minimum safe vehicle. Larger vehicles remain
    // valid sender upgrades.
    var allowed = <String>{'Motorbike', 'Car', 'Van'};
    var recommended = 'Motorbike';
    var score = 30;

    if (weightKg > 10 ||
        compactByType ||
        fragile ||
        highValue ||
        vanguardRequired) {
      allowed = {'Car', 'Van'};
      recommended = 'Car';
      score = 60;
    }
    if (weightKg > 50 || bulkyByKeyword || oversizedDimensions) {
      allowed = {'Van'};
      recommended = 'Van';
      score = 88;
    }
    if (luggageFitsCar) {
      allowed = {'Car', 'Van'};
      recommended = 'Car';
      score = max(score, 76);
    }
    if (compactStackableLoad) {
      allowed = {'Car', 'Van'};
      recommended = 'Car';
      score = max(score, 80);
    }
    if (flatPacked && weightKg <= 25 && !oversizedDimensions) {
      allowed = {'Car', 'Van'};
      recommended = 'Car';
      score = max(score, 68);
    }

    final repo = repositoryVehicleSuitability?.toLowerCase().trim() ?? '';
    if (repo == 'van' &&
        !luggageFitsCar &&
        !compactStackableLoad &&
        !normalPrinter) {
      allowed = {'Van'};
      recommended = 'Van';
      score = max(score, 90);
    } else if (repo == 'car or van') {
      allowed = {'Car', 'Van'};
      if (recommended == 'Motorbike') recommended = 'Car';
      score = max(score, 70);
    } else if (repo == 'car') {
      allowed = {'Car', 'Van'};
      recommended = 'Car';
      score = max(score, 65);
    }

    if (normalPrinter) {
      allowed = {'Car', 'Van'};
      recommended = 'Car';
      score = max(score, 82);
    }

    // Documents are a core Motorbike use case when they remain within the normal
    // courier safety, value, and protection limits.
    if (documentDelivery &&
        weightKg <= 10 &&
        bikeSafeDimensions &&
        !highValue &&
        !vanguardRequired) {
      allowed = {'Motorbike', 'Car', 'Van'};
      recommended = 'Motorbike';
      score = max(score, 95);
    } else if (weightKg <= 10 &&
        bikeSafeDimensions &&
        !fragile &&
        !highValue &&
        !vanguardRequired &&
        !bulkyByKeyword &&
        !oversizedDimensions &&
        (repo == 'bike' || repo == 'motorbike' || compactMotorbikeItem)) {
      allowed = {'Motorbike', 'Car', 'Van'};
      recommended = 'Motorbike';
      score = max(score, 78);
    }
    if (compactFootwear &&
        weightKg <= 5 &&
        bikeSafeDimensions &&
        !oversizedDimensions &&
        repo == 'bike') {
      allowed = {'Motorbike', 'Car', 'Van'};
      recommended = 'Motorbike';
      score = max(score, 86);
    }

    return VehicleSuitability(
      recommendedVehicle: recommended,
      allowedVehicles: allowed.toList(growable: false),
      score: score,
      factors: factors,
      explanation: recommended == 'Van'
          ? 'Recommended because this item may be bulky or needs extra loading space.'
          : recommended == 'Car'
              ? 'Recommended because this item fits safely in a car.'
          : 'Recommended as the fastest suitable option for this small, lightweight delivery.',
      handlingNotes: compactLuggage && weightKg > 20
          ? 'Heavy item - rider must confirm they can lift safely.'
          : handlingNotes?.trim().isNotEmpty == true
              ? handlingNotes!.trim()
              : stackable
                  ? 'Stackable item.'
                  : 'Do not stack this item.',
      fragile: fragile,
      stackable: stackable,
    );
  }

  static int _quantityFromDescription(String description) {
    final leading = RegExp(r'^\s*(\d+)\s*(?:x\s*)?').firstMatch(description);
    final trailing = RegExp(r'\bx\s*(\d+)\b').firstMatch(description);
    final parsed = int.tryParse(leading?.group(1) ?? trailing?.group(1) ?? '1');
    return parsed == null || parsed < 1 ? 1 : parsed;
  }

  static bool vehicleCanCarryWeight(String? vehicleType, double weightKg) {
    final vehicle = vehicleType?.trim().toLowerCase();
    if (vehicle == 'van') return true;
    if (vehicle == 'car') return weightKg <= 50;
    if (vehicle == 'motorbike' ||
        vehicle == 'bike' ||
        vehicle == 'bicycle' ||
        vehicle == 'e-bike' ||
        vehicle == 'ebike' ||
        vehicle == 'electric bike') {
      return weightKg <= 5;
    }
    return weightKg <= 5;
  }

  static bool vehicleCanCarryDelivery(
    String? vehicleType,
    VehicleSuitability suitability,
  ) {
    final normalized = vehicleType?.trim().toLowerCase();
    return normalized != null &&
        !PricingConstants.disabledVehicleTypes.contains(normalized) &&
        suitability.allows(vehicleType);
  }

  static String? vehicleDisabledReason(
    String? vehicleType,
    VehicleSuitability suitability,
  ) {
    final normalized = vehicleType?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return 'Not safe for this item';
    }
    if (PricingConstants.disabledVehicleTypes.contains(normalized)) {
      return 'Disabled by admin';
    }
    if (suitability.allows(vehicleType)) return null;
    if (suitability.fragile) return 'Not safe for this item';
    if (!vehicleMeetsMinimum(vehicleType, suitability.recommendedVehicle)) {
      return 'Too small for this parcel';
    }
    return 'Not safe for this item';
  }

  static bool vehicleWasUpgraded(
    String? selectedVehicle,
    String? recommendedVehicle,
  ) {
    final selected = _vehicleCapabilityRank(selectedVehicle);
    final recommended = _vehicleCapabilityRank(recommendedVehicle);
    return selected != null && recommended != null && selected > recommended;
  }

  static bool vehicleMeetsMinimum(
    String? selectedVehicle,
    String? recommendedVehicle,
  ) {
    final selected = _vehicleCapabilityRank(selectedVehicle);
    final recommended = _vehicleCapabilityRank(recommendedVehicle);
    return selected != null && recommended != null && selected >= recommended;
  }

  static int? _vehicleCapabilityRank(String? vehicleType) {
    const order = {
      'motorbike': 0,
      'bike': 0,
      'bicycle': 0,
      'e-bike': 0,
      'ebike': 0,
      'electric bike': 0,
      'car': 1,
      'estate': 1,
      'suv': 1,
      'estate/suv': 1,
      'van': 2,
      'luton van': 2,
    };
    return order[vehicleType?.trim().toLowerCase()];
  }

  static double calculateVehicleSurcharge(String? vehicleType) {
    final key = vehicleType?.trim().toLowerCase();
    if (key == null || key.isEmpty) return 0;
    return PricingConstants.vehicleSurchargesGbp[key] ?? 0;
  }

  static double calculateSpecialConditions({
    bool oversized = false,
    bool fragile = false,
    bool twoPersonHandling = false,
    int stairsFloors = 0,
    bool noLift = false,
    bool priority = false,
    bool express = false,
    int waitingMinutes = 0,
  }) {
    final fees = PricingConstants.specialConditionFeesGbp;
    var fee = 0.0;
    if (oversized) fee += fees['oversized'] ?? 0;
    if (fragile) fee += fees['fragile'] ?? 0;
    if (twoPersonHandling) fee += fees['twoPersonHandling'] ?? 0;
    if (noLift) fee += fees['noLift'] ?? 0;
    if (stairsFloors >= 1 && stairsFloors <= 2) {
      fee += fees['stairsOneToTwoFloors'] ?? 0;
    }
    if (stairsFloors >= 3) fee += fees['stairsThreePlusFloors'] ?? 0;
    if (express) {
      fee += fees['express'] ?? PricingConstants.fixedExpressSurchargeGbp;
    } else if (priority) {
      fee += fees['priority'] ?? 0;
    }
    if (waitingMinutes > 10) {
      final additionalBlocks = ((waitingMinutes - 10) / 5).ceil();
      fee += additionalBlocks * (fees['waitingAdditionalFiveMinutes'] ?? 0);
    }
    return fee;
  }

  static double calculateServiceLevelSurcharge(
    double standardSubtotal, {
    bool express = false,
    bool priority = false,
  }) {
    if (express) {
      final configuredFee =
          PricingConstants.specialConditionFeesGbp['express'] ??
              PricingConstants.fixedExpressSurchargeGbp;
      final multiplierFee =
          standardSubtotal * (PricingConstants.expressMultiplier - 1);
      return _roundMoney(max(
        max(PricingConstants.fixedExpressSurchargeGbp, configuredFee),
        multiplierFee,
      ));
    }
    if (priority) {
      return PricingConstants.specialConditionFeesGbp['priority'] ?? 0;
    }
    return 0;
  }

  static Map<String, double> serviceLevelPrices(DeliveryPricingInput input) {
    final standard = calculate(DeliveryPricingInput(
      distanceMiles: input.distanceMiles,
      weightKg: input.weightKg,
      vehicleType: input.vehicleType,
      oversized: input.oversized,
      fragile: input.fragile,
      twoPersonHandling: input.twoPersonHandling,
      stairsFloors: input.stairsFloors,
      noLift: input.noLift,
      waitingMinutes: input.waitingMinutes,
      surgeMultiplier: input.surgeMultiplier,
    ));
    final express = calculate(DeliveryPricingInput(
      distanceMiles: input.distanceMiles,
      weightKg: input.weightKg,
      vehicleType: input.vehicleType,
      oversized: input.oversized,
      fragile: input.fragile,
      twoPersonHandling: input.twoPersonHandling,
      stairsFloors: input.stairsFloors,
      noLift: input.noLift,
      express: true,
      waitingMinutes: input.waitingMinutes,
      surgeMultiplier: input.surgeMultiplier,
    ));
    return {
      'standardPrice': standard.total,
      'expressPrice': max(express.total, standard.total + 0.01),
    };
  }

  static int matchingPriorityRank(String? serviceLevel) {
    return switch (serviceLevel?.trim().toLowerCase()) {
      'express' => 0,
      'standard' => 1,
      _ => 1,
    };
  }

  static double riderPayoutFromFare(double deliveryFare) {
    return _roundMoney(deliveryFare * riderDeliveryFareShare);
  }

  static double platformRevenueFromFare(double deliveryFare) {
    return _roundMoney(deliveryFare * platformDeliveryFareShare);
  }

  static double parseWeightKg(String value, {double fallbackKg = 0}) {
    final normalized = value.trim().toLowerCase();
    final match = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(normalized);
    if (match == null) return fallbackKg;
    final parsed = double.tryParse(match.group(1)!);
    if (parsed == null) return fallbackKg;
    final unitMatch =
        RegExp(r'\d+(?:\.\d+)?\s*(kg|kilogram|kilograms|g|gram|grams)\b')
            .firstMatch(normalized);
    final unit = unitMatch?.group(1);
    if (unit == 'g' || unit == 'gram' || unit == 'grams') {
      return parsed / 1000;
    }
    return parsed;
  }

  static double kilometresToMiles(double kilometres) => kilometres / 1.6093;

  static double _roundMoney(double value) =>
      double.parse(value.toStringAsFixed(2));
}

String _normalizePricingVehicle(String? vehicleType) {
  final vehicle = vehicleType?.trim().toLowerCase() ?? '';
  if (vehicle.contains('van')) return 'van';
  if (vehicle.contains('estate') || vehicle.contains('suv')) return 'car';
  if (vehicle.contains('car')) return 'car';
  if (vehicle.contains('bike') || vehicle.contains('bicycle')) {
    return 'motorbike';
  }
  return vehicle;
}
