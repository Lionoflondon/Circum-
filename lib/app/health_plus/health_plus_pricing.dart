import '../../pricing/delivery_pricing.dart';

class HealthPlusPricing {
  static const double serviceFeeGbp = 1.2;
  static const double minimumStartingPriceGbp = 11;
  static const double defaultMedicationWeightKg = 0.5;
  static const double defaultDistanceMiles = 4.8;

  static HealthPlusPriceBreakdown calculate({
    double distanceMiles = defaultDistanceMiles,
    double medicationWeightKg = defaultMedicationWeightKg,
    bool recurring = false,
  }) {
    final delivery = DeliveryPricing.calculate(
      DeliveryPricingInput(
        distanceMiles: distanceMiles,
        weightKg: medicationWeightKg,
        vehicleType: 'bike',
      ),
    );
    final subtotal = delivery.total + serviceFeeGbp;
    final total = subtotal < minimumStartingPriceGbp
        ? minimumStartingPriceGbp
        : double.parse(subtotal.toStringAsFixed(2));

    return HealthPlusPriceBreakdown(
      delivery: delivery,
      serviceFee: serviceFeeGbp,
      minimumAdjustment: double.parse((total - subtotal).toStringAsFixed(2)),
      total: total,
      recurring: recurring,
    );
  }
}

class HealthPlusPriceBreakdown {
  final DeliveryPricingBreakdown delivery;
  final double serviceFee;
  final double minimumAdjustment;
  final double total;
  final bool recurring;

  const HealthPlusPriceBreakdown({
    required this.delivery,
    required this.serviceFee,
    required this.minimumAdjustment,
    required this.total,
    required this.recurring,
  });

  int get amountPence => (total * 100).round();

  Map<String, dynamic> toJson() => {
        'baseFare': delivery.baseFare,
        'distanceFare': delivery.distanceFare,
        'weightSurcharge': delivery.weightSurcharge,
        'serviceFee': serviceFee,
        'minimumAdjustment': minimumAdjustment,
        'total': total,
        'recurring': recurring,
      };
}
