import 'package:circum/app/platform/address_engine.dart';
import 'package:circum/app/send_package/models/suggestions.m.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('postcode extraction normalizes case and spacing without null errors',
      () {
    for (final value in ['SE6 1DQ', 'SE61DQ', 'se6 1dq', 'Se6 1Dq']) {
      expect(AddressEngine.extractUkPostcode(value), 'SE6 1DQ');
    }
    for (final value in [null, '', 'London', 'SE6']) {
      expect(AddressEngine.extractUkPostcode(value), isNull);
    }
  });

  test('only complete repeated components are collapsed', () {
    expect(
      AddressEngine.joinDistinctParts([
        '29 St Fillans Rd',
        '29 St Fillans Rd',
        'St Fillans',
        'London',
      ]),
      '29 St Fillans Rd, St Fillans, London',
    );
    expect(
      AddressEngine.joinDistinctParts(['London SE6 1DQ', 'London SE6 2DQ']),
      'London SE6 1DQ, London SE6 2DQ',
    );
  });

  test(
    'cleaning preserves place coordinates and structured locality fields',
    () {
      final result = AddressEngine.cleanSuggestion(
        Suggestion(
          placeId: 'authoritative-place',
          description: '29 St Fillans Rd, London SE6 1DQ, United Kingdom',
          mainText: '29 St Fillans Rd',
          subText: 'London SE6 1DQ',
          lat: 51.445,
          lng: -0.021,
          components: const {
            'streetNumber': '29',
            'route': 'St Fillans Rd',
            'locality': 'Catford',
            'postTown': 'London',
            'administrativeArea': 'Greater London',
            'postcode': 'SE6 1DQ',
            'country': 'United Kingdom',
          },
        ),
      );
      expect(result.placeId, 'authoritative-place');
      expect(result.lat, 51.445);
      expect(result.lng, -0.021);
      expect(result.components['route'], 'St Fillans Rd');
      expect(result.components['locality'], 'Catford');
      expect(result.components['postTown'], 'London');
      expect(result.components['administrativeArea'], 'Greater London');
    },
  );

  test('Google predictions do not duplicate the street line as the city', () {
    final suggestion = AddressEngine.cleanSuggestion(
      Suggestion(
        placeId: 'google-place-1',
        description: '29 St Fillans Rd, London SE6 1DQ, United Kingdom',
        mainText: '',
        subText: '',
        components: const {
          'addressLine1': '29 St Fillans Rd',
          'country': 'United Kingdom',
        },
      ),
    );

    expect(
      suggestion.description,
      '29 St Fillans Rd, London, SE6 1DQ, United Kingdom',
    );
    expect(suggestion.mainText, '29 St Fillans Rd');
    expect(suggestion.subText, 'London, SE6 1DQ, United Kingdom');
    expect(suggestion.components['city'], 'London');
    expect(suggestion.components['postcode'], 'SE6 1DQ');
  });

  test('Google predictions without postcode still keep the city clean', () {
    final suggestion = AddressEngine.cleanSuggestion(
      Suggestion(
        placeId: 'google-place-2',
        description: '124 City Road, London, United Kingdom',
        mainText: '',
        subText: '',
        components: const {
          'addressLine1': '124 City Road',
          'country': 'United Kingdom',
        },
      ),
    );

    expect(suggestion.description, '124 City Road, London, United Kingdom');
    expect(suggestion.subText, 'London, United Kingdom');
    expect(suggestion.components['city'], 'London');
    expect(suggestion.components.containsKey('postcode'), isFalse);
  });

  test('lookup input repairs previously duplicated address text', () {
    expect(
      AddressEngine.lookupInput(
        '29 St Fillans Rd, 29 St Fillans Rd, London SE6 1DQ, United Kingdom',
      ),
      '29 St Fillans Rd, London, SE6 1DQ, United Kingdom',
    );
  });
}
