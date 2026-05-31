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
  final bool urgent;
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
    this.urgent = false,
    this.surgeMultiplier = 1,
  });
}

class DeliveryPricingBreakdown {
  final double baseFare;
  final double distanceFare;
  final double weightSurcharge;
  final double vehicleSurcharge;
  final double specialConditions;
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
    final specialConditions = calculateSpecialConditions(
      oversized: input.oversized,
      fragile: input.fragile,
      twoPersonHandling: input.twoPersonHandling,
      stairsFloors: input.stairsFloors,
      noLift: input.noLift,
      urgent: input.urgent,
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
    bool urgent = false,
  }) {
    var fee = 0.0;
    if (oversized) fee += PricingConstants.oversizedItemFeeGbp;
    if (fragile) fee += PricingConstants.fragileHandlingFeeGbp;
    if (twoPersonHandling) fee += PricingConstants.twoPersonHandlingFeeGbp;
    if (noLift) fee += PricingConstants.noLiftFeeGbp;
    if (stairsFloors >= 1 && stairsFloors <= 2) fee += 3;
    if (stairsFloors >= 3) fee += 7;
    if (urgent) fee += 5;
    return fee;
  }

  static double parseWeightKg(String value, {double fallbackKg = 0}) {
    final match = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(value);
    if (match == null) return fallbackKg;
    return double.tryParse(match.group(1)!) ?? fallbackKg;
  }

  static double kilometresToMiles(double kilometres) => kilometres / 1.6093;

  static double _roundMoney(double value) =>
      double.parse(value.toStringAsFixed(2));
}
