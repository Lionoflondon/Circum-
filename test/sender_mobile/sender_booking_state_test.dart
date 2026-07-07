import 'dart:io';

import 'package:circum/app/send_package/bloc/send_package_bloc.dart';
import 'package:circum/app/send_package/models/delivery_data.m.dart';
import 'package:circum/app/send_package/models/canonical_iris_result.dart';
import 'package:circum/app/send_package/models/suggestions.m.dart';
import 'package:circum/app/gifts/gifts_social_policy.dart';
import 'package:circum/app/sender_mobile/sender_booking_state.dart';
import 'package:circum/app/sender_mobile/gift_delivery_view.dart';
import 'package:circum/app/sender_mobile/gift_iris_view.dart';
import 'package:circum/app/sender_mobile/gift_journey_draft.dart';
import 'package:circum/app/sender_mobile/gift_message_view.dart';
import 'package:circum/app/sender_mobile/gift_mode_view.dart';
import 'package:circum/app/sender_mobile/gift_payment_view.dart';
import 'package:circum/app/sender_mobile/gift_pre_payment_view.dart';
import 'package:circum/app/sender_mobile/gift_review_view.dart';
import 'package:circum/app/sender_mobile/gift_relationship_view.dart';
import 'package:circum/app/sender_mobile/gift_safety_view.dart';
import 'package:circum/app/sender_mobile/gift_status_view.dart';
import 'package:circum/app/sender_mobile/gift_story_view.dart';
import 'package:circum/app/sender_mobile/gift_themes_view.dart';
import 'package:circum/app/sender_mobile/gift_voice_note_view.dart';
import 'package:circum/app/sender_mobile/sender_mobile_home.dart';
import 'package:circum/app/sender_mobile/sender_gifts_icon.dart';
import 'package:circum/app/sender_mobile/sender_tracking_screen.dart';
import 'package:flutter/material.dart';
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
      final campaignSource =
          File('lib/app/sender_mobile/gift_campaign_view.dart')
              .readAsStringSync();
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
      expect(giftSource, contains('GiftCampaignView'));
      expect(campaignSource, contains('Bring London Closer'));
      expect(campaignSource, contains('giftCampaignParticipants'));
      expect(campaignSource, contains('giftCampaignMatches'));
      expect(campaignSource, contains('GiftsSocialPolicy.scoreMatch'));
      expect(campaignSource, contains('GiftsSocialPolicy.canRevealSender'));
      expect(campaignSource, contains('GiftsSocialPolicy.canPostPublicly'));
      expect(campaignSource, contains('GiftsSocialPolicy.canApproveBrandTags'));
      expect(campaignSource, contains('GiftsSocialPolicy.recipientSafeView'));
      expect(campaignSource, isNot(contains('GiftDeliveryView')));
      expect(giftSource, contains('SenderGiftsIconKind.gift'));
      expect(giftSource, contains('SenderGiftsIconKind.self'));
      expect(giftSource, contains('SenderGiftsIconKind.mask'));
      expect(giftSource, contains('SenderGiftsIconKind.people'));
      expect(giftSource, isNot(contains('Icons.volunteer_activism_rounded')));
      expect(giftSource, isNot(contains('Icons.self_improvement_rounded')));
      expect(giftSource, isNot(contains('Icons.theater_comedy_rounded')));
      expect(giftSource, isNot(contains('Icons.campaign_rounded')));
      expect(giftSource, isNot(contains('parcel')));
      expect(giftSource, isNot(contains('Rothcross')));
      expect(giftSource, isNot(contains('0xFF3B82F6')));
      expect(const SenderGiftsIcon().size, 44);
      expect(const SenderGiftsIcon().kind, SenderGiftsIconKind.gift);
      expect(iconSource, contains('class SenderGiftsIcon'));
      expect(iconSource, contains('SvgPicture.string'));
      expect(iconSource, contains('0xFFA8EDEA'));
      expect(iconSource, contains('0xFFC9B8FF'));
      expect(iconSource, contains('0xFFFFD6E8'));
      expect(iconSource, contains('0xFFB8F0D8'));
      expect(iconSource, contains('0xFFD4C5FF'));
      expect(
        iconSource,
        contains(
          '<rect x="3" y="9" width="18" height="11" rx="1.5" stroke="currentColor" stroke-width="1.7"/>',
        ),
      );
      expect(
        iconSource,
        contains(
          '<path d="M3 9h18M12 9v11M12 9c-2-4-7-4-7-1s3 1 7 1zm0 0c2-4 7-4 7-1s-3 1-7 1z" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round"/>',
        ),
      );
      expect(
        iconSource,
        contains(
          '<circle cx="12" cy="8" r="4" stroke="currentColor" stroke-width="1.7"/>',
        ),
      );
      expect(
        iconSource,
        contains(
          '<path d="M4 10c0-3 3.5-6 8-6s8 3 8 6-2 8-8 8-8-5-8-8z" stroke="currentColor" stroke-width="1.7"/>',
        ),
      );
      expect(
        iconSource,
        contains(
          '<path d="M2 20c0-3.5 3-5.5 6-5.5s6 2 6 5.5M14 20c0-2.6 2-4.5 5-4.5s5 1.9 5 4.5" stroke="currentColor" stroke-width="1.7"/>',
        ),
      );
      expect(iconSource, isNot(contains('0xFF3B82F6')));
    });

    test('sender mobile Gifts flow uses web-backed draft field names', () {
      final giftSource =
          File('lib/app/sender_mobile/gift_mode_view.dart').readAsStringSync();
      final relationshipSource = File(
        'lib/app/sender_mobile/gift_relationship_view.dart',
      ).readAsStringSync();
      final deliverySource = File(
        'lib/app/sender_mobile/gift_delivery_view.dart',
      ).readAsStringSync();
      final messageSource = File('lib/app/sender_mobile/gift_message_view.dart')
          .readAsStringSync();
      final voiceSource =
          File('lib/app/sender_mobile/gift_voice_note_view.dart')
              .readAsStringSync();
      final themesSource = File('lib/app/sender_mobile/gift_themes_view.dart')
          .readAsStringSync();
      final irisSource =
          File('lib/app/sender_mobile/gift_iris_view.dart').readAsStringSync();
      final styleSource =
          File('lib/app/sender_mobile/gift_style_view.dart').readAsStringSync();
      final privacySource = File('lib/app/sender_mobile/gift_privacy_view.dart')
          .readAsStringSync();
      final budgetSource = File('lib/app/sender_mobile/gift_budget_view.dart')
          .readAsStringSync();
      final safetySource = File('lib/app/sender_mobile/gift_safety_view.dart')
          .readAsStringSync();
      final draftSource = File('lib/app/sender_mobile/gift_journey_draft.dart')
          .readAsStringSync();
      final reviewSource = File('lib/app/sender_mobile/gift_review_view.dart')
          .readAsStringSync();
      final prePaymentSource =
          File('lib/app/sender_mobile/gift_pre_payment_view.dart')
              .readAsStringSync();
      final paymentSource = File('lib/app/sender_mobile/gift_payment_view.dart')
          .readAsStringSync();
      final statusSource = File('lib/app/sender_mobile/gift_status_view.dart')
          .readAsStringSync();
      final storySource =
          File('lib/app/sender_mobile/gift_story_view.dart').readAsStringSync();

      expect(relationshipSource, contains('static const _totalSteps = 14'));
      expect(relationshipSource, contains('step <= _totalSteps'));
      expect(deliverySource, contains('activeStep: 3'));
      expect(voiceSource, contains('activeStep: 5'));
      expect(themesSource, contains('activeStep: 6'));
      expect(irisSource, contains('activeStep: 7'));
      expect(styleSource, contains('activeStep: 8'));
      expect(privacySource, contains('activeStep: 9'));
      expect(budgetSource, contains('activeStep: 10'));
      expect(safetySource, contains('activeStep: 11'));
      expect(reviewSource, contains('activeStep: 11'));
      expect(paymentSource, contains('activeStep: 12'));
      expect(statusSource, contains('activeStep: 13'));
      expect(storySource, contains('activeStep: 14'));

      expect(giftSource, contains("import 'gift_relationship_view.dart';"));
      expect(giftSource, contains('GiftRelationshipView'));
      expect(
        GiftRelationshipView.routeName,
        '/sender-mobile/gifts/relationship',
      );
      expect(GiftDeliveryView.routeName, '/sender-mobile/gifts/delivery');
      expect(GiftMessageView.routeName, '/sender-mobile/gifts/message');
      expect(GiftVoiceNoteView.routeName, '/sender-mobile/gifts/voice-note');
      expect(GiftThemesView.routeName, '/sender-mobile/gifts/themes');
      expect(GiftIrisView.routeName, '/sender-mobile/gifts/iris');
      expect(GiftSafetyView.routeName, '/sender-mobile/gifts/safety');
      expect(GiftReviewView.routeName, '/sender-mobile/gifts/review');
      expect(GiftPrePaymentView.routeName, '/sender-mobile/gifts/pre-payment');
      expect(GiftPaymentView.routeName, '/sender-mobile/gifts/payment');
      expect(GiftStatusView.routeName, '/sender-mobile/gifts/status');
      expect(GiftStoryView.routeName, '/sender-mobile/gifts/story');
      expect(senderGiftModeFieldName, 'giftMode');
      expect(senderGiftAnonymousGiftTypeFieldName, 'anonymousGiftType');
      expect(senderGiftSenderRevealModeFieldName, 'senderRevealMode');
      expect(senderGiftSelfGiftFrequencyFieldName, 'selfGiftFrequency');
      expect(senderGiftIrisSuggestionFieldName, 'irisSuggestion');
      expect(
        senderGiftPendingIrisSuggestion,
        'Pending IRIS gift recommendation',
      );
      expect(senderGiftPaymentDraftCollectionName, 'giftPaymentDrafts');
      expect(senderGiftAdminReviewCollectionName, 'giftRequests');
      expect(senderGiftPaymentCallableName, 'createGiftPayment');
      expect(senderGiftRelationshipFieldName, 'relationship');
      expect(senderGiftOccasionFieldName, 'occasion');
      expect(senderGiftRecipientNameFieldName, 'recipientName');
      expect(senderGiftRecipientPhoneFieldName, 'recipientPhone');
      expect(senderGiftRecipientEmailFieldName, 'recipientEmail');
      expect(senderGiftRecipientContactFieldName, 'recipientContact');
      expect(senderGiftRecipientNotesFieldName, 'notes');
      expect(senderGiftDeliveryAddressFieldName, 'deliveryAddress');
      expect(senderGiftDeliveryAddressDataFieldName, 'deliveryAddressData');
      expect(senderGiftDeliveryPostcodeFieldName, 'deliveryPostcode');
      expect(senderGiftDeliveryCityFieldName, 'deliveryCity');
      expect(senderGiftDeliveryCountryFieldName, 'deliveryCountry');
      expect(senderGiftAddressLookupCallableName, 'searchFreeUkAddresses');
      expect(senderGiftDeliveryDateFieldName, 'deliveryDate');
      expect(senderGiftDeliveryTimeWindowFieldName, 'deliveryTimeWindow');
      expect(senderGiftPersonalMessageFieldName, 'personalMessage');
      expect(
          senderGiftRelationshipOptions,
          containsAll([
            'Partner',
            'Husband',
            'Wife',
            'Business Partner',
            'Anonymous Recipient',
            'Other',
          ]));
      expect(senderGiftRelationshipOptions.length, 68);
      expect(
          senderGiftOccasionOptions,
          containsAll([
            'Birthday',
            'Anniversary',
            'Community Campaign',
            'Bringing London Together',
            'Other',
          ]));
      expect(senderGiftOccasionOptions.length, 84);
      expect(relationshipSource, contains('Tell us about them'));
      expect(
        relationshipSource,
        contains(
          'Tell IRIS who this is for so we can shape the experience.',
        ),
      );
      expect(relationshipSource, contains('PHONE & EMAIL'));
      expect(relationshipSource, isNot(contains("label: 'PHONE'")));
      expect(relationshipSource, isNot(contains("label: 'EMAIL'")));
      expect(relationshipSource, contains('Used for delivery updates only.'));
      expect(relationshipSource, contains('TELL US ABOUT THEM'));
      expect(relationshipSource, contains('What makes them special?'));
      expect(relationshipSource, contains('Tell us about yourself'));
      expect(relationshipSource, contains('WHAT MAKES YOU SPECIAL?'));
      expect(relationshipSource, contains('What makes you special?'));
      expect(relationshipSource, isNot(contains('CONTACT (PHONE OR EMAIL)')));
      expect(relationshipSource, isNot(contains('For delivery updates only')));
      expect(relationshipSource, contains('GiftDeliveryView'));
      expect(deliverySource, contains('Where and when?'));
      expect(deliverySource, contains('DELIVERY ADDRESS'));
      expect(deliverySource, contains('Where should it arrive?'));
      expect(deliverySource, contains('PlaceApiProvider'));
      expect(deliverySource, contains('searchFreeUkAddresses'));
      expect(deliverySource, contains('Verified delivery address selected.'));
      expect(
        deliverySource,
        contains(
          "Couldn't find matching addresses. Please continue typing or try again.",
        ),
      );
      expect(deliverySource, contains('PREFERRED DELIVERY DATE'));
      expect(deliverySource, contains('Preferred delivery date'));
      expect(deliverySource, contains('showDatePicker'));
      expect(
        deliverySource,
        isNot(contains("now.add(const Duration(days: 1))")),
      );
      expect(deliverySource, contains('PREFERRED DELIVERY TIME'));
      expect(deliverySource, contains('Preferred delivery time'));
      expect(deliverySource, contains('showTimePicker'));
      expect(
        deliverySource,
        contains(
          "I'm flexible. Let the Gifts Team choose the best delivery time.",
        ),
      );
      expect(deliverySource, contains('_GiftDeliverySummaryCard'));
      expect(deliverySource, contains('Flexible delivery selected'));
      expect(
          deliverySource, contains('The Gifts Team will optimise delivery.'));
      expect(deliverySource, isNot(contains('senderGiftDeliveryTimeWindows')));
      expect(deliverySource, isNot(contains("'Morning'")));
      expect(deliverySource, isNot(contains("'Afternoon'")));
      expect(deliverySource, isNot(contains("'Evening'")));
      expect(deliverySource, isNot(contains('senderGiftPreferredDateOptions')));
      expect(deliverySource, isNot(contains('Tell us the date that matters')));
      expect(deliverySource, isNot(contains('Choose with Gifts Team')));
      expect(deliverySource, contains('_selectedAddressSuggestion != null'));
      expect(deliverySource, contains('GiftMessageView'));
      expect(messageSource, contains('Write something from the heart'));
      expect(messageSource, contains('Write the message in your own words'));
      expect(messageSource, contains('Write the words you want'));
      expect(
          messageSource, isNot(contains('senderGiftPersonalMessageOptions')));
      expect(messageSource, isNot(contains('GiftMessageOptionCard')));
      expect(messageSource, isNot(contains('radio_button_checked_rounded')));
      expect(messageSource,
          isNot(contains('You mean more to me than I say often enough.')));
      expect(messageSource, contains('GiftVoiceNoteView'));
      expect(voiceSource, contains('STEP 05 — VOICE NOTE'));
      expect(voiceSource, contains('Leave a personal message'));
      expect(
        voiceSource,
        contains(
          "A short voice note helps our Gifts Team understand the emotion behind your gift.",
        ),
      );
      expect(voiceSource, contains('enum GiftVoiceNoteState'));
      expect(voiceSource, contains('GiftVoiceNoteState.idle'));
      expect(voiceSource, contains('GiftVoiceNoteState.permissionDenied'));
      expect(voiceSource, contains('GiftVoiceNoteState.recording'));
      expect(voiceSource, contains('GiftVoiceNoteState.recorded'));
      expect(voiceSource, contains('GiftVoiceNoteState.playing'));
      expect(voiceSource, contains('GiftVoiceNoteState.uploadFailed'));
      expect(voiceSource, isNot(contains('Permission.microphone.request')));
      expect(voiceSource, contains('SenderGiftVoiceRecorder'));
      expect(voiceSource, contains('SenderGiftVoicePlayback'));
      expect(voiceSource, contains('FirebaseStorage.instance.ref'));
      expect(voiceSource, contains('gift_requests/'));
      expect(voiceSource, contains('voice/original.webm'));
      expect(voiceSource, contains('_maxDurationSeconds = 60'));
      expect(
        voiceSource,
        contains(
          'Microphone access is blocked. Enable it in your browser settings, or skip this step.',
        ),
      );
      expect(voiceSource, contains('Record'));
      expect(voiceSource, contains('Stop'));
      expect(voiceSource, contains('Cancel'));
      expect(voiceSource, contains('Play'));
      expect(voiceSource, contains('Delete'));
      expect(voiceSource, contains('Re-record'));
      expect(voiceSource, contains('Use this recording'));
      expect(voiceSource, contains('Skip voice note'));
      expect(voiceSource, contains('GiftThemesView'));
      expect(themesSource, contains('STEP 06 — INTERESTS'));
      expect(themesSource, contains('What makes them smile?'));
      expect(themesSource, contains('Known Interests'));
      expect(themesSource, contains('Personal Interests'));
      expect(themesSource, contains("'Add'"));
      expect(themesSource, contains('onSubmitted'));
      expect(themesSource, contains("value.split(',')"));
      expect(themesSource, contains('Personal context'));
      expect(
        themesSource,
        contains(
            "We've saved this as personal context. IRIS will use it while planning the experience."),
      );
      expect(themesSource, contains('GiftIrisView'));
      expect(irisSource, contains('STEP 07 — IRIS'));
      expect(irisSource, contains('senderGiftIrisHardcodedInsights'));
      expect(irisSource, contains('How IRIS understands this moment'));
      expect(
        irisSource,
        contains('IRIS is reading the moment, not building a basket.'),
      );
      expect(
        irisSource,
        contains(
          'A thoughtful, personal experience that feels considered rather than performative.',
        ),
      );
      expect(irisSource, contains("The feeling we're creating"));
      expect(irisSource, contains("How we'll bring it to life"));
      expect(irisSource, contains("We'll avoid"));
      expect(irisSource, contains('Our confidence'));
      expect(irisSource, contains('Reviewed by the Gifts Team'));
      expect(irisSource, contains('generateIrisBrief'));
      expect(styleSource, contains('STEP 08 — STYLE & SIZES'));
      expect(styleSource, contains('Their style'));
      expect(styleSource, contains('senderGiftClothingSizeOptions'));
      expect(styleSource, contains('senderGiftShoeSizeOptions'));
      expect(styleSource, contains('senderGiftRingSizeOptions'));
      expect(styleSource, contains('senderGiftBrandOptions'));
      expect(styleSource, contains('senderGiftColourOptions'));
      expect(styleSource, contains('senderGiftPreferredStyleOptions'));
      expect(styleSource, contains('_usesFreeEntry'));
      expect(styleSource, contains('TextEditingController'));
      expect(styleSource, contains('inputCard('));
      expect(styleSource, contains('Tell us what you know'));
      expect(styleSource, contains('CLOTHING SIZE'));
      expect(styleSource, contains('SHOE SIZE'));
      expect(styleSource, contains('RING SIZE'));
      expect(styleSource, contains('COLOUR NOTES'));
      expect(styleSource, contains('PREFERRED STYLE'));
      expect(
        styleSource,
        contains(
          'Choose the styles that best describe what they enjoy wearing, collecting or surrounding themselves with.',
        ),
      );
      expect(styleSource, contains('Minimal'));
      expect(styleSource, contains('Classic'));
      expect(styleSource, contains('Modern'));
      expect(styleSource, contains('Bold'));
      expect(styleSource, contains('Luxury'));
      expect(styleSource, contains('Streetwear'));
      expect(styleSource, contains('Vintage'));
      expect(styleSource, contains('Elegant'));
      expect(styleSource, contains('Sporty'));
      expect(styleSource, contains('Cosy'));
      expect(styleSource, contains('preferredStyles'));
      expect(privacySource, contains('STEP 09 — REVEAL & PRIVACY'));
      expect(privacySource, contains('Allow Circum story use'));
      expect(
        privacySource,
        contains(
          "We'll take every dietary and medical preference into account during curation.",
        ),
      );
      expect(budgetSource, contains('STEP 10 — BUDGET'));
      expect(budgetSource, contains('Experience Budget'));
      expect(
        budgetSource,
        contains(
          'IRIS will curate the best possible experience within your chosen budget.',
        ),
      );
      expect(budgetSource, contains('Slider('));
      expect(budgetSource, contains('senderGiftBudgetOptions'));
      expect(budgetSource, contains('GiftSafetyView'));
      expect(budgetSource, isNot(contains('Premium Experience')));
      expect(budgetSource, isNot(contains('Luxury partner access')));
      expect(budgetSource, isNot(contains('Premium presentation')));
      expect(budgetSource, isNot(contains('Handwritten message eligible')));
      expect(budgetSource, isNot(contains('Concierge curation')));
      expect(draftSource, contains('SenderGiftMode.myself'));
      expect(draftSource, contains('SenderGiftMode.anonymous'));
      expect(draftSource, contains('SenderGiftMode.campaign'));
      expect(draftSource, contains("'gift_myself'"));
      expect(draftSource, contains("'anonymous_gift'"));
      expect(draftSource, contains("'anonymousGiftType'"));
      expect(draftSource, contains("'campaign'"));
      expect(draftSource, contains("'bringing-london-closer'"));
      expect(draftSource, contains("'Bringing London Closer'"));
      expect(draftSource, contains("'irisSuggestion'"));
      expect(draftSource, contains('Pending IRIS gift recommendation'));
      expect(draftSource, contains('fashionInterest'));
      expect(draftSource, contains('beautyInterest'));
      expect(draftSource, contains('skincareInterest'));
      expect(draftSource, contains('fragranceInterest'));
      expect(draftSource, contains('jewelleryInterest'));
      expect(draftSource, contains('adminReviewPayload'));
      expect(safetySource, contains('Anything we need to know?'));
      expect(safetySource,
          contains('Help the Gifts Team avoid unsuitable or unsafe gifts.'));
      expect(safetySource, contains('FOOD ALLERGIES'));
      expect(safetySource, contains('MEDICAL ALLERGIES'));
      expect(safetySource, contains('DIETARY RESTRICTIONS'));
      expect(safetySource, contains('RELIGIOUS OR CULTURAL CONSIDERATIONS'));
      expect(safetySource, contains('THINGS TO AVOID'));
      expect(
          safetySource, contains('ANYTHING ELSE THE GIFTS TEAM SHOULD KNOW'));
      expect(draftSource, contains('foodAllergies'));
      expect(draftSource, contains('medicalAllergies'));
      expect(draftSource, contains('dietaryRestrictions'));
      expect(draftSource, contains('religiousOrCulturalConsiderations'));
      expect(draftSource, contains('safetyThingsToAvoid'));
      expect(draftSource, contains('giftTeamSafetyNotes'));
      expect(draftSource, contains('procurementSafetyNotes'));
      expect(reviewSource, contains('STEP 11 — REVIEW'));
      expect(reviewSource,
          contains('Gift contents remain confidential before delivery.'));
      expect(reviewSource, contains('GiftPrePaymentView'));
      expect(prePaymentSource, contains("We've understood the moment"));
      expect(prePaymentSource, contains('BEFORE PAYMENT'));
      expect(
          prePaymentSource, contains('IRIS believes this occasion deserves'));
      expect(
        prePaymentSource,
        contains(
          'Every experience is reviewed by a real member of our Gifts Team before sourcing begins.',
        ),
      );
      expect(prePaymentSource, contains('GiftPaymentView'));
      expect(paymentSource, contains('STEP 12 — PAYMENT'));
      expect(paymentSource, contains('senderGiftPaymentCallableName'));
      expect(paymentSource, contains('senderGiftRothBalanceCallableName'));
      expect(paymentSource, contains('Gift Summary'));
      expect(paymentSource, contains('Available Roth balance'));
      expect(paymentSource, contains('Amount covered by Roth'));
      expect(paymentSource, contains('Remaining card amount'));
      expect(paymentSource, contains('Choose payment method'));
      expect(paymentSource, contains('Card'));
      expect(paymentSource, contains('Apple Pay'));
      expect(paymentSource, contains('Google Pay'));
      expect(paymentSource, contains('Apply Roth balance'));
      expect(paymentSource, contains('_showRothToggle'));
      expect(paymentSource, contains('Continue to Secure Payment'));
      expect(paymentSource, contains('Secure payment powered by Stripe.'));
      expect(
        paymentSource,
        contains('We prepare everything around your chosen delivery date.'),
      );
      expect(paymentSource, contains("'source': 'sender_mobile'"));
      expect(paymentSource,
          contains("'applyRoth': _applyRoth && _rothBalance > 0"));
      expect(paymentSource, contains("'returnOrigin': Uri.base.origin"));
      expect(
        paymentSource,
        contains(
            'Payment cancelled. Your gift request is saved. You can try again.'),
      );
      expect(draftSource, contains("'selectedBudgetGbp': budget"));
      expect(draftSource, contains("'source': 'sender_mobile'"));
      expect(draftSource, contains("'paymentMethod': 'card'"));
      expect(draftSource, contains("'applyRoth': false"));
      expect(draftSource, contains("'rothApplied': 0"));
      expect(draftSource, contains("'cardAmount': budget"));
      expect(draftSource, contains("'walletContributionGbp': 0"));
      expect(draftSource, contains("'remainingStripeAmountGbp': budget"));
      expect(draftSource, contains("'voiceNote': voiceNote?.toMap()"));
      expect(draftSource, contains("'localUrl': localUrl ?? localPath"));
      expect(draftSource, contains('preferredStyles'));
      expect(draftSource, contains("'giftThemes':"));
      expect(draftSource, contains("'giftThemeLabels':"));
      expect(draftSource, contains("'irisGiftBrief': brief.toMap()"));
      expect(reviewSource, contains('Voice note'));
      expect(reviewSource, contains('Added ·'));
      expect(reviewSource, contains('Chosen themes'));
      expect(reviewSource, contains('Personal themes'));
      expect(reviewSource, contains('Safety / allergies'));
      expect(reviewSource, contains('Roth payment summary'));
      expect(reviewSource, contains('Campaign · Bringing London Closer'));
      expect(reviewSource, contains('Campaign path'));
      expect(
        reviewSource,
        contains('This request follows the approved campaign review path.'),
      );
      expect(reviewSource, isNot(contains('IRIS GIFT BRIEF')));
      expect(reviewSource, contains('✨ IRIS has understood the moment'));
      expect(
        reviewSource,
        contains('Your gift remains completely confidential until delivery.'),
      );
      expect(
        reviewSource,
        contains(
          'The Gifts Team now understands the intention behind your gift — not just the budget.',
        ),
      );
      expect(reviewSource, contains('Emotional direction'));
      expect(reviewSource, contains('Experience direction'));
      expect(reviewSource, contains('Things to avoid'));
      expect(reviewSource, contains('Personalisation score'));
      expect(reviewSource, contains('Human review required'));
      expect(reviewSource, contains('✨ Our approach'));
      expect(reviewSource, contains('Who this is for'));
      expect(reviewSource, contains('What matters most'));
      expect(reviewSource, contains("How we'll approach it"));
      expect(reviewSource, contains("What we'll avoid"));
      expect(reviewSource, contains('Why this will feel personal'));
      expect(paymentSource, isNot(contains('Gift this experience')));
      expect(statusSource, contains('Your gift is in safe hands.'));
      expect(statusSource, contains('Request received'));
      expect(statusSource, contains('Planning begins'));
      expect(statusSource, contains('Experience prepared'));
      expect(statusSource, contains('Quality review'));
      expect(statusSource, contains('Awaiting rider'));
      expect(statusSource, contains('Out for delivery'));
      expect(statusSource, contains('Delivered'));
      expect(statusSource, contains('Gift Story rendering'));
      expect(statusSource, contains('Gift Story ready'));
      expect(statusSource, contains('Curated by the Gifts Team'));
      expect(statusSource, contains('Supported by IRIS'));
      expect(storySource, contains('FINALE — GIFT STORY'));
      expect(storySource, contains('Gift Story locked'));
      expect(
        storySource,
        contains('Your story will unlock after delivery is confirmed.'),
      );
      expect(storySource, contains('Your Gift Story is ready'));
      expect(relationshipSource, isNot(contains('createGiftPayment')));
      expect(deliverySource, isNot(contains('createGiftPayment')));
      expect(messageSource, isNot(contains('createGiftPayment')));
      expect(relationshipSource, isNot(contains('FirebaseFirestore')));
      expect(deliverySource, isNot(contains('FirebaseFirestore')));
      expect(messageSource, isNot(contains('FirebaseFirestore')));

      final campaignDraft =
          GiftJourneyDraft.forMode(SenderGiftMode.campaign).copyWith(
        recipientName: 'Anonymous campaign match',
        recipientPhone: '07123',
        recipientEmail: 'recipient@example.com',
        campaignId: 'christmas-giving',
        campaignName: 'Christmas Giving',
        campaignType: 'seasonal_kindness',
        campaignTagline: 'Small gestures for the festive season.',
        campaignCompatibilityScore: 69,
        campaignMatchSummary: 'Matched because both selected coffee.',
        recipientContentConsent: 'not_requested',
      );
      final campaignPayload = campaignDraft.adminReviewPayload(
        senderId: 'sender-1',
        senderEmail: 'sender@example.com',
      );
      expect(campaignPayload['giftMode'], 'anonymous_gift');
      expect(campaignPayload['anonymousGiftType'], 'campaign');
      expect(campaignPayload['giftType'], 'campaign');
      expect(campaignPayload['campaignId'], 'christmas-giving');
      expect(campaignPayload['campaignName'], 'Christmas Giving');
      expect(campaignPayload['campaignType'], 'seasonal_kindness');
      expect(campaignPayload['campaignCompatibilityScore'], 69);
      expect(campaignPayload['campaignMatchSummary'],
          'Matched because both selected coffee.');
      expect(campaignPayload['recipientContentConsent'], 'not_requested');
      expect(
        campaignPayload['irisSuggestion'],
        'Pending IRIS gift recommendation',
      );
      expect(campaignPayload['participantConsentRequired'], isTrue);
    });

    test('Gift themes map only supported IRIS signals', () {
      expect(
        senderGiftIrisSignalsForThemes(
          ['Fashion', 'Beauty', 'Makeup', 'Skincare', 'Fragrance', 'Jewellery'],
        ),
        containsAll([
          'fashionInterest',
          'beautyInterest',
          'skincareInterest',
          'fragranceInterest',
          'jewelleryInterest',
        ]),
      );
      expect(
        senderGiftIrisSignalsForThemes(['Tech', 'Gaming', 'Coffee']),
        isEmpty,
      );
      expect(
        senderGiftUnsupportedIrisThemes(['Fashion', 'Tech', 'Coffee']),
        ['Tech', 'Coffee'],
      );
      expect(
        senderGiftIrisUnsupportedCopy,
        "IRIS’s real catalog only tags gift signals for Beauty/Fashion. None of your selected themes fall in that range, so there’s nothing to suggest yet.",
      );
      expect(
        senderGiftIrisPartialUnsupportedCopy,
        'No IRIS coverage yet for some themes.',
      );
      final draft = GiftJourneyDraft.forMode(SenderGiftMode.someone).copyWith(
        giftThemes: [
          SenderGiftTheme.catalogue('Fashion'),
          SenderGiftTheme.custom('hhh'),
        ],
        voiceNote: SenderGiftVoiceNote(
          hasVoiceNote: true,
          durationSeconds: 12,
          localUrl: 'blob:http://localhost/test',
          localPath: 'local://sender-mobile/gifts/voice-note/test.m4a',
          storagePath: 'gift_requests/sender-1_123/voice/original.webm',
          downloadUrl: 'https://storage.example/voice.webm',
          createdAt: DateTime.utc(2026),
        ),
        preferredStyles: const ['Minimal', 'Elegant'],
        foodAllergies: 'Nut allergy',
        medicalAllergies: 'Sensitive skin',
        dietaryRestrictions: 'Vegan',
        culturalConsiderations: 'No alcohol',
        safetyThingsToAvoid: "Doesn't wear jewellery",
        giftTeamNotes: 'Claustrophobic',
        irisGiftBrief: SenderGiftIrisBrief(
          emotionalDirection: 'Warm',
          experienceDirection: 'Concierge',
          thingsToAvoid: 'No guesses',
          catalogueCoverage: const ['fashionInterest'],
          confidence: 'High',
          personalisationScore: 90,
          allergySafetyNotes: 'None supplied',
          recommendedPartnerCategories: const ['fashion'],
          createdAt: DateTime.utc(2026),
        ),
      );
      final payload = draft.adminReviewPayload(
        senderId: 'sender-1',
        senderEmail: 'sender@example.com',
      );
      expect(payload['giftThemeLabels'], ['Fashion', 'hhh']);
      expect(payload['customInterests'], ['hhh']);
      expect(payload['giftThemes'], [
        {'label': 'Fashion', 'source': 'catalogue', 'knownToIris': true},
        {'label': 'hhh', 'source': 'custom', 'knownToIris': false},
      ]);
      expect(
        payload['voiceNote'],
        containsPair('localUrl', 'blob:http://localhost/test'),
      );
      expect(
        payload['voiceNote'],
        containsPair(
            'localPath', 'local://sender-mobile/gifts/voice-note/test.m4a'),
      );
      expect(
        payload['voiceNote'],
        containsPair(
            'storagePath', 'gift_requests/sender-1_123/voice/original.webm'),
      );
      expect(
        payload['voiceNote'],
        containsPair('downloadUrl', 'https://storage.example/voice.webm'),
      );
      expect(payload['preferredStyles'], ['Minimal', 'Elegant']);
      expect(payload['foodAllergies'], 'Nut allergy');
      expect(payload['medicalAllergies'], 'Sensitive skin');
      expect(payload['dietaryRestrictions'], 'Vegan');
      expect(payload['religiousOrCulturalConsiderations'], 'No alcohol');
      expect(payload['safetyThingsToAvoid'], "Doesn't wear jewellery");
      expect(payload['giftTeamSafetyNotes'], 'Claustrophobic');
      expect(
        payload['allergySafetyNotes'],
        contains('Food allergies: Nut allergy'),
      );
      expect(
        payload['procurementSafetyNotes'],
        containsPair('thingsToAvoid', "Doesn't wear jewellery"),
      );
      expect(payload['irisGiftBrief'], containsPair('confidence', 'High'));
    });

    testWidgets('Gift someone opens relationship screen and back returns', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const MaterialApp(home: GiftModeView()));

      expect(find.text('Gift someone'), findsOneWidget);
      expect(find.text('Gift myself'), findsOneWidget);
      expect(find.text('Anonymous gift'), findsOneWidget);
      expect(find.text('Campaign'), findsOneWidget);

      await tester.tap(find.text('Gift someone'));
      await tester.pumpAndSettle();

      expect(find.text('Tell us about them'), findsOneWidget);
      expect(find.text('PHONE & EMAIL'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Choose your gift mode.'), findsOneWidget);
      expect(find.text('Gift someone'), findsOneWidget);
    });

    testWidgets('Gift myself uses self-specific recipient copy', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const MaterialApp(home: GiftModeView()));

      await tester.tap(find.text('Gift myself'));
      await tester.pumpAndSettle();

      expect(find.text('Tell us about yourself'), findsOneWidget);
    });

    testWidgets('Campaign opens native anonymous matching flow', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const MaterialApp(home: GiftModeView()));

      await tester.tap(find.text('Campaign'));
      await tester.pumpAndSettle();

      expect(find.text('Bring London Closer'), findsOneWidget);
      expect(find.text('Join Campaign'), findsOneWidget);

      await tester.tap(find.text('Join Campaign'));
      await tester.pumpAndSettle();

      expect(find.text('Choose campaign'), findsOneWidget);
      expect(find.text('Bringing London Closer'), findsOneWidget);
      expect(find.text('Tell us about them'), findsNothing);
      expect(find.text('Where and when?'), findsNothing);

      await tester.tap(find.text('Bringing London Closer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.text('About you'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'North Londoner');
      await tester.tap(find.text('Travel'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -900));
      await tester.pumpAndSettle();
      expect(find.text('ADD YOUR OWN INSPIRATION'), findsOneWidget);
      expect(find.text('Write your own inspiration...'), findsOneWidget);
      await tester.drag(find.byType(ListView), const Offset(0, 900));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.text('Safety'), findsOneWidget);
      await tester.drag(find.byType(ListView), const Offset(0, -700));
      await tester.pumpAndSettle();
      expect(find.text('PEOPLE TO AVOID'), findsOneWidget);
      expect(
          find.text('Name, handle, phone, or email if known'), findsOneWidget);
      expect(find.text('Blocklist'), findsNothing);
      expect(find.text('Optional blocked user IDs'), findsNothing);
      await tester.drag(find.byType(ListView), const Offset(0, 700));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.text('Privacy'), findsOneWidget);
    });

    test('Campaign Gifts is separate from known-recipient Gifts flow', () {
      final campaignSource =
          File('lib/app/sender_mobile/gift_campaign_view.dart')
              .readAsStringSync();

      expect(campaignSource, contains('giftCampaignParticipants'));
      expect(campaignSource, contains('giftCampaignMatches'));
      expect(campaignSource, contains('senderGiftPaymentDraftCollectionName'));
      expect(campaignSource, contains('giftDraftId'));
      expect(campaignSource, contains('campaignParticipantId'));
      expect(campaignSource, contains('campaignFlow'));
      expect(campaignSource, contains('paid_waiting_for_match'));
      expect(campaignSource, contains('checkout_pending'));
      expect(campaignSource, contains('Payment ready'));
      expect(campaignSource, contains('Processing payment...'));
      expect(campaignSource, contains('Continue to Secure Payment'));
      expect(campaignSource, contains('customInspiration'));
      expect(campaignSource, contains('ADD YOUR OWN INSPIRATION'));
      expect(campaignSource, contains('Write your own inspiration...'));
      expect(campaignSource, contains('PEOPLE TO AVOID'));
      expect(
        campaignSource,
        contains('Name, handle, phone, or email if known'),
      );
      expect(campaignSource, contains('avoidanceSignals'));
      expect(campaignSource, contains('awaiting_admin_pairing'));
      expect(campaignSource, contains('recipientKnown'));
      expect(campaignSource, contains('deliveryCollected'));
      expect(campaignSource, contains('GiftsSocialPolicy.scoreMatch'));
      expect(campaignSource, contains('GiftsSocialPolicy.recipientSafeView'));
      expect(campaignSource, contains('GiftsSocialPolicy.canRevealSender'));
      expect(campaignSource, contains('GiftsSocialPolicy.canPostPublicly'));
      expect(campaignSource, contains('GiftsSocialPolicy.canApproveBrandTags'));
      expect(campaignSource, contains('Anonymous match found'));
      expect(campaignSource, contains('Waiting for your match'));
      expect(campaignSource, contains('Status updates automatically'));
      expect(campaignSource, contains('ready_for_gift_delivery'));
      expect(campaignSource, contains('Ready for Gift Delivery'));
      expect(
        campaignSource,
        contains(
          'Your campaign journey is complete. Your gift is now moving into the standard Circum Gifts delivery workflow.',
        ),
      );
      expect(campaignSource, contains('linkedGiftDeliveryStatus'));
      expect(campaignSource, contains('giftRequestId'));
      expect(campaignSource, contains('giftDeliveryId'));
      expect(campaignSource, contains('handoffStatus'));
      expect(campaignSource, contains('View Gift Story'));
      expect(campaignSource, isNot(contains("title: 'Delivered'")));
      expect(campaignSource, isNot(contains('STEP 10 · Delivered')));
      expect(campaignSource, contains('campaignStatus'));
      expect(campaignSource, contains('statusUpdatedAt'));
      expect(campaignSource, contains('budgetPrivacyNote'));
      expect(campaignSource, isNot(contains('Preview Next')));
      expect(campaignSource, isNot(contains('campaign_preview_step')));
      expect(campaignSource, isNot(contains('STEP 09 — MATCH FOUND')));
      expect(campaignSource, contains('No recipient fields here.'));
      expect(campaignSource, contains('Delivery address'));
      expect(
        campaignSource,
        contains(
          'Delivery address, recipient identity and handover details are handled after admin pairing approval.',
        ),
      );
      expect(
          campaignSource, isNot(contains("import 'gift_delivery_view.dart'")));
      expect(campaignSource, isNot(contains('GiftDeliveryView(')));
      expect(campaignSource, isNot(contains("import 'gift_review_view.dart'")));
      expect(campaignSource, isNot(contains('GiftReviewView(')));
      expect(campaignSource, isNot(contains("label: 'BLOCKLIST'")));
      expect(campaignSource, isNot(contains('Optional blocked user IDs')));
    });

    test('Campaign handoff does not duplicate Gift Delivery or Story unlock',
        () {
      final campaignSource =
          File('lib/app/sender_mobile/gift_campaign_view.dart')
              .readAsStringSync();
      final draftSource = File('lib/app/sender_mobile/gift_journey_draft.dart')
          .readAsStringSync();
      final storySource =
          File('lib/app/sender_mobile/gift_story_view.dart').readAsStringSync();
      final statusSource = File('lib/app/sender_mobile/gift_status_view.dart')
          .readAsStringSync();

      expect(campaignSource, contains('ready_for_gift_delivery'));
      expect(campaignSource, contains('linkedGiftDeliveryStatus'));
      expect(campaignSource, contains('Gift Story locked'));
      expect(campaignSource, contains('Your Gift Story is ready'));
      expect(campaignSource, contains('View Gift Story'));
      expect(campaignSource, isNot(contains('GiftDeliveryView(')));
      expect(campaignSource, isNot(contains("title: 'Delivered'")));
      expect(campaignSource, isNot(contains('Delivery Complete')));

      expect(draftSource, contains('campaignParticipantId'));
      expect(draftSource, contains('giftRequestId'));
      expect(draftSource, contains('giftDeliveryId'));
      expect(draftSource, contains('riderCompletionAccepted'));
      expect(draftSource, contains('deliveryVerificationCompleted'));
      expect(draftSource, contains('deliveryAuditSuccessful'));
      expect(draftSource, contains('activeDeliveryDispute'));
      expect(draftSource, contains('giftStoryStatus'));
      expect(draftSource, contains('giftStoryAdminOverrideReason'));
      expect(draftSource, contains("linkedGiftDeliveryStatus == 'delivered'"));
      expect(
        draftSource,
        contains(
          'riderCompletionAccepted &&',
        ),
      );
      expect(draftSource, contains('deliveryVerificationCompleted &&'));
      expect(draftSource, contains('deliveryAuditSuccessful &&'));
      expect(draftSource, contains('!activeDeliveryDispute'));

      expect(storySource, contains('Gift Story locked'));
      expect(
        storySource,
        contains('Your story will unlock after delivery is confirmed.'),
      );
      expect(storySource, contains('Your Gift Story is ready'));
      expect(storySource, contains('draft.giftStoryUnlocked'));

      expect(statusSource, contains('View Gift Story'));
      expect(statusSource, contains('Gift Story locked'));

      final locked = GiftJourneyDraft.forMode(SenderGiftMode.campaign).copyWith(
        linkedGiftDeliveryStatus: 'ready_for_gift_delivery',
      );
      final delivered =
          GiftJourneyDraft.forMode(SenderGiftMode.campaign).copyWith(
        linkedGiftDeliveryStatus: 'delivered',
      );
      final operationallyComplete =
          GiftJourneyDraft.forMode(SenderGiftMode.campaign).copyWith(
        linkedGiftDeliveryStatus: 'delivered',
        riderCompletionAccepted: true,
        deliveryVerificationCompleted: true,
        deliveryAuditSuccessful: true,
      );
      final disputed =
          GiftJourneyDraft.forMode(SenderGiftMode.campaign).copyWith(
        linkedGiftDeliveryStatus: 'delivered',
        riderCompletionAccepted: true,
        deliveryVerificationCompleted: true,
        deliveryAuditSuccessful: true,
        activeDeliveryDispute: true,
      );

      expect(locked.giftStoryUnlocked, isFalse);
      expect(locked.giftStoryStatus, 'locked');
      expect(delivered.giftStoryUnlocked, isFalse);
      expect(operationallyComplete.giftStoryUnlocked, isTrue);
      expect(operationallyComplete.giftStoryStatus, 'unlocked');
      expect(disputed.giftStoryUnlocked, isFalse);
    });

    test('Campaign matching is budget-independent and budget-private', () {
      expect(
        GiftsSocialPolicy.campaignBudgetIndependenceRule,
        contains('budget-independent'),
      );
      final baseParticipant = {
        'userId': 'sender-a',
        'matchConsent': true,
        'matchStatus': 'active',
        'interests': ['coffee', 'architecture'],
        'hobbies': ['walking'],
        'lifestyle': ['wellness'],
        'customInspiration': 'London mornings',
        'allergies': <String>[],
        'blockedUserIds': <String>[],
        'budget': 1500,
        'paymentMethod': 'roth_card',
        'rothApplied': 200,
        'cardAmount': 1300,
      };
      final lowBudgetMatch = {
        'userId': 'sender-b',
        'matchConsent': true,
        'matchStatus': 'active',
        'interests': ['coffee', 'architecture'],
        'hobbies': ['walking'],
        'lifestyle': ['wellness'],
        'allergies': <String>[],
        'blockedUserIds': <String>[],
        'budget': 50,
      };
      final highBudgetMatch = {
        ...lowBudgetMatch,
        'budget': 1500,
      };

      final lowBudgetScore =
          GiftsSocialPolicy.scoreMatch(baseParticipant, lowBudgetMatch);
      final highBudgetScore =
          GiftsSocialPolicy.scoreMatch(baseParticipant, highBudgetMatch);

      expect(lowBudgetScore.score, greaterThan(0));
      expect(lowBudgetScore.score, highBudgetScore.score);
      expect(lowBudgetScore.reason.toLowerCase(), isNot(contains('budget')));
      expect(lowBudgetScore.reason.toLowerCase(), isNot(contains('spend')));

      final safe = GiftsSocialPolicy.recipientSafeView(baseParticipant);
      expect(safe, isNot(contains('budget')));
      expect(safe, isNot(contains('paymentMethod')));
      expect(safe, isNot(contains('rothApplied')));
      expect(safe, isNot(contains('cardAmount')));
    });

    testWidgets('Gift flow validates recipient, delivery, and message steps', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const MaterialApp(home: GiftRelationshipView()));

      expect(find.text('Continue'), findsOneWidget);
      await tester.ensureVisible(find.text('Continue'));
      await tester.tap(find.text('Continue'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('Where and when?'), findsNothing);

      await tester.ensureVisible(find.text('Choose relationship'));
      await tester.tap(find.byType(DropdownButton<String>).at(0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Partner').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButton<String>).at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Birthday').last);
      await tester.pumpAndSettle();
      final recipientFields = find.byType(TextField);
      await tester.enterText(recipientFields.at(0), 'Ada Recipient');
      await tester.enterText(recipientFields.at(1), '07123 456789');
      await tester.enterText(recipientFields.at(2), 'recipient@example.com');
      await tester.enterText(
          recipientFields.at(3), 'They love quiet surprises.');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Continue'));
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.text('Where and when?'), findsOneWidget);
      expect(find.text('DELIVERY ADDRESS'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();
      expect(find.byType(GiftRelationshipView), findsOneWidget);

      await tester.ensureVisible(find.text('Continue'));
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Where and when?'), findsOneWidget);
      await tester.ensureVisible(find.text('Continue'));
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Write something from the heart'), findsNothing);

      final verifiedDraft = GiftJourneyDraft.forMode(
        SenderGiftMode.someone,
      ).copyWith(
        deliveryAddress: '221B Baker Street, London NW1 6XE',
        deliveryAddressData: Suggestion(
          placeId: 'verified-221b',
          description: '221B Baker Street, London NW1 6XE',
          mainText: '221B Baker Street',
          subText: 'London NW1 6XE',
          components: const {
            'postcode': 'NW1 6XE',
            'city': 'London',
            'country': 'GB',
          },
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          key: UniqueKey(),
          home: GiftDeliveryView(draft: verifiedDraft),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('PREFERRED DELIVERY DATE'), findsOneWidget);
      expect(find.text('Choose a date'), findsOneWidget);
      expect(find.text('PREFERRED DELIVERY TIME'), findsOneWidget);
      expect(find.text('Choose a time'), findsOneWidget);
      await tester.drag(find.byType(ListView).first, const Offset(0, -260));
      await tester.pumpAndSettle();
      expect(
        find.text(
          "I'm flexible. Let the Gifts Team choose the best delivery time.",
        ),
        findsOneWidget,
      );
      await tester.tap(find.byType(SwitchListTile).first);
      await tester.pumpAndSettle();
      expect(find.text('Flexible delivery selected'), findsWidgets);
      expect(
        find.text('The Gifts Team will optimise delivery.'),
        findsOneWidget,
      );

      await tester.pumpWidget(
        MaterialApp(
          key: UniqueKey(),
          home: GiftMessageView(
            draft: verifiedDraft.copyWith(
              deliveryDate: 'Friday 18 July',
              deliveryTimeWindow: 'Late afternoon',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Write the message in your own words'), findsOneWidget);
      await tester.enterText(
        find.byType(TextField),
        'I wanted this to feel like a little piece of calm.',
      );

      await tester.ensureVisible(find.text('Continue'));
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Leave a personal message'), findsNothing);

      await tester.pumpWidget(
        MaterialApp(
          key: UniqueKey(),
          home: GiftVoiceNoteView(
            draft: verifiedDraft.copyWith(
              deliveryDate: 'Tomorrow',
              deliveryTimeWindow: 'Afternoon',
              personalMessage: 'You mean more to me than I say often enough.',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Leave a personal message'), findsOneWidget);
      expect(find.text('Skip voice note'), findsOneWidget);

      await tester.tap(find.text('Skip voice note'));
      await tester.pumpAndSettle();

      expect(find.text('What makes them smile?'), findsOneWidget);
      expect(find.text('KNOWN INTEREST'), findsOneWidget);
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
