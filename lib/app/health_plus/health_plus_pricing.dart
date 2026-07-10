import '../../pricing/delivery_pricing.dart';

class HealthPlusPricing {
  static const List<String> supportedSubscriptionPlans = [
    'basic',
    'priority',
    'family',
  ];
  static const double serviceFeeGbp = 1.2;
  static const double priorityFeeGbp = 2.99;
  static const double familySupportFeeGbp = 3.99;
  static const double recurringDiscountGbp = 1.5;
  static const double minimumStartingPriceGbp = 11;
  static const double defaultMedicationWeightKg = 0.5;
  static const double defaultDistanceMiles = 4.8;

  static DeliveryPricingBreakdown deliveryQuote({
    double distanceMiles = defaultDistanceMiles,
    double medicationWeightKg = defaultMedicationWeightKg,
  }) {
    return DeliveryPricing.calculate(
      DeliveryPricingInput(
        distanceMiles: distanceMiles,
        weightKg: medicationWeightKg,
        vehicleType: 'bike',
      ),
    );
  }

  static HealthPlusPriceBreakdown calculate({
    double distanceMiles = defaultDistanceMiles,
    double medicationWeightKg = defaultMedicationWeightKg,
    bool recurring = false,
    String subscriptionPlan = 'basic',
    int remainingIncludedDeliveries = 0,
    double promotionalDiscountGbp = 0,
    DeliveryPricingBreakdown? deliveryQuote,
  }) {
    final delivery = deliveryQuote ??
        HealthPlusPricing.deliveryQuote(
          distanceMiles: distanceMiles,
          medicationWeightKg: medicationWeightKg,
        );
    final normalizedPlan = subscriptionPlan.toLowerCase().trim();
    final priorityFee =
        normalizedPlan == 'priority' ? priorityFeeGbp : 0.toDouble();
    final familyFee =
        normalizedPlan == 'family' ? familySupportFeeGbp : 0.toDouble();
    final recurringDiscount = recurring ? recurringDiscountGbp : 0.toDouble();
    final includedDeliveryCredit =
        remainingIncludedDeliveries > 0 ? delivery.total : 0.toDouble();
    final policyDiscount = recurringDiscount +
        includedDeliveryCredit +
        (promotionalDiscountGbp < 0 ? 0 : promotionalDiscountGbp);
    final subtotal = delivery.total +
        serviceFeeGbp +
        priorityFee +
        familyFee -
        policyDiscount;
    final policyAdjustedSubtotal = subtotal < 0 ? 0.toDouble() : subtotal;
    final total = policyAdjustedSubtotal < minimumStartingPriceGbp
        ? minimumStartingPriceGbp
        : double.parse(policyAdjustedSubtotal.toStringAsFixed(2));

    return HealthPlusPriceBreakdown(
      delivery: delivery,
      serviceFee: serviceFeeGbp,
      priorityFee: priorityFee,
      familySupportFee: familyFee,
      recurringDiscount: recurringDiscount,
      includedDeliveryCredit: includedDeliveryCredit,
      promotionalDiscount:
          promotionalDiscountGbp < 0 ? 0 : promotionalDiscountGbp,
      minimumAdjustment:
          double.parse((total - policyAdjustedSubtotal).toStringAsFixed(2)),
      total: total,
      recurring: recurring,
      subscriptionPlan: normalizedPlan.isEmpty ? 'basic' : normalizedPlan,
      vanguardIncluded: true,
    );
  }
}

class HealthPlusPriceBreakdown {
  final DeliveryPricingBreakdown delivery;
  final double serviceFee;
  final double priorityFee;
  final double familySupportFee;
  final double recurringDiscount;
  final double includedDeliveryCredit;
  final double promotionalDiscount;
  final double minimumAdjustment;
  final double total;
  final bool recurring;
  final String subscriptionPlan;
  final bool vanguardIncluded;

  const HealthPlusPriceBreakdown({
    required this.delivery,
    required this.serviceFee,
    required this.priorityFee,
    required this.familySupportFee,
    required this.recurringDiscount,
    this.includedDeliveryCredit = 0,
    this.promotionalDiscount = 0,
    required this.minimumAdjustment,
    required this.total,
    required this.recurring,
    required this.subscriptionPlan,
    this.vanguardIncluded = true,
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
        'includedDeliveryCredit': includedDeliveryCredit,
        'promotionalDiscount': promotionalDiscount,
        'minimumAdjustment': minimumAdjustment,
        'total': total,
        'recurring': recurring,
        'subscriptionPlan': subscriptionPlan,
        'vanguardIncluded': vanguardIncluded,
        'vanguardInvoiceLabel': 'Included with Health+',
      };
}
