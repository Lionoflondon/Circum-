import '../../pricing/delivery_pricing.dart';

class HealthPlusPricing {
  static const List<HealthPlusPlanDefinition> availablePlans = [
    HealthPlusPlanDefinition(
      value: 'core',
      label: 'Health+ Core',
      description: '2 included Health+ deliveries',
      monthlyPrice: 15,
      includedDeliveries: 2,
      overageRate: 7.5,
      benefits: [
        '2 included Health+ deliveries',
        '£7.50 baseline additional journey',
        'Vanguard handling and reminders',
      ],
    ),
    HealthPlusPlanDefinition(
      value: 'priority',
      label: 'Health+ Priority',
      description: '4 included Health+ deliveries',
      monthlyPrice: 25,
      includedDeliveries: 4,
      overageRate: 6.25,
      priorityFee: priorityFeeGbp,
      benefits: [
        '4 included Health+ deliveries',
        '£6.25 baseline additional journey',
        'Preferred rider offered first',
      ],
    ),
    HealthPlusPlanDefinition(
      value: 'family',
      label: 'Health+ Family',
      description: 'Unlimited deliveries subject to fair use',
      monthlyPrice: 40,
      familySupportFee: familySupportFeeGbp,
      benefits: [
        'Unlimited deliveries subject to fair use',
        'Family scheduling support',
        'Vanguard custody archive',
      ],
    ),
    HealthPlusPlanDefinition(
      value: 'custom',
      label: 'Health+ Custom',
      description: 'Admin-configured allowance',
      monthlyPrice: 60,
      includedDeliveries: 0,
      benefits: [
        'Admin-configured allowance',
        'Custom overage rate',
        'Tailored collection schedule',
      ],
    ),
  ];
  static const double serviceFeeGbp = 1.2;
  static const double priorityFeeGbp = 2.99;
  static const double familySupportFeeGbp = 3.99;
  static const double recurringDiscountGbp = 1.5;
  static const double minimumStartingPriceGbp = 11;
  static const double defaultMedicationWeightKg = 0.5;
  static const double defaultDistanceMiles = 4.8;

  static List<String> get supportedSubscriptionPlans =>
      availablePlans.map((plan) => plan.value).toList(growable: false);

  static HealthPlusPlanDefinition planFor(
    String value, {
    List<HealthPlusPlanDefinition> plans = availablePlans,
  }) {
    final normalized = value.toLowerCase().trim();
    return plans.firstWhere(
      (plan) => plan.value == normalized,
      orElse: () => plans.first,
    );
  }

  static List<HealthPlusPlanQuote> planQuotes({
    List<HealthPlusPlanDefinition> plans = availablePlans,
    double distanceMiles = defaultDistanceMiles,
    double medicationWeightKg = defaultMedicationWeightKg,
    bool recurring = false,
    int remainingIncludedDeliveries = 0,
    double promotionalDiscountGbp = 0,
    DeliveryPricingBreakdown? deliveryQuote,
  }) {
    final delivery = deliveryQuote ??
        HealthPlusPricing.deliveryQuote(
          distanceMiles: distanceMiles,
          medicationWeightKg: medicationWeightKg,
        );
    final base = calculate(
      distanceMiles: distanceMiles,
      medicationWeightKg: medicationWeightKg,
      recurring: recurring,
      subscriptionPlan: plans.first.value,
      plans: plans,
      remainingIncludedDeliveries: remainingIncludedDeliveries,
      promotionalDiscountGbp: promotionalDiscountGbp,
      deliveryQuote: delivery,
    );

    return plans.map((plan) {
      final quote = calculate(
        distanceMiles: distanceMiles,
        medicationWeightKg: medicationWeightKg,
        recurring: recurring,
        subscriptionPlan: plan.value,
        plans: plans,
        remainingIncludedDeliveries: remainingIncludedDeliveries,
        promotionalDiscountGbp: promotionalDiscountGbp,
        deliveryQuote: delivery,
      );
      final delta = double.parse((quote.total - base.total).toStringAsFixed(2));
      return HealthPlusPlanQuote(
        plan: plan,
        breakdown: quote,
        deltaFromBase: delta,
        displayPrice: plan.monthlyPriceLabel,
      );
    }).toList(growable: false);
  }

  static String formatGbp(double amount) => '£${amount.toStringAsFixed(2)}';

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
    String subscriptionPlan = 'core',
    List<HealthPlusPlanDefinition> plans = availablePlans,
    int remainingIncludedDeliveries = 0,
    double promotionalDiscountGbp = 0,
    DeliveryPricingBreakdown? deliveryQuote,
  }) {
    final delivery = deliveryQuote ??
        HealthPlusPricing.deliveryQuote(
          distanceMiles: distanceMiles,
          medicationWeightKg: medicationWeightKg,
        );
    final plan = planFor(subscriptionPlan, plans: plans);
    final priorityFee = plan.priorityFee;
    final familyFee = plan.familySupportFee;
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
      subscriptionPlan: plan.value,
      vanguardIncluded: true,
    );
  }
}

class HealthPlusPlanDefinition {
  final String value;
  final String label;
  final String description;
  final double priorityFee;
  final double familySupportFee;
  final double monthlyPrice;
  final int? includedDeliveries;
  final double? overageRate;
  final List<String> benefits;

  const HealthPlusPlanDefinition({
    required this.value,
    required this.label,
    required this.description,
    this.priorityFee = 0,
    this.familySupportFee = 0,
    required this.monthlyPrice,
    this.includedDeliveries,
    this.overageRate,
    this.benefits = const [],
  });

  String get monthlyPriceLabel => value == 'custom'
      ? 'From £${monthlyPrice.toStringAsFixed(0)} / month'
      : '£${monthlyPrice.toStringAsFixed(0)} / month';
}

class HealthPlusPlanQuote {
  final HealthPlusPlanDefinition plan;
  final HealthPlusPriceBreakdown breakdown;
  final double deltaFromBase;
  final String displayPrice;

  const HealthPlusPlanQuote({
    required this.plan,
    required this.breakdown,
    required this.deltaFromBase,
    required this.displayPrice,
  });
}

class HealthPlusPriceLine {
  final String label;
  final String value;

  const HealthPlusPriceLine(this.label, this.value);
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

  List<HealthPlusPriceLine> reviewLines({required String planLabel}) => [
        HealthPlusPriceLine('Plan', planLabel),
        HealthPlusPriceLine(
          'Delivery + service fee',
          HealthPlusPricing.formatGbp(delivery.total + serviceFee),
        ),
        if (priorityFee > 0)
          HealthPlusPriceLine(
            'Priority fee',
            HealthPlusPricing.formatGbp(priorityFee),
          ),
        if (familySupportFee > 0)
          HealthPlusPriceLine(
            'Family support fee',
            HealthPlusPricing.formatGbp(familySupportFee),
          ),
        if (recurringDiscount > 0)
          HealthPlusPriceLine(
            'Recurring discount',
            '-${HealthPlusPricing.formatGbp(recurringDiscount)}',
          ),
      ];

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
