class PricingConstants {
  static const double baseFareGbp = 5;
  static const double additionalFarePerMileGbp = 1.5;
  static const double includedBaseMiles = 0;
  static const double shortTripFareFloorMiles = 1.6;
  static const double longDistanceThresholdMiles = 20;
  static const double longDistanceMileageMultiplier = 1.2;
  static const double fixedExpressSurchargeGbp = 2.99;
  static const double expressMultiplier = 1.2;

  static const Map<String, double> specialConditionFeesGbp = {
    'oversized': 10,
    'fragile': 5,
    'twoPersonHandling': 25,
    'noLift': 3,
    'stairsOneToTwoFloors': 3,
    'stairsThreePlusFloors': 7,
    'priority': 5,
    'express': 10,
    'waitingAdditionalFiveMinutes': 2,
  };

  static const List<WeightBand> weightBands = [
    WeightBand(
      category: 'Small Parcel',
      minKg: 0,
      maxKg: 5,
      surchargeGbp: 0,
    ),
    WeightBand(
      category: 'Medium Parcel',
      minKg: 5,
      maxKg: 10,
      surchargeGbp: 3,
    ),
    WeightBand(
      category: 'Heavy Parcel',
      minKg: 10,
      maxKg: 20,
      surchargeGbp: 7,
    ),
    WeightBand(
      category: 'Large Item',
      minKg: 20,
      maxKg: 40,
      surchargeGbp: 15,
    ),
    WeightBand(
      category: 'Extra Heavy',
      minKg: 40,
      maxKg: null,
      surchargeGbp: 0,
      requiresManualQuote: true,
    ),
  ];

  static const Map<String, double> vehicleSurchargesGbp = {
    'bike': 0,
    'bicycle': 0,
    'car': 0,
    'estate': 5,
    'suv': 5,
    'estate/suv': 5,
    'van': 10,
    'luton van': 0,
  };
}

class WeightBand {
  final String category;
  final double minKg;
  final double? maxKg;
  final double surchargeGbp;
  final bool requiresManualQuote;

  const WeightBand({
    required this.category,
    required this.minKg,
    required this.maxKg,
    required this.surchargeGbp,
    this.requiresManualQuote = false,
  });

  bool contains(double weightKg) {
    final aboveMinimum = weightKg > minKg || minKg == 0 && weightKg >= 0;
    final belowMaximum = maxKg == null || weightKg <= maxKg!;
    return aboveMinimum && belowMaximum;
  }
}
