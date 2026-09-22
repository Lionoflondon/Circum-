import 'dart:convert';
import 'dart:io';

import 'package:circum/website/shared/rider_delivery_authority_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('website Rider authority preserves Auth and App Check envelope',
      () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
          jsonEncode({
            'result': {'nearestRequests': []}
          }),
          200);
    });

    final result = await invokeRiderDeliveryAuthority(
      'getAvailableRequests',
      const {},
      idToken: 'id-token',
      appCheckToken: 'app-check-token',
      client: client,
    );

    expect(captured.url.host, contains('circum-rider-delivery-authority'));
    expect(captured.url.path, '/getAvailableRequests');
    expect(captured.headers['authorization'], 'Bearer id-token');
    expect(captured.headers['x-firebase-appcheck'], 'app-check-token');
    expect(jsonDecode(captured.body), {'data': {}});
    expect(result, {'nearestRequests': []});
  });

  test('all website Rider callers use migrated routes', () {
    final source =
        File('lib/website/shared/circum_website_app.dart').readAsStringSync();
    expect(source, isNot(contains("httpsCallable('getAvailableRequests')")));
    expect(
        source,
        contains(
            "callRiderDeliveryAuthority(\n          'getAvailableRequests'"));
    expect(source, contains("action == 'verify_receiver_pin'"));
    expect(source, contains("callRiderDeliveryAuthority('completeDelivery'"));
    expect(source, contains("httpsCallable('updateDeliveryTrackingStatus')"));
  });
}
