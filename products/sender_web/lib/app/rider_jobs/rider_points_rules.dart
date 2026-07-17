import 'rider_job_models.dart';

class RiderPointsAward {
  final RiderJobCategory category;
  final String label;
  final int points;

  const RiderPointsAward({
    required this.category,
    required this.label,
    required this.points,
  });
}

class RiderPointsRules {
  static const Map<RiderJobCategory, int> pointsByCategory = {
    RiderJobCategory.standard: 1,
    RiderJobCategory.marketplace: 2,
    RiderJobCategory.business: 3,
    RiderJobCategory.vanguard: 4,
    RiderJobCategory.heavyDuty: 4,
    RiderJobCategory.gift: 5,
    RiderJobCategory.scheduled: 5,
    RiderJobCategory.healthPlus: 6,
  };

  static const List<RiderJobCategory> priority = [
    RiderJobCategory.healthPlus,
    RiderJobCategory.gift,
    RiderJobCategory.scheduled,
    RiderJobCategory.vanguard,
    RiderJobCategory.business,
    RiderJobCategory.marketplace,
    RiderJobCategory.standard,
  ];

  static RiderPointsAward awardFor(Set<RiderJobCategory> categories) {
    final selected = priority.firstWhere(
      categories.contains,
      orElse: () => RiderJobCategory.standard,
    );
    return RiderPointsAward(
      category: selected,
      label: labelFor(selected),
      points: pointsByCategory[selected] ?? 1,
    );
  }

  static String labelFor(RiderJobCategory category) {
    return switch (category) {
      RiderJobCategory.healthPlus => 'Health+',
      RiderJobCategory.gift => 'Gift',
      RiderJobCategory.scheduled => 'Scheduled',
      RiderJobCategory.vanguard => 'Vanguard',
      RiderJobCategory.heavyDuty => 'Heavy Duty',
      RiderJobCategory.business => 'Business',
      RiderJobCategory.marketplace => 'Marketplace',
      RiderJobCategory.standard => 'Standard',
    };
  }
}
