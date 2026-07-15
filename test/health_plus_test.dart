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

    test('plan quotes come from Health+ pricing definitions', () {
      final planQuotes = HealthPlusPricing.planQuotes();

      expect(
        planQuotes.map((quote) => quote.plan.label),
        HealthPlusPricing.availablePlans.map((plan) => plan.label),
      );
      for (final planQuote in planQuotes) {
        final directQuote = HealthPlusPricing.calculate(
          subscriptionPlan: planQuote.plan.value,
        );
        expect(planQuote.breakdown.total, directQuote.total);
      }
    });

    test('future pricing plan can quote without UI changes', () {
      const futurePlans = [
        ...HealthPlusPricing.availablePlans,
        HealthPlusPlanDefinition(
          value: 'corporate',
          label: 'Corporate',
          description: 'Configured plan from Health+ pricing',
          monthlyPrice: 75,
          priorityFee: 4.5,
        ),
      ];

      final planQuotes = HealthPlusPricing.planQuotes(plans: futurePlans);

      expect(
          planQuotes.map((quote) => quote.plan.value), contains('corporate'));
      expect(
        planQuotes.last.displayPrice,
        '£75 / month',
      );
    });

    test('mobile and web share the canonical Health+ website plans', () {
      expect(
        HealthPlusPricing.availablePlans.map((plan) => plan.value).toList(),
        ['core', 'priority', 'family', 'custom'],
      );
      expect(
        HealthPlusPricing.availablePlans.map((plan) => plan.label).toList(),
        [
          'Health+ Core',
          'Health+ Priority',
          'Health+ Family',
          'Health+ Custom'
        ],
      );
      expect(
        HealthPlusPricing.availablePlans
            .map((plan) => plan.monthlyPriceLabel)
            .toList(),
        ['£15 / month', '£25 / month', '£40 / month', 'From £60 / month'],
      );
      final web = File('lib/web_sender_app.dart').readAsStringSync();
      expect(web, contains('HealthPlusPricing.availablePlans'));
      expect(web, isNot(contains("title: 'Health+ Core'")));
    });

    test('Health+ view renders plan quotes without hardcoded plan pricing', () {
      final source =
          File('lib/app/health_plus/view/health_plus.dart').readAsStringSync();

      expect(source, contains('HealthPlusPricing.planQuotes'));
      expect(source, contains('HealthPlusPricing.formatGbp(total)'));
      expect(source, isNot(contains('static const _plans')));
      expect(source, isNot(contains('_HealthPlanOption')));
      expect(source, isNot(contains("subscriptionPlan: 'basic'")));
      expect(source, isNot(contains("'+£")));
      expect(source, isNot(contains("'Included'")));
      expect(source, isNot(contains('toStringAsFixed(2)')));
    });

    test('Health+ checkout consumes shared Sender finance surfaces', () {
      final source =
          File('lib/app/health_plus/view/health_plus.dart').readAsStringSync();

      expect(source, contains('SenderPaymentProfile'));
      expect(source, contains('SenderWalletData'));
      expect(source, contains('FirebaseSenderWalletRepository'));
      expect(source, contains('senderOrderedPaymentOptions'));
      expect(source, contains('SenderWalletView'));
      expect(source, contains('Pay With'));
      expect(source, contains('SenderPaymentProfileOptionType.applePay'));
      expect(source, contains('SenderPaymentProfileOptionType.googlePay'));
      expect(source, contains('Apply Roth'));
      expect(source, contains('Manage Payment Methods'));
      expect(
          source, contains("'paymentProfileSource': 'sender_payment_profile'"));
      expect(source, contains("'applyRoth': _applyRoth"));
      expect(source, isNot(contains('Health payment methods')));
      expect(source, isNot(contains('Save payment method for Health+')));
    });

    test('Health+ persists favourites and schedule preferences', () {
      final source =
          File('lib/app/health_plus/view/health_plus.dart').readAsStringSync();

      expect(source, contains('recentPharmacies'));
      expect(source, contains('preferredDeliveryAddresses'));
      expect(source, contains('preferredSchedule'));
      expect(source, contains('Recent Pharmacy'));
      expect(source, contains('Use Again'));
      expect(source, contains('Home'));
      expect(source, contains('Work'));
      expect(source, contains('Parents'));
      expect(source, contains('Care Home'));
      expect(source, contains('Preferred Pickup Day'));
      expect(source, contains('Preferred Pickup Time'));
    });

    test('Health+ confirmation and timeline use final customer copy', () {
      final source =
          File('lib/app/health_plus/view/health_plus.dart').readAsStringSync();

      expect(source, contains('Your Health+ pickup has been scheduled.'));
      expect(
        source,
        contains(
          "We'll collect your prescription and keep you updated every step of the way.",
        ),
      );
      expect(source, contains('💊 Prescription Ready'));
      expect(source, contains('🚴 Rider Assigned'));
      expect(source, contains('📦 Collected'));
      expect(source, contains('🚚 On The Way'));
      expect(source, contains('✅ Delivered'));
      expect(source, contains('PickupStatusValue.fromValue'));
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
      expect(source, contains("'subscriptionPlan': _subscriptionPlan"));
      expect(source, contains('Admin status overrides belong in Admin.'));
      expect(source, isNot(contains('class _AdminPanel')));
      expect(source, isNot(contains('Admin operations')));
    });

    test('Health+ carries verified Business context into canonical records',
        () {
      final source =
          File('lib/app/health_plus/view/health_plus.dart').readAsStringSync();
      final backend =
          File('server/functions/health-plus.js').readAsStringSync();

      expect(source, contains('BusinessJourneyScope.maybeOf(context)'));
      expect(source, contains('...businessFields'));
      expect(backend, contains('requireHealthBusinessAccess'));
      expect(backend, contains('billingSource'));
    });

    test('canonical Sender dashboard opens the Health+ experience', () {
      final source = File('lib/app/sender_mobile/sender_mobile_home.dart')
          .readAsStringSync();

      expect(source, contains('onOpenHealth:'));
      expect(source, contains('const HealthPlusView()'));
    });
  });
}
