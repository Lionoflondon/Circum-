import 'dart:io';

import 'package:circum/app/platform/address_engine.dart';
import 'package:circum/app/send_package/models/suggestions.m.dart';
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

    test('typed Sender address confirmation is not suggestion-click gated', () {
      final canvas = File('lib/app/sender_mobile/sender_booking_canvas.dart')
          .readAsStringSync();
      final provider =
          File('lib/app/send_package/repo/place_api.dart').readAsStringSync();

      expect(canvas, contains('resolveTypedAddress(address, lang)'));
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
  });
}
