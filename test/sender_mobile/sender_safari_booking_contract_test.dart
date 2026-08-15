import 'dart:io';

import 'package:circum/app/platform/address_engine.dart';
import 'package:circum/app/send_package/models/suggestions.m.dart';
import 'package:circum/app/sender_mobile/sender_booking_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Sender platform address precision contract', () {
    test('Flat 190 Edridge Road keeps unit and building without duplication',
        () {
      final resolved = AddressEngine.cleanSuggestion(
        Suggestion(
          placeId: 'google-edridge-4',
          description: 'Flat 190, 4 Edridge Road, Croydon, CR0 1GD, UK',
          mainText: '4 Edridge Road',
          subText: 'Croydon CR0 1GD',
          lat: 51.3728,
          lng: -0.1007,
          components: const {
            'addressLine1': '4 Edridge Road',
            'buildingNumber': '4',
            'street': 'Edridge Road',
            'apartment': 'Flat 190',
            'city': 'Croydon',
            'postcode': 'CR0 1GD',
            'country': 'United Kingdom',
            'resolutionPrecision': 'unit',
          },
        ),
      );

      expect(resolved.description, startsWith('Flat 190, 4 Edridge Road'));
      expect(RegExp('Flat 190').allMatches(resolved.description), hasLength(1));
      expect(resolved.components['apartment'], 'Flat 190');
      expect(resolved.components['buildingNumber'], '4');
      expect(resolved.components['street'], 'Edridge Road');
      expect(resolved.components['postcode'], 'CR0 1GD');
      expect(resolved.components['resolutionPrecision'], 'unit');
    });

    test('City Road formatting does not duplicate the same address line', () {
      final resolved = AddressEngine.cleanSuggestion(
        Suggestion(
          placeId: 'google-city-road-124',
          description: '124 City Road, 124 City Road, London, United Kingdom',
          mainText: '124 City Road',
          subText: 'London',
          lat: 51.5274,
          lng: -0.0878,
          components: const {
            'addressLine1': '124 City Road',
            'addressLine2': '124 City Road',
            'buildingNumber': '124',
            'street': 'City Road',
            'city': 'London',
            'country': 'United Kingdom',
            'resolutionPrecision': 'premise',
          },
        ),
      );

      expect(
        RegExp('124 City Road').allMatches(resolved.description),
        hasLength(1),
      );
      expect(resolved.description, contains('London'));
      expect(resolved.components['buildingNumber'], '124');
      expect(resolved.components['street'], 'City Road');
    });

    test('manual Sender address confirmation is not provider gated', () {
      final canvas = File('lib/app/sender_mobile/sender_booking_canvas.dart')
          .readAsStringSync();
      final provider =
          File('lib/app/send_package/repo/place_api.dart').readAsStringSync();

      expect(canvas, contains("hint: 'Pickup address, flat or postcode'"));
      expect(canvas, contains("hint: 'Drop-off address, flat or postcode'"));
      expect(canvas, isNot(contains("hint: 'Address line 1'")));
      expect(canvas, isNot(contains("hint: 'City / town'")));
      expect(
        canvas,
        contains('return _enrichTypedAddressCoordinates'),
      );
      expect(
          canvas, isNot(contains('unawaited(_enrichTypedAddressCoordinates')));
      expect(
        canvas,
        contains('Type the full address with postcode, then continue.'),
      );
      expect(canvas, isNot(contains('street, city and postcode')));
      expect(canvas, contains('resolveTypedAddress(address, lang)'));
      expect(
        canvas,
        isNot(contains('We could not verify that address')),
      );
      expect(
        canvas,
        isNot(
          contains(
              'Add a house or flat number, street, town and postcode, then try again.'),
        ),
      );
      expect(canvas, isNot(contains('No exact address match found')));
      expect(
        canvas,
        isNot(
          contains(
              'Please choose a matching address suggestion before continuing.'),
        ),
      );
      expect(provider, contains('Future<Suggestion> resolveTypedAddress'));
      expect(provider, contains("'sourceInput': sourceInput!.trim()"));
      expect(provider, contains('_bestTypedResolutionCandidate'));
    });

    test('building-only Edridge Road does not fabricate a flat', () {
      final resolved = AddressEngine.cleanSuggestion(
        Suggestion(
          placeId: 'google-edridge-4',
          description: '4 Edridge Road, Croydon, CR0 1GD, UK',
          mainText: '4 Edridge Road',
          subText: 'Croydon CR0 1GD',
          lat: 51.3728,
          lng: -0.1007,
          components: const {
            'addressLine1': '4 Edridge Road',
            'buildingNumber': '4',
            'street': 'Edridge Road',
            'city': 'Croydon',
            'postcode': 'CR0 1GD',
            'country': 'United Kingdom',
          },
        ),
      );

      expect(resolved.description, startsWith('4 Edridge Road'));
      expect(resolved.components['apartment'], isNull);
      expect(resolved.components['buildingNumber'], '4');
      expect(resolved.components['resolutionPrecision'], 'premise');
    });

    test(
        'Place API preserves cached unit only through matching building details',
        () {
      final source =
          File('lib/app/send_package/repo/place_api.dart').readAsStringSync();

      expect(source, contains('_preserveCachedUnitMetadata'));
      expect(source, contains('cachedBuilding'));
      expect(source, contains('resolvedBuilding'));
      expect(source, contains('cachedBuilding.toLowerCase() !='));
      expect(source, contains('AddressEngine.cleanSuggestion(merged)'));
      expect(source, contains("'sourceInput'"));
    });

    test('stale address search responses cannot overwrite newer query state',
        () {
      final source = File('lib/app/send_package/bloc/send_package_bloc.dart')
          .readAsStringSync();

      expect(source, contains('_addressSearchGeneration'));
      expect(source, contains('final generation = ++_addressSearchGeneration'));
      expect(source, contains('generation != _addressSearchGeneration'));
    });

    test('Gift delivery address can continue from manual entry', () {
      final source = File('lib/app/sender_mobile/gift_delivery_view.dart')
          .readAsStringSync();

      expect(source, contains('_manualGiftAddressSuggestion(address)'));
      expect(
        source,
        contains(
            'Enter a full delivery address. Search suggestions are optional.'),
      );
      expect(
        source,
        isNot(
          contains(
              'That address could not be verified. Check the house or flat number, street, town and postcode.'),
        ),
      );
      expect(
        source,
        isNot(contains('We will verify it before continuing.')),
      );
    });
  });

  group('Sender scheduled delivery contract', () {
    test('preferred dates are generated from injected London current date', () {
      final londonLateNight = DateTime.utc(2026, 8, 13, 23, 30);
      final dates = senderScheduleDateOptions(now: londonLateNight, days: 5);

      expect(dates.map(senderScheduleDateValue), [
        '2026-08-14',
        '2026-08-15',
        '2026-08-16',
        '2026-08-17',
        '2026-08-18',
      ]);
      expect(senderScheduleDayLabel(dates[0], now: londonLateNight), 'Today');
      expect(
        senderScheduleDayLabel(dates[1], now: londonLateNight),
        'Tomorrow',
      );
      expect(senderScheduleMonthDayLabel(dates[0]), '14 Aug');
    });

    test('preferred dates expose a rolling future scheduling horizon', () {
      final dates = senderScheduleDateOptions(
        now: DateTime.utc(2026, 8, 15, 9),
      );

      expect(dates.length, greaterThanOrEqualTo(370));
      expect(senderScheduleDateValue(dates.first), '2026-08-15');
      expect(senderScheduleDateValue(dates[7]), '2026-08-22');
      expect(senderScheduleDateValue(dates[29]), '2026-09-13');
      expect(senderScheduleDateValue(dates[365]), '2027-08-15');
    });

    test('scheduled date selector exposes a next-year capable date picker', () {
      final source = File('lib/app/sender_mobile/sender_booking_canvas.dart')
          .readAsStringSync();

      expect(source, contains('showDatePicker'));
      expect(source, contains('senderScheduleHorizonDays'));
      expect(source, contains('Choose another date'));
    });

    test('schedule labels are not hardcoded in Sender booking UI', () {
      final source = File('lib/app/sender_mobile/sender_booking_canvas.dart')
          .readAsStringSync();

      expect(source, contains('senderScheduleDateOptions()'));
      expect(source, isNot(contains("'14 Aug'")));
      expect(source, isNot(contains("'15 Aug'")));
      expect(source, isNot(contains("'16 Aug'")));
      expect(source, isNot(contains("'17 Aug'")));
    });

    test('today blocks past scheduled windows in London time', () {
      final now = DateTime.utc(2026, 8, 14, 14);
      final iso = senderScheduledJourneyIso(
        scheduledDate: '2026-08-14',
        scheduledWindow: 'Morning',
      );

      expect(
        isSenderScheduledSelectionValid(
          scheduledDate: '2026-08-14',
          scheduledJourneyAt: iso,
          scheduledWindow: 'Morning',
          now: now,
        ),
        isFalse,
      );
    });

    test('future dates allow valid London scheduled windows', () {
      final now = DateTime.utc(2026, 8, 14, 14);
      final iso = senderScheduledJourneyIso(
        scheduledDate: '2026-08-15',
        scheduledWindow: 'Morning',
      );

      expect(
        isSenderScheduledSelectionValid(
          scheduledDate: '2026-08-15',
          scheduledJourneyAt: iso,
          scheduledWindow: 'Morning',
          now: now,
        ),
        isTrue,
      );
    });

    test('custom scheduled window requires valid HH:mm range', () {
      final iso = senderScheduledJourneyIso(
        scheduledDate: '2026-08-15',
        scheduledWindow: 'Custom',
        customWindowStart: '16:30',
        customWindowEnd: '18:00',
      );

      expect(iso, isNotEmpty);
      expect(
        isSenderScheduledSelectionValid(
          scheduledDate: '2026-08-15',
          scheduledJourneyAt: iso,
          scheduledWindow: 'Custom',
          customWindowStart: '16:30',
          customWindowEnd: '18:00',
          now: DateTime.utc(2026, 8, 14, 14),
        ),
        isTrue,
      );
      expect(
        senderScheduledJourneyIso(
          scheduledDate: '2026-08-15',
          scheduledWindow: 'Custom',
          customWindowStart: '18:00',
          customWindowEnd: '16:30',
        ),
        isEmpty,
      );
    });

    test('scheduled draft serializes canonical timestamp and window', () {
      final futureDate = senderScheduleDateValue(
        senderScheduleDateOptions(days: 3).last,
      );
      final iso = senderScheduledJourneyIso(
        scheduledDate: futureDate,
        scheduledWindow: 'Afternoon',
      );
      final draft = SenderBookingDraft(
        deliveryTimingType: SenderDeliveryTimingType.scheduled,
        scheduledDate: futureDate,
        scheduledWindow: 'Afternoon',
        scheduledJourneyAt: iso,
      );
      final deliveryTime = draft.toBackendDraftPayload()['deliveryTime'] as Map;

      expect(draft.isDeliveryTimeValid, isTrue);
      expect(deliveryTime['type'], 'scheduled');
      expect(deliveryTime['scheduledDate'], futureDate);
      expect(deliveryTime['scheduledWindow'], 'Afternoon');
      expect(deliveryTime['scheduledJourneyAt'], iso);
      expect(
        deliveryTime['summary'],
        'Scheduled: ${senderScheduleMonthDayLabel(DateTime.parse(futureDate))}, Afternoon',
      );
    });

    test('scheduled Rider availability warning is absent', () {
      final source = File('lib/app/sender_mobile/sender_booking_canvas.dart')
          .readAsStringSync();

      expect(
        source,
        isNot(contains(
            'Scheduled deliveries depend on Circum Rider availability')),
      );
      expect(
        source,
        isNot(contains("We'll confirm before the delivery begins")),
      );
    });
  });
}
