import '../../pricing/delivery_pricing.dart';

class HealthPlusPricing {
  static const double serviceFeeGbp = 1.2;
  static const double basicMonthlyPriceGbp = 11;
  static const double priorityMonthlyPriceGbp = 25;
  static const double familyMonthlyPriceGbp = 40;
  static const double minimumStartingPriceGbp = 11;
  static const double defaultMedicationWeightKg = 0.5;
  static const double defaultDistanceMiles = 4.8;

  static HealthPlusPlan planFor(String subscriptionPlan) {
    final id = subscriptionPlan.toLowerCase().trim();
    return switch (id) {
      'priority' => const HealthPlusPlan(
          id: 'priority',
          title: 'Health+ Priority',
          monthlyPrice: priorityMonthlyPriceGbp,
          includedPickups: 4,
          unlimited: false,
          fairUseMonitored: false,
        ),
      'family' => const HealthPlusPlan(
          id: 'family',
          title: 'Health+ Family',
          monthlyPrice: familyMonthlyPriceGbp,
          includedPickups: null,
          unlimited: true,
          fairUseMonitored: true,
        ),
      _ => const HealthPlusPlan(
          id: 'basic',
          title: 'Health+ Basic',
          monthlyPrice: basicMonthlyPriceGbp,
          includedPickups: 2,
          unlimited: false,
          fairUseMonitored: false,
        ),
    };
  }

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
    final plan = planFor(subscriptionPlan);
    final subtotal = delivery.total + serviceFeeGbp;
    final oneOffTotal = subtotal < minimumStartingPriceGbp
        ? minimumStartingPriceGbp
        : double.parse(subtotal.toStringAsFixed(2));
    final total = recurring ? plan.monthlyPrice : oneOffTotal;

    return HealthPlusPriceBreakdown(
      delivery: delivery,
      serviceFee: serviceFeeGbp,
      priorityFee: 0,
      familySupportFee: 0,
      recurringDiscount: 0,
      minimumAdjustment: recurring
          ? 0
          : double.parse((oneOffTotal - subtotal).toStringAsFixed(2)),
      total: total,
      recurring: recurring,
      subscriptionPlan: plan.id,
      monthlyPlanPrice: plan.monthlyPrice,
      includedPickups: plan.includedPickups,
      unlimitedPickups: plan.unlimited,
      fairUseMonitored: plan.fairUseMonitored,
    );
  }
}

class HealthPlusPlan {
  final String id;
  final String title;
  final double monthlyPrice;
  final int? includedPickups;
  final bool unlimited;
  final bool fairUseMonitored;

  const HealthPlusPlan({
    required this.id,
    required this.title,
    required this.monthlyPrice,
    required this.includedPickups,
    required this.unlimited,
    required this.fairUseMonitored,
  });
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
  final double monthlyPlanPrice;
  final int? includedPickups;
  final bool unlimitedPickups;
  final bool fairUseMonitored;

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
    required this.monthlyPlanPrice,
    required this.includedPickups,
    required this.unlimitedPickups,
    required this.fairUseMonitored,
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
        'monthlyPlanPrice': monthlyPlanPrice,
        'includedPickups': includedPickups,
        'unlimitedPickups': unlimitedPickups,
        'fairUseMonitored': fairUseMonitored,
      };
}
