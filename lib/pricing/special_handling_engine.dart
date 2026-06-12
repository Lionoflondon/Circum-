import 'delivery_pricing.dart';

enum DeliveryAccess { groundFloor, liftAvailable, stairs }

enum SpecialHandlingClass { none, assisted, heavyDuty }

class SpecialHandlingResult {
  final SpecialHandlingClass handlingClass;
  final double assistedFee;
  final double heavyDutyFee;
  final double twoPersonFee;
  final bool requiresAccessQuestions;
  final bool twoPersonRequired;
  final String explanation;

  const SpecialHandlingResult({
    required this.handlingClass,
    required this.assistedFee,
    required this.heavyDutyFee,
    required this.twoPersonFee,
    required this.requiresAccessQuestions,
    required this.twoPersonRequired,
    required this.explanation,
  });

  double get labourPremium => assistedFee + heavyDutyFee + twoPersonFee;

  DeliveryPricingBreakdown applyTo(DeliveryPricingBreakdown base) {
    final riderBaseShare = DeliveryPricing.riderPayoutFromFare(base.total);
    final circumBaseShare = DeliveryPricing.platformRevenueFromFare(base.total);
    final riderLabourShare = _handlingMoney(labourPremium * 0.80);
    final circumLabourShare = _handlingMoney(labourPremium * 0.20);
    return DeliveryPricingBreakdown(
      baseFare: base.baseFare,
      distanceFare: base.distanceFare,
      weightSurcharge: base.weightSurcharge,
      vehicleSurcharge: base.vehicleSurcharge,
      specialConditions: base.specialConditions,
      serviceLevelSurcharge: base.serviceLevelSurcharge,
      serviceLevel: base.serviceLevel,
      surgeMultiplier: base.surgeMultiplier,
      total: _handlingMoney(base.total + labourPremium),
      weightCategory: base.weightCategory,
      assistedFee: assistedFee,
      heavyDutyFee: heavyDutyFee,
      twoPersonFee: twoPersonFee,
      riderBaseShare: riderBaseShare,
      riderLabourShare: riderLabourShare,
      circumBaseShare: circumBaseShare,
      circumLabourShare: circumLabourShare,
      totalRiderEarnings: _handlingMoney(riderBaseShare + riderLabourShare),
      totalCircumRevenue: _handlingMoney(circumBaseShare + circumLabourShare),
    );
  }
}

class SpecialHandlingEngine {
  static const assistedDeliveryFee = 15.0;
  static const heavyDutyFee = 30.0;
  static const twoPersonFee = 50.0;

  static const _alwaysTwoPerson = [
    'grand piano',
    'upright piano',
    'piano',
    'large commercial safe',
    'requires two people',
    'two person',
    '2 person',
  ];

  static const _heavyDuty = [
    'deep freezer',
    'american fridge freezer',
    'fridge freezer',
    'washing machine',
    'tumble dryer',
    'wardrobe',
    'large sofa',
    'dining table',
    'commercial safe',
    'large appliance',
    'large furniture',
    'grand piano',
    'upright piano',
    'piano',
  ];

  static const _assisted = [
    'office chair',
    'small furniture',
    'multiple light boxes',
    'monitor setup',
    'desktop pc plus boxes',
    'desktop pc and boxes',
  ];

  static SpecialHandlingResult evaluate({
    required String description,
    String? itemName,
    DeliveryAccess pickupAccess = DeliveryAccess.groundFloor,
    DeliveryAccess dropoffAccess = DeliveryAccess.groundFloor,
  }) {
    final text = '${itemName ?? ''} $description'.toLowerCase();
    final heavy = _heavyDuty.any(text.contains);
    final assisted = !heavy && _assisted.any(text.contains);
    final accessHasStairs = pickupAccess == DeliveryAccess.stairs ||
        dropoffAccess == DeliveryAccess.stairs;
    final alwaysTwoPerson = _alwaysTwoPerson.any(text.contains);
    final twoPerson = heavy && (alwaysTwoPerson || accessHasStairs);

    if (heavy) {
      return SpecialHandlingResult(
        handlingClass: SpecialHandlingClass.heavyDuty,
        assistedFee: 0,
        heavyDutyFee: heavyDutyFee,
        twoPersonFee: twoPerson ? twoPersonFee : 0,
        requiresAccessQuestions: true,
        twoPersonRequired: twoPerson,
        explanation: twoPerson
            ? 'Heavy Duty and Two Person fees added because this item or its access conditions may require two people.'
            : 'Heavy Duty fee added because this item may require careful lifting or handling.',
      );
    }
    if (assisted) {
      return const SpecialHandlingResult(
        handlingClass: SpecialHandlingClass.assisted,
        assistedFee: assistedDeliveryFee,
        heavyDutyFee: 0,
        twoPersonFee: 0,
        requiresAccessQuestions: true,
        twoPersonRequired: false,
        explanation:
            'Assisted Delivery fee added because this item may need light handling help.',
      );
    }
    return const SpecialHandlingResult(
      handlingClass: SpecialHandlingClass.none,
      assistedFee: 0,
      heavyDutyFee: 0,
      twoPersonFee: 0,
      requiresAccessQuestions: false,
      twoPersonRequired: false,
      explanation: '',
    );
  }
}

double _handlingMoney(double value) => double.parse(value.toStringAsFixed(2));
