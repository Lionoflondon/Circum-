import 'dart:io';

import 'package:circum/app/send_package/models/canonical_iris_result.dart';
import 'package:circum/app/sender_mobile/sender_booking_state.dart';
import 'package:circum/app/sender_mobile/sender_mobile_home.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Sender mobile booking state', () {
    test('uses the locked Sender Engine step order', () {
      expect(SenderBookingStep.values, const [
        SenderBookingStep.pickup,
        SenderBookingStep.dropoff,
        SenderBookingStep.recipient,
        SenderBookingStep.deliveryTime,
        SenderBookingStep.parcel,
        SenderBookingStep.iris,
        SenderBookingStep.options,
        SenderBookingStep.review,
        SenderBookingStep.payment,
        SenderBookingStep.findingRider,
        SenderBookingStep.liveTracking,
      ]);
    });

    test('back and forward retain entered booking data', () {
      final draft = const SenderBookingDraft()
          .copyWith(pickupAddress: 'Flat 2, 14 Harley Street')
          .next()
          .copyWith(dropoffAddress: 'Chelsea')
          .next()
          .back();

      expect(draft.step, SenderBookingStep.dropoff);
      expect(draft.pickupAddress, 'Flat 2, 14 Harley Street');
      expect(draft.dropoffAddress, 'Chelsea');
    });

    test('recipient step requires name and phone', () {
      final draft = const SenderBookingDraft(
        step: SenderBookingStep.recipient,
        receiverName: 'Ada',
      );

      expect(draft.canContinue, isFalse);
      expect(
        draft.copyWith(receiverPhone: '+447891362527').canContinue,
        isTrue,
      );
      expect(
        const SenderBookingDraft(
          step: SenderBookingStep.recipient,
          receiverName: 'Ada',
          receiverPhone: '+447891362527',
          deliveryNotes: '',
        ).canContinue,
        isTrue,
      );
    });

    test('recipient details persist into booking state', () {
      final draft = const SenderBookingDraft(
        step: SenderBookingStep.recipient,
        receiverName: 'Ada',
        receiverPhone: '+447891362527',
        deliveryNotes: 'Leave at reception',
      );

      expect(draft.receiverName, 'Ada');
      expect(draft.receiverPhone, '+447891362527');
      expect(draft.deliveryNotes, 'Leave at reception');
    });

    test('schedule is not treated as live booking support', () {
      const draft = SenderBookingDraft(
        step: SenderBookingStep.deliveryTime,
        deliveryTime: 'Schedule',
      );

      expect(draft.canContinue, isFalse);
    });

    test('IRIS confidence exposes labels only', () {
      expect(mapConfidenceLabel(.91), 'High');
      expect(mapConfidenceLabel(.70), 'Medium');
      expect(mapConfidenceLabel(.40), 'Low');
    });

    test(
      'canonical IRIS response renders item quantity and backend weight',
      () {
        final result = CanonicalIrisResult.fromCallable(
          {
            'recommendation': {
              'detectedItem': 'Apple MacBook',
              'estimatedWeightKg': 12.4,
              'confidencePercent': 91,
            },
            'internal': {
              'riderMatching': {'vehicleRequired': 'Car'},
              'learningMatchedExamples': 4,
            },
          },
          fallbackItemName: 'Apple MacBook',
          fallbackQuantity: 10,
        );

        expect(result.itemAndQuantity, 'Apple MacBook ×10');
        expect(result.totalWeightLabel, '12.40kg');
        expect(result.recommendedVehicle, 'Car');
        expect(result.confidenceLabel, 'High');
        expect(result.similarVerifiedDeliveries, 4);
      },
    );

    test(
      'canonical IRIS fallback quantity displays one without mutating backend',
      () {
        final result = CanonicalIrisResult.fromCallable({
          'recommendation': {
            'detectedItem': 'iPhone 13',
            'estimatedWeightKg': .6,
          },
        }, fallbackItemName: 'iPhone 13');

        expect(result.quantity, 1);
        expect(result.itemAndQuantity, 'iPhone 13 ×1');
      },
    );

    test('sender quantity parser does not calculate weight', () {
      expect(senderQuantityFromItemName('10 MacBooks'), 10);
      expect(senderQuantityFromItemName('iPhone 13 ×3'), 3);
      expect(senderQuantityFromItemName('Wedding dress'), 1);
    });

    test('Vanguard is not treated as a delivery speed', () {
      expect(senderDeliverySpeeds, const ['Economy', 'Standard', 'Express']);
      expect(isSenderDeliverySpeed('Standard'), isTrue);
      expect(isSenderDeliverySpeed('Vanguard'), isFalse);
    });

    test('dashboard service hub excludes Vanguard', () {
      expect(senderMobileDashboardServiceNames, const [
        'Health+',
        'Business',
        'Gifts',
      ]);
      expect(senderMobileDashboardServiceNames, isNot(contains('Vanguard')));
    });

    test('dashboard copy uses approved service hub language', () {
      expect(
        senderMobileHeroSubtitle,
        'From collection to delivery, every step protected by IRIS.',
      );
      expect(
        senderMobileDashboardServiceSubtitles['Health+'],
        'Trusted medical deliveries',
      );
      expect(
        senderMobileDashboardServiceSubtitles['Business'],
        'Business deliveries',
      );
      expect(
        senderMobileDashboardServiceSubtitles['Gifts'],
        'Thoughtful gfts, delivered.',
      );
      expect(senderMobileRecentOrderTitles, const [
        'Passport',
        'Prescription collection',
      ]);
    });

    test('sender mobile pre-auth landing and auth copy are locked', () {
      expect(senderMobilePreAuthHeadline, 'Deliver anything with confidence.');
      expect(
        senderMobilePreAuthSubtitle,
        'Fast, trusted delivery powered by IRIS and verified riders.',
      );
      expect(senderMobileAuthSignInHeadline, 'Welcome back');
      expect(senderMobileAuthCreateHeadline, 'Join Circum');
      expect(
        senderMobileAuthFinePrint,
        "By continuing, you agree to Circum's Terms and Privacy Policy.",
      );
    });

    test('sender mobile pre-auth implementation follows auth entry contract', () {
      final source = File(
        'lib/app/sender_mobile/sender_mobile_home.dart',
      ).readAsStringSync();

      expect(
        source,
        contains(
          "Image.asset(\n            'assets/images/circum_wordmark.png'",
        ),
      );
      expect(source, contains('Create account'));
      expect(source, contains('Sign in'));
      expect(source, contains('_SenderAuthMode.signIn'));
      expect(source, contains('_SenderAuthMode.createAccount'));
      expect(source, contains('EMAIL OR PHONE'));
      expect(source, contains('PASSWORD'));
      expect(source, contains('Continue with Apple'));
      expect(source, contains('Continue with Google'));
      expect(source, contains('Terms'));
      expect(source, contains('Privacy Policy'));
      expect(source, contains('After you join'));
      expect(source, contains('OR CONTINUE WITH'));
      expect(source, contains('Trusted Riders'));
      expect(source, contains('if (_isSignIn)'));
      expect(
        source,
        contains(
          '// TODO(sender-mobile-auth): Wire to the existing auth/onboarding handler.',
        ),
      );
    });

    test('sender mobile pre-auth visual refinements are present', () {
      final source = File(
        'lib/app/sender_mobile/sender_mobile_home.dart',
      ).readAsStringSync();

      expect(source, contains('height: 26'));
      expect(source, contains('mainAxisExtent: 88'));
      expect(source, contains('Curated gifts delivered with care.'));
      expect(source, contains('Trusted prescription and care deliveries.'));
      expect(source, contains('Delivery tools for growing teams.'));
      expect(
        source,
        contains(
          'Trusted by people sending everything from forgotten passports to meaningful gifts.',
        ),
      );
      expect(source, contains('_AfterJoinPill(accent: accent)'));
    });

    test('Vanguard add-on does not replace selected delivery speed', () {
      final draft = const SenderBookingDraft(
        step: SenderBookingStep.options,
        selectedOption: 'Express',
      ).copyWith(vanguard: true);

      expect(draft.selectedOption, 'Express');
      expect(draft.vanguard, isTrue);
      expect(draft.addOnTotalGbp, senderVanguardAddOnPriceGbp);
      expect(draft.totalWithAddOns(8), 9.99);
    });

    test('removing Vanguard removes only the add-on price', () {
      final draft = const SenderBookingDraft(
        vanguard: true,
      ).copyWith(vanguard: false);

      expect(draft.selectedOption, 'Standard');
      expect(draft.addOnTotalGbp, 0);
      expect(draft.totalWithAddOns(8), 8);
    });

    test('sender booking copy uses recipient and canonical IRIS labels', () {
      final source = File(
        'lib/app/sender_mobile/sender_booking_canvas.dart',
      ).readAsStringSync();

      expect(source, contains('Confirm pickup'));
      expect(source, contains('Confirm drop-off'));
      expect(source, contains('Recipient name'));
      expect(source, contains('Recipient phone'));
      expect(source, contains('Delivery instructions (optional)'));
      expect(source, contains('Confirm recipient'));
      expect(
        source,
        contains('Used only if the rider needs to contact the recipient.'),
      );
      expect(source, isNot(contains('Receiver name')));
      expect(source, isNot(contains('Receiver phone')));
      expect(source, isNot(contains('Delivery notes')));
      expect(source, contains('Item & quantity'));
      expect(source, contains('Estimated total weight'));
      expect(source, contains('Recommended vehicle'));
      expect(source, contains('Why IRIS estimated this'));
      expect(source, isNot(contains('Classification')));
    });

    test(
      'sender mobile address lookup uses canonical free address callable',
      () {
        final source = File(
          'lib/app/send_package/repo/place_api.dart',
        ).readAsStringSync();

        expect(source, contains('searchFreeUkAddresses'));
        expect(source, isNot(contains('maps.googleapis.com/maps/api/place')));
        expect(source, contains('lat'));
        expect(source, contains('lng'));
        expect(source, contains('components'));
      },
    );

    test('payment cannot fake success', () {
      const unpaid = SenderBookingDraft(
        step: SenderBookingStep.payment,
        paymentStatus: SenderPaymentStatus.notReady,
      );
      const paidButNotConfirmed = SenderBookingDraft(
        step: SenderBookingStep.payment,
        paymentStatus: SenderPaymentStatus.paid,
      );

      expect(unpaid.canContinue, isFalse);
      expect(unpaid.next().step, SenderBookingStep.payment);
      expect(paidButNotConfirmed.exposesPaymentSuccess, isFalse);
    });
  });
}
