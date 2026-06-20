import 'package:circum/app/health_plus/health_plus_pricing.dart';
import 'package:circum/app/health_plus/models/health_plus_profile.dart';
import 'package:circum/app/health_plus/models/pickup_status.dart';
import 'package:circum/app/health_plus/models/prescription_pickup.dart';
import 'package:circum/app/health_plus/models/recurring_pickup_schedule.dart';
import 'package:circum/app/health_plus/models/health_plus_subscription.dart';
import 'package:circum/app/health_plus/models/health_plus_custody_event.dart';
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

      expect(quote.delivery.baseFare, 6);
      expect(quote.serviceFee, HealthPlusPricing.serviceFeeGbp);
      expect(quote.total, 11);
      expect(quote.amountPence, 1100);
    });

    test('cancelling or pausing uses explicit status fields', () {
      expect(PickupStatusValue.fromValue('cancelled'), PickupStatus.cancelled);
      expect(PickupStatus.failed.value, 'failed');
    });

    test('defines launch subscription allowances and overage rates', () {
      expect(HealthPlusPlanType.core.monthlyPrice, 15);
      expect(HealthPlusPlanType.core.includedDeliveries, 2);
      expect(HealthPlusPlanType.core.overageRate, 7.5);
      expect(HealthPlusPlanType.priority.includedDeliveries, 4);
      expect(HealthPlusPlanType.family.includedDeliveries, isNull);

      const usage = HealthPlusSubscriptionUsage(
        planType: HealthPlusPlanType.priority,
        usedDeliveries: 3,
        includedDeliveries: 4,
      );
      expect(usage.remainingDeliveries, 1);
    });

    test('creates customer-safe custody archive entries', () {
      final event = HealthPlusCustodyEvent(
        eventType: 'rider_assigned',
        timestamp: DateTime.utc(2026, 6, 20),
        actorType: 'system',
        publicMessage: 'A verified rider has been assigned.',
        statusAfterEvent: 'assigned',
      );
      expect(event.toJson()['publicMessage'], contains('verified rider'));
      expect(event.toJson()['internalNote'], isNull);
    });
  });
}
