import 'dart:io';

import 'package:circum/app/health_plus/health_plus_pricing.dart';
import 'package:circum/app/health_plus/models/health_plus_profile.dart';
import 'package:circum/app/health_plus/models/pickup_status.dart';
import 'package:circum/app/health_plus/models/prescription_pickup.dart';
import 'package:circum/app/health_plus/models/recurring_pickup_schedule.dart';
import 'package:circum/app/health_plus/models/health_plus_subscription.dart';
import 'package:circum/app/health_plus/models/health_plus_custody_event.dart';
import 'package:circum/pricing/delivery_pricing.dart';
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
      expect(quote.vanguardIncluded, isTrue);
      expect(quote.toJson()['vanguardInvoiceLabel'], 'Included with Health+');
    });

    test('consumes shared delivery pricing without recalculating mileage', () {
      final deliveryQuote = DeliveryPricing.calculate(
        const DeliveryPricingInput(
          distanceMiles: 2,
          weightKg: 0.5,
          vehicleType: 'car',
        ),
      );
      final quote = HealthPlusPricing.calculate(
        deliveryQuote: deliveryQuote,
        remainingIncludedDeliveries: 0,
      );

      expect(quote.delivery.distanceFare, deliveryQuote.distanceFare);
      expect(quote.delivery.vehicleSurcharge, deliveryQuote.vehicleSurcharge);
      expect(quote.delivery.total, deliveryQuote.total);
      expect(quote.total, deliveryQuote.total + quote.serviceFee);
    });

    test('policy discounts apply after delivery pricing', () {
      final deliveryQuote = DeliveryPricing.calculate(
        const DeliveryPricingInput(
          distanceMiles: 8,
          weightKg: 0.5,
          vehicleType: 'bike',
        ),
      );
      final quote = HealthPlusPricing.calculate(
        deliveryQuote: deliveryQuote,
        recurring: true,
        promotionalDiscountGbp: 2,
      );

      expect(quote.delivery.total, deliveryQuote.total);
      expect(quote.recurringDiscount, HealthPlusPricing.recurringDiscountGbp);
      expect(quote.promotionalDiscount, 2);
      expect(
        quote.total,
        deliveryQuote.total +
            quote.serviceFee -
            quote.recurringDiscount -
            quote.promotionalDiscount,
      );
    });

    test(
        'included deliveries reduce payable amount without changing delivery quote',
        () {
      final deliveryQuote = DeliveryPricing.calculate(
        const DeliveryPricingInput(
          distanceMiles: 8,
          weightKg: 0.5,
          vehicleType: 'bike',
        ),
      );
      final quote = HealthPlusPricing.calculate(
        deliveryQuote: deliveryQuote,
        remainingIncludedDeliveries: 1,
      );

      expect(quote.delivery.total, deliveryQuote.total);
      expect(quote.includedDeliveryCredit, deliveryQuote.total);
      expect(quote.total, HealthPlusPricing.minimumStartingPriceGbp);
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

    test('guided mobile Health+ view uses approved customer copy', () {
      final source =
          File('lib/app/health_plus/view/health_plus.dart').readAsStringSync();

      expect(source, contains('class HealthStatusView'));
      expect(source, contains('class HealthPlusView extends HealthStatusView'));
      expect(source, contains('Your Care'));
      expect(source, contains("We'll help you stay on schedule."));
      expect(source, contains('Who are we caring for?'));
      expect(source, contains('Which pharmacy has your prescription?'));
      expect(source, contains('Where should we deliver it?'));
      expect(
        source,
        contains('How should we look after this prescription?'),
      );
      expect(source, contains('Anything we should know?'));
      expect(source, contains('Everything looks ready.'));
      expect(source, contains("You're all set."));
      expect(
        source,
        contains(
          "We'll collect your prescription and keep you updated every step of the way.",
        ),
      );
    });

    test('guided mobile Health+ reuses backend integrations', () {
      final source =
          File('lib/app/health_plus/view/health_plus.dart').readAsStringSync();

      expect(source, contains('HealthPlusPricing.calculate'));
      expect(source, contains('HealthPlusFrequency.values'));
      expect(source, contains('PickupStatus.scheduled.value'));
      expect(source, contains('PlaceApiProvider'));
      expect(source, contains('createHealthPlusCheckoutSession'));
      expect(source, contains('launchUrl'));
      expect(source, contains("collection('healthPlusProfiles')"));
      expect(source, contains("collection('prescriptionPickups')"));
      expect(source, contains("collection('recurringPickupSchedules')"));
      expect(source, contains("collection('healthPlusPayments')"));
      expect(source, contains('pricingBreakdown'));
      expect(source, contains('Admin status overrides belong in Admin.'));
      expect(source, isNot(contains('class _AdminPanel')));
      expect(source, isNot(contains('Admin operations')));
    });

    test('Health+ tab renders the guided status view', () {
      final source =
          File('lib/app/bottom_nav/view/app_nav.dart').readAsStringSync();

      expect(source, contains('const HealthStatusView()'));
      expect(source, isNot(contains('const HealthPlusView(),')));
    });
  });
}
