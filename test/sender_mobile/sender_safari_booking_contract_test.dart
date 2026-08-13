import 'package:circum/app/platform/address_engine.dart';
import 'package:circum/app/sender_mobile/sender_booking_canvas.dart';
import 'package:circum/app/sender_mobile/sender_booking_state.dart';
import 'package:circum/app/send_package/models/suggestions.m.dart';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

void main() {
  group('Sender Safari booking address contract', () {
    test('typed text alone is not enough to continue', () {
      const draft = SenderBookingDraft(
        step: SenderBookingStep.pickup,
        pickupAddress: '29 St Fillans Road SE6 1DQ',
      );

      expect(isSenderTypedAddressSpecific(draft.pickupAddress), isTrue);
      expect(draft.canContinue, isFalse);
    });

    test('resolved UK coordinates are enough even when formatting differs', () {
      const pickup = SenderBookingDraft(
        step: SenderBookingStep.pickup,
        pickupAddress: '29 St Fillans Road, London SE6 1DQ, UK',
        pickupLat: 51.4329,
        pickupLng: -0.0205,
      );
      const dropoff = SenderBookingDraft(
        step: SenderBookingStep.dropoff,
        dropoffAddress: 'CR0 1GD, Greater London, England',
        dropoffLat: 51.3737,
        dropoffLng: -0.1004,
      );

      expect(pickup.canContinue, isTrue);
      expect(dropoff.canContinue, isTrue);
    });

    test('resolved numbered premise keeps house and flat detail', () {
      final resolved = AddressEngine.cleanSuggestion(
        Suggestion(
          placeId: 'premise_29',
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
        ),
      );

      expect(resolved.description, contains('29 St Fillans Road'));
      expect(resolved.components['addressLine1'], '29 St Fillans Road');
      expect(resolved.components['buildingNumber'], '29');
      expect(resolved.components['street'], 'St Fillans Road');
      expect(resolved.components['apartment'], 'Flat 4');
      expect(resolved.components['resolutionPrecision'], 'unit');
    });

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
    });

    test('stale address search responses cannot overwrite newer query state',
        () {
      final source = File('lib/app/send_package/bloc/send_package_bloc.dart')
          .readAsStringSync();

      expect(source, contains('_addressSearchGeneration'));
      expect(source, contains('final generation = ++_addressSearchGeneration'));
      expect(source, contains('generation != _addressSearchGeneration'));
    });

    test('resolution precision distinguishes premise from street fallback', () {
      expect(
        AddressEngine.inferResolutionPrecision(
          buildingNumber: '29',
          street: 'St Fillans Road',
          postcode: 'SE6 1DQ',
        ),
        'premise',
      );
      expect(
        AddressEngine.inferResolutionPrecision(
          street: 'St Fillans Road',
          postcode: 'SE6 1DQ',
        ),
        'street',
      );
    });

    test('zero, NaN, infinite, and outside-UK coordinates are blocked', () {
      expect(isSenderValidUkCoordinate(0, 0), isFalse);
      expect(isSenderValidUkCoordinate(double.nan, -0.1), isFalse);
      expect(isSenderValidUkCoordinate(51.4, double.infinity), isFalse);
      expect(isSenderValidUkCoordinate(40.7, -73.9), isFalse);
    });
  });

  group('Sender booking map route authority', () {
    test('accepts current Croydon route polyline', () {
      const pickup = LatLng(51.4329, -0.0205);
      const dropoff = LatLng(51.3737, -0.1004);
      const points = [
        LatLng(51.4329, -0.0205),
        LatLng(51.4050, -0.0600),
        LatLng(51.3737, -0.1004),
      ];

      expect(
        senderBookingPolylineMatchesRoute(points, pickup, dropoff),
        isTrue,
      );
    });

    test('rejects stale north London polyline for Croydon booking', () {
      const pickup = LatLng(51.4329, -0.0205);
      const dropoff = LatLng(51.3737, -0.1004);
      const staleNorthLondon = [
        LatLng(51.6850, -0.0350),
        LatLng(51.6500, -0.0800),
        LatLng(51.6170, -0.0300),
      ];

      expect(
        senderBookingPolylineMatchesRoute(staleNorthLondon, pickup, dropoff),
        isFalse,
      );
    });
  });
}
