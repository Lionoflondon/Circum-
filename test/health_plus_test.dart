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
          quote.total, greaterThan(HealthPlusPricing.minimumStartingPriceGbp));
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

    test('app booking plans match the public Health+ plan copy', () {
      final source =
          File('lib/app/health_plus/view/health_plus.dart').readAsStringSync();

      expect(source, contains('Health+ Basic'));
      expect(source,
          contains('2 Health+ prescription pickups every calendar month'));
      expect(source, contains('Medicine delivery reminders'));
      expect(source, contains('Secure sealed-package handover'));
      expect(source, contains('Health+ Priority'));
      expect(source, contains('£25/month'));
      expect(source,
          contains('4 Health+ prescription pickups every calendar month'));
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
      final source =
          File('lib/app/health_plus/view/health_plus.dart').readAsStringSync();

      expect(source, contains("_openStripeCheckoutUrl(checkoutUrl)"));
      expect(source, contains("webOnlyWindowName: kIsWeb ? '_self' : null"));
      expect(source, contains("'subscriptionPlan': _plan"));
      expect(source, contains('_HealthCheckoutException'));
    });

    test('mobile Health+ serializes the shared canonical address contract', () {
      final suggestion = Suggestion(
        placeId: 'place_1',
        description: 'The Shard, London SE1 9SG',
        mainText: 'The Shard',
        subText: 'London SE1 9SG',
        lat: 51.5045,
        lng: -0.0865,
        components: const {
          'addressLine1': '32 London Bridge Street',
          'city': 'London',
          'postcode': 'SE1 9SG',
          'country': 'United Kingdom',
        },
      );
      final payload = AddressEngine.canonicalAddressPayload(suggestion);

      expect(payload['displayAddress'], isNotEmpty);
      expect(payload['postcode'], 'SE1 9SG');
      expect(payload['lat'], 51.5045);
      expect(payload['lng'], -0.0865);
      expect(payload['placeId'], 'place_1');
      expect(payload['validationStatus'], 'verified');
      expect(payload['provider'], 'google_places');
    });

    test('Health+ booking resolves typed addresses before canonical payloads',
        () {
      final source =
          File('lib/app/health_plus/view/health_plus.dart').readAsStringSync();

      expect(source, contains("'pharmacyAddressCanonical'"));
      expect(source, contains("'deliveryAddressCanonical'"));
      expect(source, contains('_resolveHealthAddressIfNeeded'));
      expect(source, contains('search.resolveTypedAddress(current)'));
      expect(source, contains('AddressEngine.hasRequiredFields'));
      expect(source, isNot(contains("'pharmacyPosition'")));
      expect(source, isNot(contains("'deliveryPosition'")));
    });

    test('Gift address selection and typed confirmation resolve canonically',
        () {
      final source = File(
        'lib/app/sender_mobile/gift_delivery_view.dart',
      ).readAsStringSync();

      expect(source, contains('resolveSuggestion'));
      expect(source, contains('resolveTypedAddress(address, \'en\')'));
      expect(source, contains('senderGiftAddressResolveCallableName'));
      expect(source, contains('_selectedAddressSuggestion = resolved'));
      expect(source, contains('That address could not be resolved'));
      expect(
        source,
        isNot(contains('Select a verified address, or enter a full address')),
      );
    });
  });
}
