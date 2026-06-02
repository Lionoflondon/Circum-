import 'dart:math';

import 'pricing_constants.dart';

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
  final bool economy;
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
    this.economy = false,
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
  final bool requiresManualQuote;

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
    required this.requiresManualQuote,
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
        'requiresManualQuote': requiresManualQuote,
      };
}

class DeliveryPricing {
  static DeliveryPricingBreakdown calculate(DeliveryPricingInput input) {
    final weightBand = weightBandFor(input.weightKg);
    final distanceFare = calculateDistanceFare(input.distanceMiles);
    final vehicleSurcharge = calculateVehicleSurcharge(input.vehicleType);
    final baseSpecialConditions = calculateSpecialConditions(
      oversized: input.oversized,
      fragile: input.fragile,
      twoPersonHandling: input.twoPersonHandling,
      stairsFloors: input.stairsFloors,
      noLift: input.noLift,
      waitingMinutes: input.waitingMinutes,
    );
    final preServiceSubtotal = PricingConstants.baseFareGbp +
        distanceFare +
        weightBand.surchargeGbp +
        vehicleSurcharge +
        baseSpecialConditions;
    final serviceLevelSurcharge = calculateServiceLevelSurcharge(
      preServiceSubtotal,
      express: input.express,
      priority: input.priority,
      economy: input.economy,
    );
    final specialConditions = _roundMoney(
      baseSpecialConditions + serviceLevelSurcharge,
    );
    final subtotal = PricingConstants.baseFareGbp +
        distanceFare +
        weightBand.surchargeGbp +
        vehicleSurcharge +
        specialConditions;
    final surgeMultiplier = max(input.surgeMultiplier, 1.0).toDouble();
    final total = weightBand.requiresManualQuote
        ? 0.0
        : _roundMoney(subtotal * surgeMultiplier);

    return DeliveryPricingBreakdown(
      baseFare: PricingConstants.baseFareGbp,
      distanceFare: _roundMoney(distanceFare),
      weightSurcharge: weightBand.surchargeGbp,
      vehicleSurcharge: vehicleSurcharge,
      specialConditions: specialConditions,
      serviceLevelSurcharge: serviceLevelSurcharge,
      serviceLevel: input.express
          ? 'express'
          : input.economy
              ? 'economy'
              : 'standard',
      surgeMultiplier: surgeMultiplier,
      total: total,
      weightCategory: weightBand.category,
      requiresManualQuote: weightBand.requiresManualQuote,
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

  static double safeIrisFallbackWeightKg({required bool irisVerified}) {
    return irisVerified ? 0 : PricingConstants.unverifiedIrisSafeDefaultKg;
  }

  static String recommendedVehicleForWeight(double weightKg) {
    if (weightKg > 10) return 'Van';
    if (weightKg > 5) return 'Car';
    return 'Bike';
  }

  static bool vehicleCanCarryWeight(String? vehicleType, double weightKg) {
    final vehicle = vehicleType?.trim().toLowerCase();
    if (vehicle == 'van') return true;
    if (vehicle == 'car') return weightKg <= 20;
    if (vehicle == 'bike' || vehicle == 'bicycle') return weightKg <= 5;
    return weightKg <= 5;
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
    bool economy = false,
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
    if (economy) {
      return -min<double>(
        PricingConstants.economyDiscountGbp,
        max<double>(0, standardSubtotal - PricingConstants.baseFareGbp),
      );
    }
    return 0;
  }

  static Map<String, double> serviceLevelPrices(DeliveryPricingInput input) {
    final economy = calculate(DeliveryPricingInput(
      distanceMiles: input.distanceMiles,
      weightKg: input.weightKg,
      vehicleType: input.vehicleType,
      oversized: input.oversized,
      fragile: input.fragile,
      twoPersonHandling: input.twoPersonHandling,
      stairsFloors: input.stairsFloors,
      noLift: input.noLift,
      economy: true,
      waitingMinutes: input.waitingMinutes,
      surgeMultiplier: input.surgeMultiplier,
    ));
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
      'economyPrice': min(economy.total, standard.total - 0.01),
      'standardPrice': standard.total,
      'expressPrice': max(express.total, standard.total + 0.01),
    };
  }

  static int matchingPriorityRank(String? serviceLevel) {
    return switch (serviceLevel?.trim().toLowerCase()) {
      'express' => 0,
      'standard' => 1,
      'economy' => 2,
      _ => 1,
    };
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
