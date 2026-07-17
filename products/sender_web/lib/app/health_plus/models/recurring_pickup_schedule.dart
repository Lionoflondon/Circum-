enum HealthPlusFrequency {
  oneOff,
  weekly,
  everyTwoWeeks,
  every28Days,
  monthly,
  custom,
}

extension HealthPlusFrequencyValue on HealthPlusFrequency {
  String get value {
    return switch (this) {
      HealthPlusFrequency.oneOff => 'one_off',
      HealthPlusFrequency.weekly => 'weekly',
      HealthPlusFrequency.everyTwoWeeks => 'every_2_weeks',
      HealthPlusFrequency.every28Days => 'every_28_days',
      HealthPlusFrequency.monthly => 'monthly',
      HealthPlusFrequency.custom => 'custom',
    };
  }

  String get label {
    return switch (this) {
      HealthPlusFrequency.oneOff => 'One-off pickup',
      HealthPlusFrequency.weekly => 'Weekly pickup',
      HealthPlusFrequency.everyTwoWeeks => 'Every 2 weeks',
      HealthPlusFrequency.every28Days => 'Every 28 days',
      HealthPlusFrequency.monthly => 'Monthly pickup',
      HealthPlusFrequency.custom => 'Custom repeat schedule',
    };
  }

  static HealthPlusFrequency fromValue(String value) {
    return HealthPlusFrequency.values.firstWhere(
      (frequency) => frequency.value == value,
      orElse: () => HealthPlusFrequency.oneOff,
    );
  }
}

class RecurringPickupSchedule {
  final String id;
  final String profileId;
  final HealthPlusFrequency frequency;
  final String preferredDayTime;
  final String customSchedule;
  final bool paused;
  final DateTime? nextPickupAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const RecurringPickupSchedule({
    required this.id,
    required this.profileId,
    required this.frequency,
    required this.preferredDayTime,
    required this.customSchedule,
    required this.paused,
    required this.nextPickupAt,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isRecurring => frequency != HealthPlusFrequency.oneOff;

  Map<String, dynamic> toJson() => {
        'id': id,
        'profileId': profileId,
        'frequency': frequency.value,
        'preferredDayTime': preferredDayTime,
        'customSchedule': customSchedule,
        'paused': paused,
        'nextPickupAt': nextPickupAt?.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };
}
