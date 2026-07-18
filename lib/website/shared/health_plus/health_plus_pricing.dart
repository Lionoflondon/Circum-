import '../pricing/website_delivery_pricing.dart';

class HealthPlusPricing {
  static const double serviceFeeGbp = 1.2;
  static const double priorityFeeGbp = 2.99;
  static const double familySupportFeeGbp = 3.99;
  static const double recurringDiscountGbp = 1.5;
  static const double minimumStartingPriceGbp = 11;
  static const double defaultMedicationWeightKg = 0.5;
  static const double defaultDistanceMiles = 4.8;

  static HealthPlusPriceBreakdown calculate({
    double distanceMiles = defaultDistanceMiles,
    double medicationWeightKg = defaultMedicationWeightKg,
    bool recurring = false,
    String subscriptionPlan = 'basic',
  }) {
    final delivery = DeliveryPricing.calculate(
      DeliveryPricingInput(
        distanceMiles: distanceMiles,
        weightKg: medicationWeightKg,
        vehicleType: 'bike',
      ),
    );
    final normalizedPlan = subscriptionPlan.toLowerCase().trim();
    final priorityFee =
        normalizedPlan == 'priority' ? priorityFeeGbp : 0.toDouble();
    final familyFee =
        normalizedPlan == 'family' ? familySupportFeeGbp : 0.toDouble();
    final recurringDiscount = recurring ? recurringDiscountGbp : 0.toDouble();
    final subtotal = delivery.total +
        serviceFeeGbp +
        priorityFee +
        familyFee -
        recurringDiscount;
    final total = subtotal < minimumStartingPriceGbp
        ? minimumStartingPriceGbp
        : double.parse(subtotal.toStringAsFixed(2));

    return HealthPlusPriceBreakdown(
      delivery: delivery,
      serviceFee: serviceFeeGbp,
      priorityFee: priorityFee,
      familySupportFee: familyFee,
      recurringDiscount: recurringDiscount,
      minimumAdjustment: double.parse((total - subtotal).toStringAsFixed(2)),
      total: total,
      recurring: recurring,
      subscriptionPlan: normalizedPlan.isEmpty ? 'basic' : normalizedPlan,
    );
  }
}

class HealthPlusPriceBreakdown {
  final DeliveryPricingBreakdown delivery;
  final double serviceFee;
  final double priorityFee;
  final double familySupportFee;
  final double recurringDiscount;
  final double minimumAdjustment;
  final double total;
  final bool recurring;
  final String subscriptionPlan;

  const HealthPlusPriceBreakdown({
    required this.delivery,
    required this.serviceFee,
    required this.priorityFee,
    required this.familySupportFee,
    required this.recurringDiscount,
    required this.minimumAdjustment,
    required this.total,
    required this.recurring,
    required this.subscriptionPlan,
  });

  int get amountPence => (total * 100).round();

  Map<String, dynamic> toJson() => {
        'baseFare': delivery.baseFare,
        'distanceFare': delivery.distanceFare,
        'weightSurcharge': delivery.weightSurcharge,
        'serviceFee': serviceFee,
        'priorityFee': priorityFee,
        'familySupportFee': familySupportFee,
        'recurringDiscount': recurringDiscount,
        'minimumAdjustment': minimumAdjustment,
        'total': total,
        'recurring': recurring,
        'subscriptionPlan': subscriptionPlan,
      };
}
