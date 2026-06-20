enum HealthPlusPlanType { core, priority, family, custom }

extension HealthPlusPlanTypeValue on HealthPlusPlanType {
  String get value => name;

  String get label => switch (this) {
        HealthPlusPlanType.core => 'Core',
        HealthPlusPlanType.priority => 'Priority',
        HealthPlusPlanType.family => 'Family',
        HealthPlusPlanType.custom => 'Custom',
      };

  double get monthlyPrice => switch (this) {
        HealthPlusPlanType.core => 15,
        HealthPlusPlanType.priority => 25,
        HealthPlusPlanType.family => 40,
        HealthPlusPlanType.custom => 60,
      };

  int? get includedDeliveries => switch (this) {
        HealthPlusPlanType.core => 2,
        HealthPlusPlanType.priority => 4,
        HealthPlusPlanType.family => null,
        HealthPlusPlanType.custom => 0,
      };

  double? get overageRate => switch (this) {
        HealthPlusPlanType.core => 7.5,
        HealthPlusPlanType.priority => 6.25,
        HealthPlusPlanType.family || HealthPlusPlanType.custom => null,
      };

  static HealthPlusPlanType fromValue(String value) =>
      HealthPlusPlanType.values.firstWhere(
        (plan) => plan.value == value.trim().toLowerCase(),
        orElse: () => HealthPlusPlanType.core,
      );
}

class HealthPlusSubscriptionUsage {
  final HealthPlusPlanType planType;
  final int usedDeliveries;
  final int? includedDeliveries;

  const HealthPlusSubscriptionUsage({
    required this.planType,
    required this.usedDeliveries,
    required this.includedDeliveries,
  });

  int? get remainingDeliveries => includedDeliveries == null
      ? null
      : (includedDeliveries! - usedDeliveries).clamp(0, includedDeliveries!);
}
