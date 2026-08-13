import 'dart:io';

import 'package:circum/app/health_plus/health_plus_pricing.dart';
import 'package:circum/app/health_plus/models/health_plus_profile.dart';
import 'package:circum/app/health_plus/models/pickup_status.dart';
import 'package:circum/app/health_plus/models/prescription_pickup.dart';
import 'package:circum/app/health_plus/models/recurring_pickup_schedule.dart';
import 'package:circum/app/platform/address_engine.dart';
import 'package:circum/app/send_package/models/suggestions.m.dart';
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
        quote.total,
        greaterThan(HealthPlusPricing.minimumStartingPriceGbp),
      );
      expect(quote.priorityFee, 0);
      expect(quote.minimumAdjustment, lessThanOrEqualTo(0));
    });

    test('subscriptions use the locked Health+ monthly plan model', () {
      final basic = HealthPlusPricing.calculate(
        recurring: true,
        subscriptionPlan: 'basic',
      );
      final priority = HealthPlusPricing.calculate(
        recurring: true,
        subscriptionPlan: 'priority',
      );
      final family = HealthPlusPricing.calculate(
        recurring: true,
        subscriptionPlan: 'family',
      );

      expect(basic.total, 11);
      expect(basic.includedPickups, 2);
      expect(priority.total, 25);
      expect(priority.includedPickups, 4);
      expect(family.total, 40);
      expect(family.unlimitedPickups, isTrue);
      expect(family.fairUseMonitored, isTrue);
      expect(priority.priorityFee, 0);
      expect(family.familySupportFee, 0);
      expect(family.recurringDiscount, 0);
    });

    test('cancelling or pausing uses explicit status fields', () {
      expect(PickupStatusValue.fromValue('cancelled'), PickupStatus.cancelled);
      expect(PickupStatus.failed.value, 'failed');
    });

    test('app pickup preference requires full date and time selection', () {
      final source = File(
        'lib/app/health_plus/view/health_plus.dart',
      ).readAsStringSync();

      expect(source, contains('_HealthDateTimeInput'));
      expect(source, contains('showDatePicker'));
      expect(source, contains('showTimePicker'));
      expect(source, contains('Preferred pickup date and time'));
      expect(source, contains('Choose day, month, year and time.'));
      expect(source, contains("_formatHealthPickupDateTime"));
      expect(source, isNot(contains("Tuesday, 10:00 AM")));
    });

    test('app booking plans match the public Health+ plan copy', () {
      final source = File(
        'lib/app/health_plus/view/health_plus.dart',
      ).readAsStringSync();

      expect(source, contains('Health+ Basic'));
      expect(
        source,
        contains('2 Health+ prescription pickups every calendar month'),
      );
      expect(source, contains('Medicine delivery reminders'));
      expect(source, contains('Secure sealed-package handover'));
      expect(source, contains('Health+ Priority'));
      expect(source, contains('£25/month'));
      expect(
        source,
        contains('4 Health+ prescription pickups every calendar month'),
      );
      expect(source, contains('Priority Circum Rider matching'));
      expect(source, contains('Faster pickup target'));
      expect(source, contains('Medicine reminders'));
      expect(source, contains('Health+ Family'));
      expect(source, contains('£40/month'));
      expect(source, contains('Unlimited Health+ prescription pickups'));
      expect(source, contains('Family member support'));
      expect(source, contains('Shared pickup notes'));
      expect(source, contains('Repeat medicine reminders'));
      expect(source, contains('Priority support'));
      expect(source, contains('Start subscription'));
      expect(source, contains('Continue one-off pickup'));
      expect(source, contains('£11/month'));
      expect(source, isNot(contains('Standard prescription delivery')));
      expect(source, isNot(contains('Faster Circum Rider assignment')));
      expect(source, isNot(contains('Household pickup support')));
    });

    test('app Health+ checkout opens Stripe correctly on web', () {
      final source = File(
        'lib/app/health_plus/view/health_plus.dart',
      ).readAsStringSync();

      expect(source, contains("_openStripeCheckoutUrl(checkoutUrl)"));
      expect(source, contains("webOnlyWindowName: kIsWeb ? '_self' : null"));
      expect(source, contains("'subscriptionPlan': _plan"));
      expect(source, contains('_HealthCheckoutException'));
    });

    test(
      'canonical address payload preserves house number and flat metadata',
      () {
        final suggestion = Suggestion(
          placeId: 'place_29',
          description: 'Flat 4, 29 St Fillans Road, London, SE6 1DQ, UK',
          mainText: 'Flat 4, 29 St Fillans Road',
          subText: 'London SE6 1DQ',
          lat: 51.4401,
          lng: -0.0258,
          components: const {
            'addressLine1': '29 St Fillans Road',
            'buildingNumber': '29',
            'street': 'St Fillans Road',
            'apartment': 'Flat 4',
            'city': 'London',
            'postcode': 'SE6 1DQ',
            'country': 'United Kingdom',
          },
        );

        final normalized = AddressEngine.normalize(suggestion: suggestion);
        final cleanSuggestion = AddressEngine.cleanSuggestion(suggestion);

        expect(normalized['addressLine1'], '29 St Fillans Road');
        expect(normalized['buildingNumber'], '29');
        expect(normalized['street'], 'St Fillans Road');
        expect(normalized['apartment'], 'Flat 4');
        expect(cleanSuggestion.description, contains('29 St Fillans Road'));
        expect(
          cleanSuggestion.components['addressLine1'],
          '29 St Fillans Road',
        );
        expect(cleanSuggestion.components['buildingNumber'], '29');
        expect(cleanSuggestion.components['street'], 'St Fillans Road');
        expect(cleanSuggestion.components['apartment'], 'Flat 4');
      },
    );
  });
}
