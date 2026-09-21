import 'dart:convert';

import 'package:circum/app/send_package/repo/address_places_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'address transport uses Cloud Run callable envelope and security headers',
    () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'result': {'status': 'OK', 'results': <Map<String, dynamic>>[]},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final result = await invokeAddressPlaces(
        'searchFreeUkAddresses',
        {'query': 'SW1A 2AA'},
        idToken: 'id-token',
        appCheckToken: 'app-check-token',
        client: client,
      );

      expect(result['status'], 'OK');
      expect(captured.url.host, contains('circum-address-places'));
      expect(captured.url.path, '/searchFreeUkAddresses');
      expect(captured.headers['authorization'], 'Bearer id-token');
      expect(captured.headers['x-firebase-appcheck'], 'app-check-token');
      expect(jsonDecode(captured.body), {
        'data': {'query': 'SW1A 2AA'},
      });
    },
  );

  test('address transport preserves structured callable errors', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'error': {
            'status': 'UNAVAILABLE',
            'message': 'Address search is unavailable.',
          },
        }),
        503,
      ),
    );

    expect(
      () => invokeAddressPlaces(
        'resolveUkAddressPlace',
        {'placeId': 'place-1'},
        idToken: 'id-token',
        appCheckToken: 'app-check-token',
        client: client,
      ),
      throwsA(
        isA<AddressPlacesException>().having(
          (error) => error.status,
          'status',
          'UNAVAILABLE',
        ),
      ),
    );
  });

  test('client source contains no Google server credential', () {
    const source = addressPlacesServiceUrl;
    expect(source, isNot(contains('AIza')));
    expect(source, isNot(contains('BACKEND_GOOGLE_PLACES_API_KEY')));
  });
}

