import 'package:circum/app/rider_jobs/rider_job_models.dart';
import 'package:circum/app/rider_jobs/rider_points_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RiderPointsRules', () {
    test('uses launch point table', () {
      expect(RiderPointsRules.pointsByCategory[RiderJobCategory.standard], 1);
      expect(
          RiderPointsRules.pointsByCategory[RiderJobCategory.marketplace], 2);
      expect(RiderPointsRules.pointsByCategory[RiderJobCategory.business], 3);
      expect(RiderPointsRules.pointsByCategory[RiderJobCategory.vanguard], 4);
      expect(RiderPointsRules.pointsByCategory[RiderJobCategory.heavyDuty], 4);
      expect(RiderPointsRules.pointsByCategory[RiderJobCategory.gift], 5);
      expect(RiderPointsRules.pointsByCategory[RiderJobCategory.scheduled], 5);
      expect(RiderPointsRules.pointsByCategory[RiderJobCategory.healthPlus], 6);
    });

    test('category priority favours Health+ over other flags', () {
      final award = RiderPointsRules.awardFor({
        RiderJobCategory.business,
        RiderJobCategory.vanguard,
        RiderJobCategory.gift,
        RiderJobCategory.healthPlus,
      });
      expect(award.category, RiderJobCategory.healthPlus);
      expect(award.points, 6);
    });

    test('missing category falls back to Standard +1', () {
      final award = RiderPointsRules.awardFor({});
      expect(award.category, RiderJobCategory.standard);
      expect(award.points, 1);
      expect(award.label, 'Standard');
    });
  });
}
