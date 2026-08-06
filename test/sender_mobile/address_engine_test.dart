import 'package:flutter_test/flutter_test.dart';

import 'package:circum/app/platform/address_engine.dart';

void main() {
  test('canonical address requires coordinates for a place-backed result', () {
    final incomplete = AddressEngine.normalize(
      components: {
        'addressLine1': '29 St Fillans Road',
        'city': 'London',
        'postcode': 'SE6 1DQ',
        'country': 'United Kingdom',
        'placeId': 'google-place-1',
      },
    );
    expect(AddressEngine.isCanonical(incomplete), isFalse);

    final complete = AddressEngine.normalize(
      components: {
        ...incomplete,
        'latitude': 51.4401,
        'longitude': -0.0258,
        'provider': 'google_places',
      },
    );
    expect(AddressEngine.isCanonical(complete), isTrue);
    expect(complete['provider'], 'google_places');
  });

  test('manual addresses remain canonical without a place identifier', () {
    final address = AddressEngine.normalize(
      manualAddress: '10 Downing Street, London, SW1A 2AA, United Kingdom',
    );
    expect(AddressEngine.isCanonical(address), isTrue);
    expect(address['placeId'], isNull);
  });

  test('backend provenance is preserved when nested components are absent', () {
    final suggestion = AddressEngine.suggestionFromBackend({
      'placeId': 'google-place-1',
      'displayAddress': '29 St Fillans Road, London SE6 1DQ, UK',
      'provider': 'google_places',
      'lat': 51.4401,
      'lng': -0.0258,
      'components': {
        'addressLine1': '29 St Fillans Road',
        'city': 'London',
        'postcode': 'SE6 1DQ',
        'country': 'United Kingdom',
      },
    });
    final address = AddressEngine.normalize(suggestion: suggestion);
    expect(address['provider'], 'google_places');
    expect(AddressEngine.isCanonical(address), isTrue);
  });
}
