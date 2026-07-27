import 'dart:io';

import 'package:circum/app/health_plus/health_plus_pricing.dart';
import 'package:circum/app/health_plus/models/health_plus_profile.dart';
import 'package:circum/app/health_plus/models/pickup_status.dart';
import 'package:circum/app/health_plus/models/prescription_pickup.dart';
import 'package:circum/app/health_plus/models/recurring_pickup_schedule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Health+', () {
    test('creates a Health+ profile payload', () {
      final now = DateTime.utc(2026, 5, 29);
      final profile = HealthPlusProfile(
        id: 'hp_1',
        fullName: 'Jane Smith',
        phoneNumber: '+447700900123',
        pharmacyAddress: 'Shoreditch Pharmacy',
        deliveryAddress: 'Canary Wharf',
        notes: 'Prescription ready after 2pm',
        consentConfirmed: true,
        createdAt: now,
        updatedAt: now,
      );

      expect(profile.toJson()['fullName'], 'Jane Smith');
      expect(profile.toJson()['consentConfirmed'], isTrue);
    });

    test('books a one-off prescription pickup', () {
      final now = DateTime.utc(2026, 5, 29);
      final pickup = PrescriptionPickup(
        id: 'pickup_1',
        profileId: 'hp_1',
        scheduleId: null,
        pharmacyAddress: 'Shoreditch Pharmacy',
        deliveryAddress: 'Canary Wharf',
        notes: 'Sealed bag only',
        status: PickupStatus.scheduled,
        assignedDriverId: null,
        preferredPickupAt: now.add(const Duration(days: 1)),
        createdAt: now,
        updatedAt: now,
      );

      expect(pickup.toJson()['status'], 'scheduled');
      expect(pickup.toJson()['scheduleId'], isNull);
    });

    test('creates recurring pickups', () {
      final now = DateTime.utc(2026, 5, 29);
      final schedule = RecurringPickupSchedule(
        id: 'schedule_1',
        profileId: 'hp_1',
        frequency: HealthPlusFrequency.everyTwoWeeks,
        preferredDayTime: 'Tuesday 10:00',
        customSchedule: '',
        paused: false,
        nextPickupAt: now.add(const Duration(days: 14)),
        createdAt: now,
        updatedAt: now,
      );

      expect(schedule.isRecurring, isTrue);
      expect(schedule.toJson()['frequency'], 'every_2_weeks');
    });

    test('uses delivery pricing plus Health+ minimum starting price', () {
      final quote = HealthPlusPricing.calculate();

      expect(quote.delivery.baseFare, 5);
      expect(quote.serviceFee, HealthPlusPricing.serviceFeeGbp);
      expect(quote.total, 13.4);
      expect(quote.amountPence, 1340);
    });

    test('applies the Health+ minimum only below the floor', () {
      final quote = HealthPlusPricing.calculate(distanceMiles: 0.1);

      expect(quote.total, HealthPlusPricing.minimumStartingPriceGbp);
      expect(quote.minimumAdjustment, greaterThan(0));
    });

    test('does not double-apply the Health+ minimum at the floor', () {
      final quote = HealthPlusPricing.calculate(distanceMiles: 3.2);

      expect(quote.total, HealthPlusPricing.minimumStartingPriceGbp);
      expect(quote.minimumAdjustment, 0);
    });

    test('prices Health+ above the minimum with service uplifts', () {
      final quote = HealthPlusPricing.calculate(
        distanceMiles: 8,
        subscriptionPlan: 'priority',
      );

      expect(
          quote.total, greaterThan(HealthPlusPricing.minimumStartingPriceGbp));
      expect(quote.priorityFee, HealthPlusPricing.priorityFeeGbp);
      expect(quote.minimumAdjustment, lessThanOrEqualTo(0));
    });

    test('cancelling or pausing uses explicit status fields', () {
      expect(PickupStatusValue.fromValue('cancelled'), PickupStatus.cancelled);
      expect(PickupStatus.failed.value, 'failed');
    });

    test('app pickup preference requires full date and time selection', () {
      final source =
          File('lib/app/health_plus/view/health_plus.dart').readAsStringSync();

      expect(source, contains('_HealthDateTimeInput'));
      expect(source, contains('showDatePicker'));
      expect(source, contains('showTimePicker'));
      expect(source, contains('Preferred pickup date and time'));
      expect(source, contains('Choose day, month, year and time.'));
      expect(source, contains("_formatHealthPickupDateTime"));
      expect(source, isNot(contains("Tuesday, 10:00 AM")));
    });
  });
}
