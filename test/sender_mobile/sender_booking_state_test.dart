import 'dart:io';

import 'package:circum/app/send_package/bloc/send_package_bloc.dart';
import 'package:circum/app/send_package/models/delivery_data.m.dart';
import 'package:circum/app/send_package/models/canonical_iris_result.dart';
import 'package:circum/app/sender_mobile/sender_booking_state.dart';
import 'package:circum/app/sender_mobile/gift_mode_view.dart';
import 'package:circum/app/sender_mobile/sender_mobile_home.dart';
import 'package:circum/app/sender_mobile/sender_gifts_icon.dart';
import 'package:circum/app/sender_mobile/sender_tracking_screen.dart';
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

    test('delivery time defaults to deliver now and continues', () {
      const draft = SenderBookingDraft(step: SenderBookingStep.deliveryTime);

      expect(draft.deliveryTimingType, SenderDeliveryTimingType.now);
      expect(draft.deliveryTimeSummary, 'Deliver now');
      expect(draft.canContinue, isTrue);
      expect(draft.next().step, SenderBookingStep.parcel);
    });

    test('scheduled delivery requires valid future date and window', () {
      const incomplete = SenderBookingDraft(
        step: SenderBookingStep.deliveryTime,
        deliveryTimingType: SenderDeliveryTimingType.scheduled,
      );

      expect(incomplete.canContinue, isFalse);
      expect(
        isSenderScheduledDateValid('2026-07-06', now: DateTime(2026, 7, 6)),
        isTrue,
      );
      expect(
        isSenderScheduledDateValid('2026-07-05', now: DateTime(2026, 7, 6)),
        isFalse,
      );
      final scheduled = incomplete.copyWith(
        scheduledDate: '2026-07-07',
        scheduledWindow: 'Morning',
      );
      expect(scheduled.canContinue, isTrue);
      expect(scheduled.deliveryTimeSummary, 'Scheduled: 2026-07-07, Morning');
      expect(isSenderCustomWindowValid('14:00', '16:00'), isTrue);
      expect(isSenderCustomWindowValid('16:00', '14:00'), isFalse);
    });

    test('scheduled delivery exposes selectable calendar dates', () {
      final options = senderScheduleDateOptions(
        now: DateTime(2026, 7, 6),
        days: 3,
      );

      expect(options.map(senderScheduleDateValue), [
        '2026-07-06',
        '2026-07-07',
        '2026-07-08',
      ]);
      expect(
        senderScheduleDayLabel(options.first, now: DateTime(2026, 7, 6)),
        'Today',
      );
      expect(
        senderScheduleDayLabel(options[1], now: DateTime(2026, 7, 6)),
        'Tomorrow',
      );
      expect(senderScheduleMonthDayLabel(options[2]), '8 Jul');
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

    test('sender mobile Gifts entry opens GiftModeView shell only', () {
      final homeSource = File('lib/app/sender_mobile/sender_mobile_home.dart')
          .readAsStringSync();
      final giftSource =
          File('lib/app/sender_mobile/gift_mode_view.dart').readAsStringSync();
      final iconSource = File(
        'lib/app/sender_mobile/sender_gifts_icon.dart',
      ).readAsStringSync();

      expect(GiftModeView.routeName, '/sender-mobile/gifts');
      expect(homeSource, contains("import 'gift_mode_view.dart';"));
      expect(homeSource, contains("import 'sender_gifts_icon.dart';"));
      expect(homeSource, contains('onOpenGifts'));
      expect(homeSource, contains('const GiftModeView()'));
      expect(homeSource, contains('const SenderGiftsIcon()'));
      expect(homeSource, isNot(contains('_PremiumGiftIcon')));
      expect(homeSource, isNot(contains('_PremiumGiftPainter')));
      expect(giftSource, contains('class GiftModeView'));
      expect(giftSource, contains('Gift someone'));
      expect(giftSource, contains('Gift myself'));
      expect(giftSource, contains('Anonymous gift'));
      expect(giftSource, contains('Campaign'));
      expect(giftSource, contains('const SenderGiftsIcon(size: 52)'));
      expect(giftSource, isNot(contains('Icons.volunteer_activism_rounded')));
      expect(giftSource, isNot(contains('Icons.self_improvement_rounded')));
      expect(giftSource, isNot(contains('Icons.theater_comedy_rounded')));
      expect(giftSource, isNot(contains('Icons.campaign_rounded')));
      expect(giftSource, isNot(contains('parcel')));
      expect(giftSource, isNot(contains('Rothcross')));
      expect(giftSource, isNot(contains('0xFF3B82F6')));
      expect(const SenderGiftsIcon().size, 44);
      expect(iconSource, contains('class SenderGiftsIcon'));
      expect(iconSource, contains('0xFFA8EDEA'));
      expect(iconSource, contains('0xFFC9B8FF'));
      expect(iconSource, contains('0xFFFFD6E8'));
      expect(iconSource, contains('0xFFB8F0D8'));
      expect(iconSource, contains('0xFFD4C5FF'));
      expect(iconSource, contains('Rect.fromLTWH(3, 9, 18, 11)'));
      expect(iconSource, contains('strokeWidth = 1.7'));
      expect(iconSource, isNot(contains('0xFF3B82F6')));
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

    test(
      'sender mobile pre-auth implementation follows auth entry contract',
      () {
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
        expect(source, contains('previewAuthEnabled'));
        expect(source, contains('FirebaseAuth.instance'));
        expect(source, contains('createUserWithEmailAndPassword'));
        expect(source, contains('signInWithEmailAndPassword'));
        expect(source, contains('user.getIdToken(true)'));
        expect(
          source,
          contains(
            'Authentication handler is not enabled for this production surface.',
          ),
        );
      },
    );

    test(
      'sender mobile preview enables real Firebase auth only for preview',
      () {
        final previewSource = File(
          'lib/app/sender_mobile/sender_mobile_preview.dart',
        ).readAsStringSync();
        final homeSource = File(
          'lib/app/sender_mobile/sender_mobile_home.dart',
        ).readAsStringSync();

        expect(previewSource, contains('previewAuthEnabled: true'));
        expect(homeSource, contains('this.previewAuthEnabled = false'));
        expect(homeSource, isNot(contains('signInAnonymously')));
      },
    );

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

    test('Vanguard protocol does not replace selected delivery speed', () {
      final draft = const SenderBookingDraft(
        step: SenderBookingStep.options,
        selectedOption: 'Express',
      ).copyWith(vanguard: true);

      expect(draft.selectedOption, 'Express');
      expect(draft.vanguard, isTrue);
      expect(draft.vanguardProtocolEnabled, isTrue);
      expect(draft.vanguardStatus, 'pickup_verification_pending');
      expect(draft.addOnTotalGbp, senderVanguardAddOnPriceGbp);
      expect(draft.totalWithAddOns(8), 9.99);
    });

    test('removing Vanguard disables the protocol and fee', () {
      final draft = const SenderBookingDraft(
        vanguard: true,
      ).copyWith(vanguard: false);

      expect(draft.selectedOption, 'Standard');
      expect(draft.vanguardProtocolEnabled, isFalse);
      expect(draft.vanguardStatus, 'not_required');
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
      expect(senderVanguardProtocolLabel, 'Vanguard Delivery Protocol');
      expect(source, contains('Vanguard Protection Active'));
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

    test('canonical IRIS callable and backend auth guard stay in place', () {
      final blocSource = File(
        'lib/app/send_package/bloc/send_package_bloc.dart',
      ).readAsStringSync();
      final canvasSource = File(
        'lib/app/sender_mobile/sender_booking_canvas.dart',
      ).readAsStringSync();
      final backendSource = File('server/functions/iris.js').readAsStringSync();

      expect(blocSource, contains("httpsCallable('analyseIris')"));
      expect(blocSource, contains('analyseIris request payload'));
      expect(blocSource, contains('analyseIris response payload'));
      expect(blocSource, contains('FirebaseFunctionsException'));
      expect(blocSource, contains('code=\${error.code}'));
      expect(blocSource, contains('message=\${error.message}'));
      expect(blocSource, contains('details=\${error.details}'));
      expect(canvasSource, contains("label: 'Retry'"));
      expect(canvasSource, contains('RequestCanonicalIrisEstimate'));
      expect(backendSource, contains('if (!context.auth)'));
      expect(
        backendSource,
        contains('User must be authenticated to call Iris.'),
      );
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

    test('Roth payment split is user controlled at one to one value', () {
      expect(senderRothPoundValue, 1.0);
      final off = SenderPaymentSplit.calculate(
        totalDue: 58.50,
        rothEnabled: false,
        availableRothCredits: 42,
        fallbackMethod: SenderFallbackPaymentMethod.card,
      );
      expect(off.rothAppliedAmount, 0);
      expect(off.remainingAmount, 58.50);
      expect(off.ctaLabel, 'Pay £58.50 with Card');

      final partial = SenderPaymentSplit.calculate(
        totalDue: 58.50,
        rothEnabled: true,
        availableRothCredits: 42,
        fallbackMethod: SenderFallbackPaymentMethod.card,
      );
      expect(partial.rothAppliedCredits, 42);
      expect(partial.rothAppliedAmount, 42);
      expect(partial.remainingAmount, 16.50);
      expect(partial.ctaLabel, 'Pay £16.50 with Card + 42 Roth');

      final full = SenderPaymentSplit.calculate(
        totalDue: 20,
        rothEnabled: true,
        availableRothCredits: 42,
      );
      expect(full.fullyCoveredByRoth, isTrue);
      expect(full.requiresFallback, isFalse);
      expect(full.ctaLabel, 'Pay £20.00 with Roth');
    });

    test('delivery time and payment copy stay safe', () {
      final source = File(
        'lib/app/sender_mobile/sender_booking_canvas.dart',
      ).readAsStringSync();

      expect(source, contains('Delivery time'));
      expect(source, contains('Confirm delivery time'));
      expect(source, contains('Preferred date'));
      expect(source, contains('_ScheduleDateSelector'));
      expect(source, contains('Preferred collection window'));
      expect(source, contains('Payment'));
      expect(source, contains('Estimated total due today'));
      expect(source, contains('Apply Roth to this payment'));
      expect(
        source,
        contains('Roth balance could not be loaded from the backend'),
      );
      expect(source, contains("Payment couldn't be started"));
      expect(source, isNot(contains('42 Roth available')));
      expect(source, isNot(contains('senderMobilePreviewRothBalanceCredits')));
      expect(source, isNot(contains('Step X')));
      expect(source, isNot(contains('Step 1')));
      expect(source, isNot(contains('1/12')));
      expect(source, isNot(contains('Final total')));
      expect(source, isNot(contains('guaranteed delivery')));
    });

    test('sender tracking exposes every required state copy', () {
      for (final state in SenderTrackingState.values) {
        final content = senderTrackingContentFor(state);
        expect(content.title, isNotEmpty);
        expect(content.body, isNotEmpty);
      }

      expect(
        senderTrackingContentFor(SenderTrackingState.riderAssigned).title,
        'Your rider is on the way',
      );
      expect(
        senderTrackingContentFor(SenderTrackingState.riderArrivingAtDropoff)
            .showReceiverPin,
        isTrue,
      );
      expect(
        senderTrackingContentFor(SenderTrackingState.issue).title,
        "There's an issue with this delivery",
      );
    });

    test('sender tracking maps real backend statuses to all production states',
        () {
      final cases = {
        'requested': SenderTrackingState.findingRider,
        'accepted': SenderTrackingState.riderAssigned,
        'navigating_to_pickup': SenderTrackingState.riderEnRouteToPickup,
        'arrived_at_pickup': SenderTrackingState.riderArrivedAtPickup,
        'pickup_verified': SenderTrackingState.pickupComplete,
        'collected': SenderTrackingState.pickupComplete,
        'navigating_to_dropoff': SenderTrackingState.inTransit,
        'arrived_at_dropoff': SenderTrackingState.riderArrivingAtDropoff,
        'pin_required': SenderTrackingState.riderArrivingAtDropoff,
        'delivered': SenderTrackingState.delivered,
        'completed': SenderTrackingState.delivered,
        'cancelled': SenderTrackingState.cancelled,
        'issue_reported': SenderTrackingState.issue,
        'error': SenderTrackingState.error,
      };

      for (final entry in cases.entries) {
        expect(senderTrackingStateForBackendStatus(entry.key), entry.value);
      }
      expect(senderTrackingStateForBackendStatus(null), isNull);
    });

    test('sender tracking engine prefers Firestore backend status', () {
      expect(
        senderTrackingStateForEngine(
          SendPackageState(
            deliveryStatus: DeliveryStatus.deliveryOnGoing,
            deliveryRequestStatus: 'arrived_at_dropoff',
          ),
        ),
        SenderTrackingState.riderArrivingAtDropoff,
      );
      expect(
        senderTrackingStateForEngine(
          SendPackageState(
            deliveryStatus: DeliveryStatus.deliveryConfirmed,
            deliveryRequestStatus: 'cancelled',
          ),
        ),
        SenderTrackingState.cancelled,
      );
    });

    test('sender tracking state gallery exposes all 13 states', () {
      final source = File(
        'lib/app/sender_mobile/sender_tracking_state_gallery.dart',
      ).readAsStringSync();

      for (final state in SenderTrackingState.values) {
        expect(source, contains('SenderTrackingState.${state.name}'));
      }
    });

    test('finding rider remains anonymous and calm', () {
      final content =
          senderTrackingContentFor(SenderTrackingState.findingRider);

      expect(content.showPickupPin, isTrue);
      expect(content.showAnonymousRiders, isTrue);
      expect(content.showRiderCard, isFalse);
      expect(content.showCollectionPin, isFalse);
      expect(content.showReceiverPin, isFalse);
    });

    test('both PINs appear together after rider assignment', () {
      const activeStates = [
        SenderTrackingState.riderAssigned,
        SenderTrackingState.riderEnRouteToPickup,
        SenderTrackingState.riderArrivedAtPickup,
        SenderTrackingState.pickupComplete,
        SenderTrackingState.inTransit,
        SenderTrackingState.riderArrivingAtDropoff,
        SenderTrackingState.issue,
      ];

      final pinStates = SenderTrackingState.values.where((state) {
        final content = senderTrackingContentFor(state);
        return content.showCollectionPin && content.showReceiverPin;
      }).toList();

      expect(pinStates, activeStates);
      for (final state in activeStates) {
        final content = senderTrackingContentFor(state);
        expect(content.showCollectionPin, isTrue, reason: '$state');
        expect(content.showReceiverPin, isTrue, reason: '$state');
      }
    });

    test('tracking PIN status labels follow active delivery state', () {
      expect(
        senderCollectionPinStatusFor(SenderTrackingState.riderAssigned),
        'Ready for pickup',
      );
      expect(
        senderCollectionPinStatusFor(SenderTrackingState.riderArrivedAtPickup),
        'Ready for pickup',
      );
      expect(
        senderCollectionPinStatusFor(SenderTrackingState.pickupComplete),
        '✓ Pickup verified',
      );
      expect(
        senderCollectionPinStatusFor(
          SenderTrackingState.riderAssigned,
          verified: true,
        ),
        '✓ Pickup verified',
      );
      expect(
        senderCollectionPinStatusFor(SenderTrackingState.inTransit),
        '✓ Pickup verified',
      );
      expect(
        senderReceiverPinStatusFor(SenderTrackingState.riderAssigned),
        'Ready for delivery',
      );
      expect(
        senderReceiverPinStatusFor(
          SenderTrackingState.riderArrivingAtDropoff,
          verified: true,
        ),
        '✓ Delivery verified',
      );
    });

    test('delivered state supports optional backend verification beat', () {
      final normal = senderTrackingContentFor(SenderTrackingState.delivered);
      final verified = senderTrackingContentFor(
        SenderTrackingState.delivered,
        deliveryVerified: true,
      );

      expect(normal.title, 'Delivered');
      expect(verified.title, 'Delivery verified');
      expect(
        verified.body,
        'Vanguard confirmed this delivery is complete.',
      );
    });

    test('delivered tracking state uses green success treatment', () {
      final source = File(
        'lib/app/sender_mobile/sender_tracking_screen.dart',
      ).readAsStringSync();

      expect(
        source,
        contains('completed: state == SenderTrackingState.delivered'),
      );
      expect(source, contains('success: delivered'));
      expect(source, contains('const Color(0xFF34D399)'));
      expect(source, contains('completeColor.withValues'));
    });

    test('delivered tracking state has calm completion sequence', () {
      final source = File(
        'lib/app/sender_mobile/sender_tracking_screen.dart',
      ).readAsStringSync();

      expect(source, contains('_DeliveredConfirmationOverlay'));
      expect(source, contains('✓ Delivery completed'));
      expect(source, contains('_DeliveredChipSequence'));
      expect(source, contains('IRIS parcel confirmed'));
      expect(source, contains('Vanguard completed'));
      expect(source, contains('Tween(begin: completed ? .74 : 1, end: 1)'));
      expect(source, contains('Duration(milliseconds: 400)'));
      expect(source, contains('Duration(milliseconds: 500)'));
      expect(source, contains('Curves.easeOut'));
      expect(source, contains('settled: delivered'));
      expect(
        source,
        contains('state != SenderTrackingState.delivered && content.showIris'),
      );
      expect(
        source,
        contains(
          'state != SenderTrackingState.delivered && content.showVanguard',
        ),
      );
    });

    test('PINs are removed for inactive terminal states', () {
      const inactiveStates = [
        SenderTrackingState.noActiveDelivery,
        SenderTrackingState.loading,
        SenderTrackingState.findingRider,
        SenderTrackingState.delivered,
        SenderTrackingState.cancelled,
        SenderTrackingState.error,
      ];

      for (final state in inactiveStates) {
        final content = senderTrackingContentFor(state);
        expect(content.showCollectionPin, isFalse, reason: '$state');
        expect(content.showReceiverPin, isFalse, reason: '$state');
      }
    });

    test('sender tracking PIN cards stay masked by default', () {
      final source = File(
        'lib/app/sender_mobile/sender_tracking_screen.dart',
      ).readAsStringSync();

      expect(source, contains("label: 'Collection PIN'"));
      expect(source, contains("label: 'Receiver PIN'"));
      expect(source, contains('Give this to your rider at pickup.'));
      expect(source, contains('Give this to the receiver at delivery.'));
      expect(source, contains('const Color(0xFF3B82F6)'));
      expect(source, contains('const Color(0xFF34D399)'));
      expect(source, contains('Icons.inventory_2_outlined'));
      expect(source, contains('Icons.verified_outlined'));
      expect(source, contains('AnimatedSwitcher'));
      expect(source, contains('Duration(milliseconds: 250)'));
      expect(source, contains("'••••••'"));
      expect(source, contains('onTap: _reveal'));
      expect(source, contains('onLongPress: _reveal'));
      expect(source, contains('Timer(const Duration(seconds: 4)'));
      expect(source, isNot(contains('price')));
      expect(source, isNot(contains('eye')));
      expect(source, isNot(contains('Delivery PIN sent to receiver')));
    });

    test('sender tracking maps assigned vehicles to live map marker kinds', () {
      expect(senderVehicleMarkerKindFor('Bike'), 'bike');
      expect(senderVehicleMarkerKindFor('Scooter'), 'bike');
      expect(senderVehicleMarkerKindFor('Car'), 'car');
      expect(senderVehicleMarkerKindFor('Small van'), 'van');
      expect(senderVehicleMarkerKindFor(''), 'unknown');
      expect(senderVehicleMarkerKindFor(null), 'unknown');
    });

    test('sender tracking stale location labels follow live update age', () {
      final now = DateTime(2026, 7, 7, 12);
      expect(
        senderLiveLocationStaleLabel(
          now.subtract(const Duration(seconds: 44)),
          now: now,
        ),
        isNull,
      );
      expect(
        senderLiveLocationStaleLabel(
          now.subtract(const Duration(seconds: 45)),
          now: now,
        ),
        'Location updating…',
      );
      expect(
        senderLiveLocationStaleLabel(
          now.subtract(const Duration(minutes: 2, seconds: 5)),
          now: now,
        ),
        'Last seen 2 min ago',
      );
    });

    test('sender tracking renders live-location map affordances', () {
      final source = File(
        'lib/app/sender_mobile/sender_tracking_screen.dart',
      ).readAsStringSync();

      expect(source, contains('_VehicleMarker'));
      expect(source, contains('_VehicleIconPainter'));
      expect(source, contains('_StaleLocationPill'));
      expect(source, contains('_RecenterButton'));
      expect(source, contains('Recenter'));
      expect(source, contains('Location updating…'));
      expect(source, contains('Last seen'));
      expect(source, contains('duration: const Duration(milliseconds: 900)'));
    });

    test('sender tracking reads low-cost active delivery live location', () {
      final blocSource = File(
        'lib/app/send_package/bloc/send_package_bloc.dart',
      ).readAsStringSync();
      final functionSource = File(
        'server/functions/delivery-tracking.js',
      ).readAsStringSync();

      expect(blocSource, contains("collection('activeDeliveries')"));
      expect(blocSource, contains('riderLiveLocation'));
      expect(functionSource, contains('activeDeliveries'));
      expect(functionSource, contains('riderLiveLocation'));
      expect(functionSource, isNot(contains('locationHistory')));
    });

    test('delivery data carries existing backend receiver PIN field', () {
      final data = DeliveryData.fromJson({
        'courierName': 'Maya Stone',
        'phoneNumber': '+447000000000',
        'typeOfVehicle': 'Bike',
        'estimatedDeliveryTime': '7 min',
        'plateNumber': '',
        'code': '427158',
        'deliveryPin': '835246',
        'rating': '4.9',
        'riderId': 'rider_1',
        'photoURL': 'null',
      });

      expect(data.code, '427158');
      expect(data.deliveryPin, '835246');
    });

    test('delivery data reads nested Vanguard PIN fields from backend', () {
      final data = DeliveryData.fromJson({
        'riderName': 'Maya Stone',
        'driverVehicle': 'Bike',
        'driverPlateNumber': '',
        'rating': '4.9',
        'riderId': 'rider_1',
        'photoURL': 'null',
        'vanguardProtection': {
          'collectionPin': '111222',
          'deliveryPin': '333444',
        },
      });

      expect(data.code, '111222');
      expect(data.deliveryPin, '333444');
    });
  });
}
