import 'package:flutter_test/flutter_test.dart';

import 'package:circum/app/platform/address_engine.dart';
import 'package:circum/app/send_package/models/suggestions.m.dart';

Suggestion suggestion({double? lat, double? lng}) => Suggestion(
      placeId: 'fixture-place',
      description: '29 St Fillans Road, London, SE6 1DQ, United Kingdom',
      mainText: '29 St Fillans Road',
      subText: 'London, SE6 1DQ, United Kingdom',
      lat: lat,
      lng: lng,
    );

void main() {
  test('resolved London Gift address enables the canonical address gate', () {
    expect(
        AddressEngine.hasResolvedUkCoordinates(
          suggestion(lat: 51.437, lng: -0.003),
        ),
        isTrue);
  });

  test('unresolved, zero, invalid and non-UK Gift addresses remain blocked',
      () {
    expect(AddressEngine.hasResolvedUkCoordinates(suggestion()), isFalse);
    expect(
        AddressEngine.hasResolvedUkCoordinates(
          suggestion(lat: 0, lng: 0),
        ),
        isFalse);
    expect(
        AddressEngine.hasResolvedUkCoordinates(
          suggestion(lat: double.nan, lng: -0.003),
        ),
        isFalse);
    expect(
        AddressEngine.hasResolvedUkCoordinates(
          suggestion(lat: 40.7, lng: -74.0),
        ),
        isFalse);
  });

  test('typed display text alone cannot satisfy the Gift address gate', () {
    expect(AddressEngine.hasResolvedUkCoordinates(null), isFalse);
  });
}
